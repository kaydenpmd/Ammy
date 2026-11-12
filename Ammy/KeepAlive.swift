import AVFoundation
import Foundation

/// A snapshot of the keepalive's health, sent to the relay on every push.
///
/// This exists because the app cannot report its own death. The receiver only
/// ever sees that pushes stopped, never why — so the last snapshot before the
/// silence is the only evidence there will be. `UptimeLog.NoteSilence` in Issun
/// prints it onto the "phone stopped checking in" line for exactly that reason.
///
/// `running` is what this class *believes*; `engineRunning` is what
/// `AVAudioEngine` actually reports. When those two disagree the keepalive is
/// dead and the app is living on borrowed background time.
struct KeepAliveDiagnostics: Sendable {
    var running = false
    var engineRunning = false
    var nodePlaying = false

    var resumes = 0
    var resumeFailures = 0
    var lastError: String?

    /// Which step of `resume()` failed last, its error code, and when. Unlike
    /// `lastError`, which the next success clears, these stay, so a push after
    /// a recovery still says what the last failure was. Before Nov 2026 only
    /// the error's description was sent: 4 Nov's carried its code because
    /// AVFAudio's description happens to include it, and "Session activation
    /// failed" never did, so eleven setActive failures can't say which refusal
    /// they were.
    var failStage: String?
    var failCode: Int?
    var lastFailAt: Date?
    /// Failed tries since the silence last played, and the most in one run.
    var failRun = 0
    var failRunMax = 0
    /// When the engine was first found down, for as long as it stays down.
    var downSince: Date?

    var interruptionsBegan = 0
    var interruptionsEnded = 0
    /// `.began` notices marked as delivered late because iOS had suspended the
    /// app. Each one proves a suspension, and none of them gets an `.ended`, so
    /// they're counted apart from the rest.
    var interruptionsOnResume = 0
    /// AVAudioSessionInterruptionReasonKey of the last `.began`, raw.
    var lastInterruptionReason: Int?
    var lastBeganAt: Date?
    var lastEndedAt: Date?
    var configChanges = 0
    var routeChanges = 0
    var mediaResets = 0
    var selfHeals = 0

    var secondsSinceResume: Double = -1
    var route = "?"

    var dictionary: [String: Any] {
        var d: [String: Any] = [
            "running": running,
            "engine_running": engineRunning,
            "node_playing": nodePlaying,
            "resumes": resumes,
            "resume_failures": resumeFailures,
            "int_began": interruptionsBegan,
            "int_ended": interruptionsEnded,
            "config_changes": configChanges,
            "route_changes": routeChanges,
            "media_resets": mediaResets,
            "self_heals": selfHeals,
            "secs_since_resume": Int(secondsSinceResume),
            "route": route,
            "fail_run": failRun,
            "fail_run_max": failRunMax,
            "int_on_resume": interruptionsOnResume,
        ]
        if let lastError { d["last_error"] = lastError }
        if let failStage { d["fail_stage"] = failStage }
        if let failCode { d["fail_code"] = failCode }
        if let lastInterruptionReason { d["int_reason"] = lastInterruptionReason }
        let now = Date()
        func ago(_ date: Date?) -> Int? { date.map { Int(now.timeIntervalSince($0)) } }
        if let s = ago(lastFailAt) { d["secs_since_fail"] = s }
        if let s = ago(downSince) { d["down_s"] = s }
        if let s = ago(lastBeganAt) { d["secs_since_began"] = s }
        if let s = ago(lastEndedAt) { d["secs_since_ended"] = s }
        return d
    }
}

