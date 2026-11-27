import BackgroundTasks
import Foundation
import UIKit

/// LAB, branch continued-task-lab (27 Nov 2026): keeps Ammy running in the
/// background with iOS 26's continued processing task instead of the silent
/// audio in KeepAlive.swift. This build never creates a KeepAlive, and
/// project.yml no longer declares the audio background mode, so nothing else
/// keeps the app running. The questions (HISTORY.md, 25 and 27 Nov 2026): how
/// long a task lasts through a normal day on the owner's phone, and whether a
/// new one can start once iOS has ended one in the background.
///
/// While a session runs, Ammy keeps one task running. It submits one when the
/// session starts, and again whenever none is running and the app comes to
/// the front, leaves it, goes to the background, sends a push or ticks. After
/// a refusal it waits 30 s, or a change of app state, before asking again.
/// The system shows the task as a Live Activity with a progress bar and a way
/// to cancel it. A task that reports no progress is ended, so every 10 s tick
/// adds one unit against a day's worth of units. When a task ends while a
/// session is on, Ammy submits a new one at once, wherever the app is.
///
/// The same calls as KeepAlive, so PresenceController changes in two lines.
/// The diagnostics reuse KeepAlive's keys, so Issun's existing lines show the
/// lab's events with no new Issun build. Read them this way:
///
///   engine      a task is running
///   want        a session wants one
///   resumes     tasks that have started running
///   fails       submissions iOS refused, and finding no identifier registered
///   heals       tasks that ended, by iOS or by the person cancelling
///   route       always "lab-task"
///   last_error  the newest event in words: a task started, ended or refused.
///               Issun logs each new one as a "resume failed:" line.
///   failstage   that event's kind: started, ended, submit or register
///
/// Everything it does also goes to the keepalive journal, whose last lines
/// reach Issun with the first push of the next process.
@MainActor
final class ContinuedTask {

    /// Units of progress in a day of 10 s ticks. When a task gets near the
    /// end of it, the total grows by another day rather than finishing.
    private static let unitsPerDay: Int64 = 8_640
    private static let tickInterval: TimeInterval = 10
    /// Ticks this far apart on the clock that stops while the phone sleeps
    /// mean the process wasn't running while the phone was awake.
    private static let frozenAfter: TimeInterval = 30
    /// How long a submission may wait for its task to start, and how long a
    /// refusal holds off the next try in the same app state.
    private static let retryAfter: TimeInterval = 30

    private static weak var live: ContinuedTask?

    /// Identifiers iOS agreed to register, best first, registered on first
    /// use. A static let runs once per process, and registering an identifier
    /// twice kills the app.
    ///
    /// SideStore renames the bundle ID to com.local.ammy.<TEAMID>, and a
    /// task's identifier has to begin with the bundle ID and be allowed by
    /// Info.plist, which SideStore may or may not rewrite. So the identifiers
    /// are built from the bundle ID the phone reports, with the plain ones as
    /// fallbacks, and the journal records which iOS took.
    private static let registered: [String] = {
        let bundle = Bundle.main.bundleIdentifier ?? "?"
        let permitted = (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]) ?? []
        var candidates: [String] = []
        for id in ["\(bundle).session", "\(bundle).session.lab", "com.local.ammy.session", "com.local.ammy.session.lab"]
            where !candidates.contains(id) {
            candidates.append(id)
        }