/// iOS suspends foreground apps after ~30 seconds. The standard (if grubby)
/// workaround is to claim the `audio` background mode and play silence.
/// `.mixWithOthers` is essential — without it this fights Apple Music for the
/// audio session and stops your actual playback.
///
/// This is exactly the sort of thing App Review rejects. Fine for sideloading.
///
/// The silence has to *keep* playing. Anything that stops the engine ends the
/// app's justification for background time, and iOS suspends and then kills it
/// minutes to hours later. That reads as "iOS is being aggressive" rather than
/// as a bug, which is what makes this class worth its length.
///
/// Four things stop the engine, and all four are handled below:
///
///   1. An interruption — a call, an alarm, Siri.
///   2. A media services reset, after which every audio object is invalid.
///   3. **A configuration change.** `AVAudioEngine` stops itself whenever the
///      audio route changes: AirPods connecting, headphones going in, CarPlay,
///      a Bluetooth speaker. This one has no `.ended` counterpart to wait for
///      and was unhandled until Sept 2026, which is the likeliest explanation
///      for the app dying within the hour during a normal day while surviving
///      fourteen hours untouched overnight.
///   4. A `resume()` that simply fails — the session refuses to activate, or
///      the engine refuses to start.
///
/// The design rule here: **never conclude that the keepalive is off.** Nothing
/// in this class gives up. `running` means "we want silence playing"; a failure
/// leaves it true and tries again. Before Sept 2026 a failed `resume()` at
/// startup returned early with `running` still false, so the observers were
/// never installed and nothing ever retried — the app then ran with no
/// keepalive at all and nothing anywhere said so.
///
/// **Every retry here needs a running process**, and a backgrounded app whose
/// silence has stopped is suspended within seconds. On 4 Nov 2026 an
/// interruption stopped the engine, the push's own `verify()` found it,
/// `setActive` succeeded, `engine.start()` refused ('what'), and that one try
/// was the last: iOS suspended Ammy before the 10 s timer or the next push
/// could run, and nothing ran it again. 17 Sept had the same shape with a
/// refused `setActive`. Since Nov 2026 a refused `engine.start()` makes the
/// next try build a fresh engine, and `KeepAliveJournal` writes down what
/// happens after the last push that got through, so the next launch can say.
/// Holding a background task through the retries was built and lab-tested on
/// 11 Nov 2026 and not shipped: reopening one after iOS's deadline, or an
/// audio call blocking the main thread past it, gets the app killed outright
/// rather than suspended (CLAUDE.md, "The keepalive hold, parked").
final class KeepAlive {

    // Recreated wholesale after a media services reset, a configuration
    // change, or an engine that refused to start, so these are `var`.
    private var engine = AVAudioEngine()
    private var node = AVAudioPlayerNode()

    private var running = false
    private var wired = false
    private var observers: [NSObjectProtocol] = []
    private var healthTimer: Timer?

    private var diag = KeepAliveDiagnostics()
    private var lastResumeAt: Date?

    /// Set when `engine.start()` refused with the session up. The graph it
    /// refused with was built before whatever stopped it, so the next try
    /// builds a new one, as a configuration change already does. A fresh
    /// engine is the cure usually reported for 'what' after an interruption.
    private var freshGraphNext = false

    /// How often to confirm the engine is still running. The relay's heartbeat
    /// is 30s, so this is deliberately tighter: a stopped engine should be
    /// caught and restarted well inside one push interval.
    private let verifyInterval: TimeInterval = 10

    // MARK: - Lifecycle

    func start() {
        guard !running else { return }

        // Set before resuming, and left set even if resuming fails. The
        // observers and the verify timer are what make recovery possible, so
        // they must be installed whether or not the first attempt works.
        running = true
        observe()
        startHealthTimer()
        KeepAliveJournal.note("start")
        resume()
    }

    func stop() {
        guard running else { return }
        running = false
        freshGraphNext = false
        diag.failRun = 0
        diag.downSince = nil
        healthTimer?.invalidate()
        healthTimer = nil
        removeObservers()
        node.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        KeepAliveJournal.note("stop")
        refreshDiagnostics()
    }

    /// Current health. Reads live state from the engine rather than trusting
    /// anything cached — the whole point is to catch the case where this class
    /// thinks it is running and the engine disagrees.
    var diagnostics: KeepAliveDiagnostics {
        refreshDiagnostics()
        return diag
    }

    /// Cheap "is it still up?" check that callers can invoke opportunistically.
    /// `PresenceController` calls this on every push, so the engine gets
    /// checked at least every 30s even if the timer is throttled while the app
    /// is in the background.
    func verify() {
        guard running else { return }
        if !engine.isRunning || !node.isPlaying {
            diag.selfHeals += 1
            if diag.downSince == nil { diag.downSince = Date() }
            KeepAliveJournal.note("verify: engine \(engine.isRunning ? "running, node silent" : "stopped")")
            attempt()
        }
    }