        var accepted: [String] = []
        var results: [String] = []
        for id in candidates {
            let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { task in
                MainActor.assumeIsolated {
                    guard let live = ContinuedTask.live else {
                        KeepAliveJournal.note("task \(task.identifier) started with nothing to run it; completing it")
                        task.setTaskCompleted(success: false)
                        return
                    }
                    live.launched(task)
                }
            }
            results.append("\(id) \(ok ? "yes" : "no")")
            if ok { accepted.append(id) }
        }
        KeepAliveJournal.note("bundle \(bundle); Info.plist permits \(permitted); registered: \(results.joined(separator: ", "))")
        return accepted
    }()

    /// The host the session sends to, which the Live Activity shows under its
    /// title. Set by PresenceController before start().
    var destination = ""

    private var wanted = false
    /// The running task and when it started.
    private var current: (task: BGContinuedProcessingTask, since: Date)?
    private var task: BGContinuedProcessingTask? { current?.task }
    private var submittedAt: Date?
    private var lastRefusal: (at: Date, state: String)?
    /// Which of `registered` submissions use. It moves on when iOS answers
    /// notPermitted, but only while the app is in front and before any task
    /// has run: in the background a refusal may only mean "not now".
    private var identifierIndex = 0
    private var identifierSettled = false
    /// How the last task ended, for the line that says the next one started.
    private var lastEnd: String?
    private var timer: Timer?
    private var lastTick: (wall: Date, awake: TimeInterval)?
    /// Set when the ticks show the process stopped while a task was thought
    /// to be running. Acted on when the app next comes to the front.
    private var taskDoubted = false
    private var observers: [NSObjectProtocol] = []
    private var diag = KeepAliveDiagnostics()

    init() {
        Self.live = self
        KeepAliveJournal.note("lab build: a continued processing task in place of the silent audio")
        _ = Self.registered
    }

    // MARK: - Lifecycle

    func start() {
        guard !wanted else { return }
        wanted = true
        observe()
        lastTick = Self.clocks()
        startTimer()
        KeepAliveJournal.note("start, app \(Self.appState)")
        submit(reason: "start")
    }

    func stop() {
        guard wanted else { return }
        wanted = false
        timer?.invalidate()
        timer = nil
        removeObservers()
        submittedAt = nil
        lastRefusal = nil
        taskDoubted = false
        if let current {
            KeepAliveJournal.note("stop: completing the task after \(Self.seconds(since: current.since))s")
            current.task.setTaskCompleted(success: true)
        } else {
            KeepAliveJournal.note("stop, no task was running")
        }
        current = nil
        diag.failRun = 0
        diag.downSince = nil
    }

    /// Called on every push.
    func verify() {
        submit(reason: "push")
    }

    var diagnostics: KeepAliveDiagnostics {
        diag.running = wanted
        diag.engineRunning = task != nil
        diag.nodePlaying = task != nil
        diag.secondsSinceResume = current.map { Date().timeIntervalSince($0.since) } ?? -1
        diag.route = "lab-task"
        return diag
    }

    // MARK: - Submitting

    /// Asks iOS for a task when a session wants one and none is running or
    /// waiting to start. Returns what happened in words, with the error code
    /// of a refusal.
    @discardableResult
    private func submit(reason: String) -> (text: String, code: Int?) {
        guard wanted else { return ("no session", nil) }
        guard task == nil else { return ("not needed", nil) }
        if let at = submittedAt, Date().timeIntervalSince(at) < Self.retryAfter {
            return ("one is waiting to start", nil)
        }
        let state = Self.appState
        if let refusal = lastRefusal, refusal.state == state,
           Date().timeIntervalSince(refusal.at) < Self.retryAfter {
            return ("waiting after a refusal", nil)
        }

        while identifierIndex < Self.registered.count {
            let id = Self.registered[identifierIndex]
            // Title-style, like a notification's title: Apple gives no rule
            // for a Live Activity's capitals, and its own apps' weren't
            // captured (interface-text rulebook). The subtitle is the address.
            let request = BGContinuedProcessingTaskRequest(identifier: id, title: "Sending to Endpoint", subtitle: destination)
            // Fail at once rather than wait in a queue, so the journal can say
            // whether iOS would start one at that moment.
            request.strategy = .fail
            // Set before submitting, in case iOS starts the task before
            // submit() returns.
            submittedAt = Date()
            do {
                try BGTaskScheduler.shared.submit(request)
                lastRefusal = nil
                KeepAliveJournal.note("submitted \(id) (\(reason), app \(state))")
                return ("submitted", nil)
            } catch {
                submittedAt = nil
                lastRefusal = (Date(), state)
                let ns = error as NSError
                let text = "refused, app \(state): \(Self.codeName(error)) [\(ns.domain) \(ns.code)] \(ns.localizedDescription)"
                refused(text: "submit " + text, code: ns.code, reason: reason)
                guard (error as? BGTaskScheduler.Error)?.code == .notPermitted, state == "active",
                      !identifierSettled, identifierIndex + 1 < Self.registered.count
                else { return (text, ns.code) }
                identifierIndex += 1
                KeepAliveJournal.note("trying the next identifier, \(Self.registered[identifierIndex])")
            }
        }
        lastRefusal = (Date(), state)
        refused(text: "no task identifier was registered", code: nil, reason: reason, stage: "register")
        return ("none registered", nil)
    }

    private func refused(text: String, code: Int?, reason: String, stage: String = "submit") {
        diag.resumeFailures += 1
        diag.failRun += 1
        diag.failRunMax = max(diag.failRunMax, diag.failRun)
        report(stage: stage, code: code, text: text)
        // Every one of the first three in a row, then every 30th, so a long
        // run of refusals doesn't push everything else out of the journal.
        if diag.failRun <= 3 || diag.failRun % 30 == 0 {
            KeepAliveJournal.note("\(text) (\(reason), \(diag.failRun) in a row)")
        }
    }

    /// Puts the newest event where Issun shows it: `last_error`, which Issun
    /// logs whenever it changes, with the event's kind and code beside it.
    private func report(stage: String, code: Int?, text: String) {
        diag.failStage = stage
        diag.failCode = code
        diag.lastFailAt = Date()
        diag.lastError = text
        if task == nil, diag.downSince == nil { diag.downSince = Date() }
    }

    // MARK: - The task

    private func launched(_ bgTask: BGTask) {
        guard let started = bgTask as? BGContinuedProcessingTask else {
            KeepAliveJournal.note("launch handler got a \(type(of: bgTask)), not a continued processing task; completing it")
            bgTask.setTaskCompleted(success: false)
            return
        }
        let waited = submittedAt.map { "\(Self.seconds(since: $0))s after submitting" } ?? "with no submission waiting"
        submittedAt = nil
        guard wanted else {
            KeepAliveJournal.note("task \(started.identifier) started after Stop; completing it")
            started.setTaskCompleted(success: true)
            return
        }
        if let old = task, old !== started {
            KeepAliveJournal.note("a second task started while one was running; completing the first")
            old.setTaskCompleted(success: true)
        }

        let down = diag.downSince.map { ", none for \(Self.seconds(since: $0))s before it" } ?? ""
        current = (started, Date())
        identifierSettled = true
        lastRefusal = nil
        taskDoubted = false
        diag.resumes += 1
        diag.failRun = 0
        diag.downSince = nil
        started.progress.totalUnitCount = Self.unitsPerDay
        started.progress.completedUnitCount = 0

        // Which queue iOS calls this on isn't documented, so the ending runs
        // on the main thread either way, before the handler returns.
        started.expirationHandler = { [weak self, weak started] in
            let end = {
                MainActor.assumeIsolated {
                    guard let self, let started else { return }
                    self.ended(started, how: "the expiration handler")
                }
            }
            if Thread.isMainThread { end() } else { DispatchQueue.main.sync(execute: end) }
        }

        let text = "task started \(waited), app \(Self.appState)\(down)" + (lastEnd.map { "; the last \($0)" } ?? "")
        lastEnd = nil
        KeepAliveJournal.note("\(text), \(started.identifier)")
        report(stage: "started", code: nil, text: text)
    }

    /// A task is over: iOS ended it, the person cancelled it (iOS doesn't say
    /// which), or the ticks showed the process had stopped under it. If a
    /// session still wants one, asks for a new one straight away, wherever
    /// the app is. Whether iOS agrees in the background is the lab's second
    /// question.
    private func ended(_ finished: BGContinuedProcessingTask, how: String) {
        guard let current, current.task === finished else {
            KeepAliveJournal.note("\(how) ran for a task already counted as over")
            return
        }
        let lived = Self.seconds(since: current.since)
        let progress = "\(finished.progress.completedUnitCount)/\(finished.progress.totalUnitCount)"
        let state = Self.appState
        self.current = nil
        taskDoubted = false
        diag.selfHeals += 1
        KeepAliveJournal.note("task ended through \(how) after \(lived)s, app \(state), locked \(Self.locked), progress \(progress)")
        finished.setTaskCompleted(success: false)

        let end = "ended through \(how) after \(lived)s, app \(state)"
        lastEnd = end
        let next = submit(reason: "the last one ended")
        // A task that started at once has said so already, with this ending.
        guard task == nil else { return }
        report(stage: next.code == nil ? "ended" : "ended, new one refused", code: next.code,
               text: "task \(end); a new one: \(next.text)")
    }

    /// Ends a task the ticks showed the process had stopped under, now that
    /// the app is in front and a new one can be asked for. It also measures
    /// the gap since the last tick itself, in case it runs before the first
    /// tick after a suspension.
    private func checkDoubtedTask() {
        guard let stale = task else { return }
        let awakeSinceTick = lastTick.map { Self.clocks().awake - $0.awake } ?? 0
        guard taskDoubted || awakeSinceTick > Self.frozenAfter else { return }
        ended(stale, how: "a stop the ticks found")
    }

    // MARK: - Tick

    private func startTimer() {
        timer?.invalidate()
        let ticker = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick()
            }
        }
        // A second of slack lets iOS fire it along with other timers.
        ticker.tolerance = 1
        // .common so it keeps firing while the UI is being scrolled.
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
    }

    private func tick() {
        let now = Self.clocks()
        if let last = lastTick, now.wall.timeIntervalSince(last.wall) > Self.frozenAfter {
            let awake = now.awake - last.awake
            // Logged, not acted on here: the expiration handler is what ends
            // a task. A gap with the phone awake means the process wasn't
            // running, so a task thought to be running is doubted until the
            // app comes to the front.
            if task != nil, awake > Self.frozenAfter { taskDoubted = true }
            KeepAliveJournal.note("ticks \(Int(now.wall.timeIntervalSince(last.wall)))s apart, \(Int(awake))s of it with the phone awake, task \(task == nil ? "none" : "thought to be running")")
        }
        lastTick = now

        if let task {
            let progress = task.progress
            progress.completedUnitCount += 1
            if progress.completedUnitCount >= progress.totalUnitCount - 1 {
                progress.totalUnitCount += Self.unitsPerDay
            }
        }

        // The last of these before a silence is when the process stopped
        // running, to within one tick; Issun prints it on the gap line.
        let running = current.map { "running \(Self.seconds(since: $0.since))s" } ?? "none"
        KeepAliveJournal.alive("task=\(running) app=\(Self.appState)")

        submit(reason: "tick")
    }

    // MARK: - What the app and phone are doing

    /// Each event watched, with the journal line it writes and, where a task
    /// may be needed, a submission.
    private static let watched: [(Notification.Name, @MainActor (ContinuedTask) -> Void)] = [
        (UIApplication.didBecomeActiveNotification, { lab in
            KeepAliveJournal.note("app in front, task \(lab.task == nil ? "none" : "running")")
            lab.checkDoubtedTask()
            lab.submit(reason: "app in front")
        }),
        (UIApplication.willResignActiveNotification, { lab in
            KeepAliveJournal.note("app leaving the front")
            lab.submit(reason: "app leaving the front")
        }),
        (UIApplication.didEnterBackgroundNotification, { lab in
            KeepAliveJournal.note("app in the background, task \(lab.task == nil ? "none" : "running"), background time left \(ContinuedTask.backgroundTimeLeft)")
            lab.submit(reason: "app in the background")
        }),
        (UIApplication.willEnterForegroundNotification, { _ in
            KeepAliveJournal.note("app coming to the front")
        }),
        (UIApplication.protectedDataWillBecomeUnavailableNotification, { _ in
            KeepAliveJournal.note("phone locked")
        }),
        (UIApplication.protectedDataDidBecomeAvailableNotification, { _ in
            KeepAliveJournal.note("phone unlocked")
        }),
        (UIApplication.didReceiveMemoryWarningNotification, { _ in
            KeepAliveJournal.note("memory warning")
        }),
        (.NSProcessInfoPowerStateDidChange, { _ in
            KeepAliveJournal.note("Low Power Mode \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")")
        }),
        (ProcessInfo.thermalStateDidChangeNotification, { _ in
            KeepAliveJournal.note("thermal state \(ProcessInfo.processInfo.thermalState.rawValue)")
        }),
    ]

    private func observe() {
        for (name, handle) in Self.watched {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    handle(self)
                }
            })
        }
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    // MARK: - Helpers

    /// The wall clock, and the device's uptime, which stops while the phone
    /// sleeps.
    private static func clocks() -> (wall: Date, awake: TimeInterval) {
        (Date(), ProcessInfo.processInfo.systemUptime)
    }

    private static var appState: String {
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    private static var locked: String {
        UIApplication.shared.isProtectedDataAvailable ? "no" : "yes"
    }

    private static var backgroundTimeLeft: String {
        let left = UIApplication.shared.backgroundTimeRemaining
        return left.isFinite && left < 100_000 ? "\(Int(left))s" : "unlimited"
    }

    private static func seconds(since date: Date?) -> Int {
        date.map { Int(Date().timeIntervalSince($0)) } ?? -1
    }

    private static func codeName(_ error: Error) -> String {
        guard let scheduler = error as? BGTaskScheduler.Error else { return "not a scheduler error" }
        switch scheduler.code {
        case .unavailable: return "unavailable"
        case .tooManyPendingTaskRequests: return "tooManyPendingTaskRequests"
        case .notPermitted: return "notPermitted"
        default: return "code \(scheduler.code.rawValue)"
        }
    }
}