    // MARK: - Recovery

    /// One try: from a new graph if the last one got as far as the engine and
    /// it refused, otherwise as `resume()` always has.
    private func attempt() {
        if freshGraphNext { rebuild() } else { resume() }
    }

    /// Bring session and engine back up. Idempotent, so it serves as the
    /// initial start, the interruption recovery, and the self-heal.
    @discardableResult
    private func resume() -> Bool {
        // Already healthy — don't schedule a second looping buffer onto a node
        // that is already playing one.
        if engine.isRunning && node.isPlaying {
            recovered()
            refreshDiagnostics()
            return true
        }

        let session = AVAudioSession.sharedInstance()

        // These were `try?` until Sept 2026. A session that refuses to activate
        // is the single most likely cause of a silent keepalive death, and
        // discarding the error meant there was nothing to read afterwards.
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            return fail("setCategory", error)
        }
        do {
            try session.setActive(true)
        } catch {
            return fail("setActive", error)
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)
        else {
            return fail("buffer", nil)
        }
        buffer.frameLength = buffer.frameCapacity // zero-filled = one second of silence

        // Attach and connect once per engine instance; doing it repeatedly on a
        // live graph is an error.
        if !wired {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            wired = true
        }
        engine.mainMixerNode.outputVolume = 0

        do {
            try engine.start()
        } catch {
            return fail("engine.start", error)
        }

        node.scheduleBuffer(buffer, at: nil, options: .loops)
        node.volume = 0
        node.play()

        diag.resumes += 1
        diag.lastError = nil
        lastResumeAt = Date()
        if let since = diag.downSince {
            KeepAliveJournal.note("playing again after \(diag.failRun) failed tries, down \(Int(Date().timeIntervalSince(since)))s")
        }
        recovered()
        refreshDiagnostics()
        return true
    }

    /// The silence is playing: the run of failures is over.
    private func recovered() {
        diag.failRun = 0
        diag.downSince = nil
    }

    /// Record a failure and leave `running` alone: never conclude the keepalive
    /// is off. The next try comes from the 10 s timer, the next push or an
    /// `.ended`; the relay sees `resume_failures` climbing and `last_error`
    /// explaining why.
    private func fail(_ stage: String, _ error: Error?) -> Bool {
        diag.resumeFailures += 1
        diag.failRun += 1
        diag.failRunMax = max(diag.failRunMax, diag.failRun)
        diag.failStage = stage
        diag.lastFailAt = Date()
        if diag.downSince == nil { diag.downSince = Date() }
        if let error {
            let ns = error as NSError
            diag.failCode = ns.code
            // The old wording with the code added, so Issun's "resume failed:"
            // lines read as they always have and carry the code with no change
            // on Issun's side.
            diag.lastError = "\(stage): \(ns.localizedDescription) [\(ns.code)\(Self.fourCC(ns.code))]"
        } else {
            diag.failCode = nil
            diag.lastError = "\(stage): could not build silence buffer"
        }
        if stage == "engine.start" { freshGraphNext = true }
        KeepAliveJournal.note("failed, \(diag.failRun) in a row: \(diag.lastError ?? stage)")
        refreshDiagnostics()
        return false
    }

    /// Tear the audio graph down and build a fresh one. Required after a media
    /// services reset (every audio object is invalid), the safest response to
    /// a configuration change, where the hardware format may have changed
    /// underneath an existing connection, and the next try after an engine
    /// that refused to start.
    private func rebuild() {
        freshGraphNext = false
        node.stop()
        engine.stop()
        engine = AVAudioEngine()
        node = AVAudioPlayerNode()
        wired = false
        resume()
    }

    /// " '!pri'" for 561017449, " 'what'" for 2003329396, nothing for codes
    /// that aren't four printable characters.
    private static func fourCC(_ code: Int) -> String {
        let n = UInt32(truncatingIfNeeded: code)
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: n >> $0) }
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return "" }
        return " '\(String(decoding: bytes, as: UTF8.self))'"
    }

    // MARK: - Observers

    private func observe() {
        let nc = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session, queue: .main
        ) { [weak self] note in
            guard let self, self.running else { return }
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }

            if type == .began {
                // Counted but not acted on: the engine is already stopped by
                // the system. Worth recording because `.ended` is NOT
                // guaranteed to arrive — if the interruption finishes while the
                // app is suspended iOS may never send it. A began count that
                // outruns the ended count is that happening, and is why
                // recovery can no longer depend on `.ended` alone.
                self.diag.interruptionsBegan += 1
                self.diag.lastBeganAt = Date()
                if let reason = note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt {
                    self.diag.lastInterruptionReason = Int(reason)
                }
                // Read by name: the constant is deprecated, but iOS documents it
                // as the mark on a late "you were suspended" notice.
                let onResume = (note.userInfo?["AVAudioSessionInterruptionWasSuspendedKey"] as? Bool) == true
                if onResume { self.diag.interruptionsOnResume += 1 }
                KeepAliveJournal.note("interruption began" + (onResume ? " (delivered late: the app had been suspended)" : "")
                    + ", reason \(self.diag.lastInterruptionReason.map(String.init) ?? "-")")
                self.refreshDiagnostics()
                return
            }

            // Deliberately ignoring `shouldResume`: that hint is about whether
            // *media* should resume. This is a keepalive, and it always should.
            self.diag.interruptionsEnded += 1
            self.diag.lastEndedAt = Date()
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:))
            KeepAliveJournal.note("interruption ended, shouldResume \(options?.contains(.shouldResume) == true)")
            // Through attempt(), so a refused engine is rebuilt first.
            self.attempt()
        })

        // Media services can be reset out from under the app. Every audio
        // object is invalid afterwards, so rebuild the graph rather than
        // restarting the dead one.
        observers.append(nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session, queue: .main
        ) { [weak self] _ in
            guard let self, self.running else { return }
            self.diag.mediaResets += 1
            KeepAliveJournal.note("media services reset")
            self.rebuild()
        })

        // The gap that mattered. AVAudioEngine posts this and stops itself when
        // the route changes; there is no paired "ended" event, so without this
        // observer the silence simply never comes back. `object: nil` because
        // `rebuild()` replaces the engine instance and an observer bound to the
        // old one would go deaf after the first recovery.
        observers.append(nc.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.running else { return }
            self.diag.configChanges += 1
            KeepAliveJournal.note("configuration change")
            self.rebuild()
        })

        // Not acted on — the configuration change above is what actually stops
        // the engine. Counted so the log can show whether deaths line up with
        // headphones and Bluetooth coming and going.
        observers.append(nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session, queue: .main
        ) { [weak self] _ in
            guard let self, self.running else { return }
            self.diag.routeChanges += 1
            self.refreshDiagnostics()
        })
    }

    private func removeObservers() {
        let nc = NotificationCenter.default
        observers.forEach(nc.removeObserver)
        observers.removeAll()
    }

    /// Each tick also stamps the time and the engine's state on disk. A
    /// suspended or killed process writes nothing, so the last stamp says when
    /// it stopped running, to within one tick.
    private func startHealthTimer() {
        healthTimer?.invalidate()
        let timer = Timer(timeInterval: verifyInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.verify()
            KeepAliveJournal.alive("engine=\(self.engine.isRunning ? "yes" : "no")")
        }
        // .common so it keeps firing while the UI is being scrolled.
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    // MARK: - Diagnostics

    private func refreshDiagnostics() {
        diag.running = running
        diag.engineRunning = engine.isRunning
        diag.nodePlaying = node.isPlaying
        diag.secondsSinceResume = lastResumeAt.map { Date().timeIntervalSince($0) } ?? -1
        diag.route = AVAudioSession.sharedInstance()
            .currentRoute.outputs.first?.portType.rawValue ?? "none"
    }

    deinit {
        healthTimer?.invalidate()
        let nc = NotificationCenter.default
        observers.forEach(nc.removeObserver)
    }
}
