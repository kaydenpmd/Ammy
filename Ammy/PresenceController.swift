import Foundation
import Combine
import UIKit

@MainActor
final class PresenceController: ObservableObject {
    @Published var endpoint = UserDefaults.standard.string(forKey: "relay_endpoint") ?? ""
    /// Reads the old `relay_secret` entry if the new one is absent, so a build
    /// that predates the rename doesn't lose a key the owner already typed in.
    @Published var key = UserDefaults.standard.string(forKey: "relay_key")
        ?? UserDefaults.standard.string(forKey: "relay_secret")
        ?? ""
    @Published private(set) var linkStatus = "Disconnected"

    /// True from starting until the first push comes back — the window where
    /// the link's real state isn't known yet.
    ///
    /// Worth a flag of its own rather than another `linkStatus` string.
    /// "Connected" used to be set the moment start() finished, before anything
    /// had been sent, which made a session whose first push never returned
    /// indistinguishable from a healthy one. linkStatus now only ever says
    /// what has been confirmed; this says whether confirming is still in
    /// flight.
    @Published private(set) var resolving = false

    /// Whether a session exists right now. The view reads this rather than
    /// keeping its own copy, because the session can now end without the view
    /// asking — a failed push tears it down, and a button holding its own
    /// belief would go on offering to stop something already gone.
    @Published private(set) var isRunning = false

    /// A terminal failure waiting to be shown as a popup, or nil.
    ///
    /// Only set while someone is actually looking. If the app leaves the
    /// screen with one still here it becomes a notification instead — see
    /// appDidEnterBackground().
    @Published var pendingFailure: FailureNotice?

    /// Which session a push belongs to. start() and stop() both bump it, so a
    /// request still in the air when a session ends can tell that it has been
    /// orphaned and keep its hands off the UI.
    ///
    /// Cancelling the task wouldn't be enough on its own: by the time stop()
    /// runs it is already past its last cancellation point, suspended on the
    /// network. This is checked at the moment of writing instead, which is the
    /// only moment that matters.
    private var session = 0

    /// What the *running* session is actually sending to, as opposed to what is
    /// currently typed into the fields. Empty while stopped.
    ///
    /// The difference between these and `endpoint`/`key` is the whole definition
    /// of "you edited this while it was running". Comparing against the live
    /// config rather than setting a flag on edit matters: type a character and
    /// delete it again and there is nothing left over, because the strings match
    /// once more.
    @Published private(set) var activeEndpoint = ""
    @Published private(set) var activeKey = ""

    /// How long to wait before the next push.
    ///
    /// Thirty seconds while healthy; much sooner while reconnecting, because a
    /// handover resolves in seconds and waiting out a full heartbeat to notice
    /// would make a two-second blip look like half a minute of downtime.
    private func nextDelay() -> TimeInterval {
        guard failureRun > 0 else { return 30 }
        // 2, 5, 10, 20, then 30 forever — quick enough to catch a handover,
        // slow enough that a genuinely dead relay isn't hammered for the whole
        // retry window.
        let ladder: [TimeInterval] = [2, 5, 10, 20]
        return failureRun <= ladder.count ? ladder[failureRun - 1] : 30
    }

    /// How long an established session keeps trying before it gives up.
    ///
    /// GUESS: 20 minutes. Chosen from ammy-uptime.log rather than invented —
    /// every interruption that healed on its own was back inside 15m30s, and
    /// this clears the longest of them with margin. Nothing documents it.
    private static let retryWindow: TimeInterval = 20 * 60

    /// What to do about a push that failed.
    ///
    /// Never connected: the address or the key is wrong, so say so now. Was
    /// connected: hold the session open, keep trying, and stay quiet — the
    /// person does not need telling about a wi-fi handover. Only when the
    /// window runs out does it become news.
    private func handleFailure(_ outcome: PushOutcome) {
        failureRun += 1

        guard everConnected else {
            return teardown(reason: outcome.notice)
        }

        if retryUntil == nil {
            retryUntil = Date().addingTimeInterval(Self.retryWindow)
            events.record(.interrupted, summary: outcome.summary)
        }

        guard let deadline = retryUntil, Date() < deadline else {
            return teardown(reason: outcome.notice)
        }

        // Same treatment as the first connect: a wait in progress is a
        // spinner, not a word. The string is still set — if the spinner ever
        // stopped covering it, the row should fall back to something true
        // rather than to whatever it happened to be showing beforehand.
        linkStatus = "Reconnecting"
        resolving = true

        // The app is alive and working, which is the only thing the watchdog
        // claims to measure — its notice says "Ammy isn't running", and firing
        // that mid-reconnect would be simply untrue. Postponing on liveness
        // rather than on success also stops it colliding with the give-up
        // notice at the end of the window.
        watchdog.postpone()
    }

    /// A push landed.
    private func handleSuccess() {
        if failureRun > 0, everConnected {
            events.record(.recovered, summary: "Reconnected")
        }
        failureRun = 0
        retryUntil = nil
        everConnected = true
        notifyRegardless = false
        linkStatus = "Connected"
        resolving = false
        watchdog.postpone()
    }

    /// Record a failure and put it in front of someone, without putting it on
    /// the row.
    ///
    /// The row reports *state* — Disconnected, Connecting, Connected,
    /// Reconnecting — and nothing else. A reason is not a state: it describes
    /// one moment in the past, while the row describes now, and parking one in
    /// the other leaves the screen asserting something that stopped being true
    /// the instant it appeared. Reasons live in the alert, the notification
    /// and the history, all three of which are timestamped or dismissible.
    private func fail(_ reason: FailureNotice) {
        linkStatus = "Disconnected"
        events.record(.failed, summary: reason.summary)
        announce(reason)
    }

    /// Put a terminal failure in front of the person.
    ///
    /// A first push that never landed and a reconnect that ran out of road are
    /// the same news — the link is down and will not come back by itself — so
    /// they get the same treatment. The only thing that varies is where it can
    /// be seen: a popup if anyone is looking, a notification if not.
    ///
    /// Interruptions deliberately do not come through here. Those are expected
    /// and self-healing, and announcing every wi-fi handover would teach
    /// people to ignore the ones that matter.
    private func announce(_ notice: FailureNotice) {
        let canBeSeen = UIApplication.shared.applicationState == .active
        if canBeSeen && !notifyRegardless {
            pendingFailure = notice
        } else {
            watchdog.reportFailure(notice)
        }
        notifyRegardless = false
    }

    /// Whether this connection attempt should skip the popup entirely.
    ///
    /// Set by opening `ammy://notify`, which is what a Shortcut uses when it
    /// is going to switch away from Ammy immediately. Being frontmost at the
    /// instant of failure is then not the same as being *looked at*, and no
    /// amount of guessing from scene phase can tell the difference — so the
    /// launch says so outright instead. One-shot: it describes the attempt it
    /// was opened for, and nothing after.
    private var notifyRegardless = false

    /// A start() is in progress; see the guard at its top.
    private var starting = false

    func suppressNextPopup() {
        notifyRegardless = true
    }

    func dismissFailure() {
        pendingFailure = nil
    }

    /// A popup nobody saw is not a notification.
    ///
    /// If the app leaves the screen with one still up, convert it. This is the
    /// case where Ammy is launched by a Shortcut, fails while technically
    /// frontmost, and is switched away from a frame later — the alert would
    /// have been drawn to an empty room and then thrown away with the
    /// screenful it was on.
    func appDidEnterBackground() {
        // The notify flag's job ends here: from now on nobody can see a popup,
        // so announce() sends a notification anyway. Left set, it outlived the
        // launch it was for — when no connection attempt followed the open —
        // and turned a later failure the person was watching into a
        // notification instead of the popup.
        notifyRegardless = false

        guard let pending = pendingFailure else { return }
        pendingFailure = nil
        watchdog.reportFailure(pending)
    }

    /// Called whenever the app comes to the front, to retract any notification
    /// that has already fired. Opening the app answers what they were asking.
    func appDidBecomeActive() {
        watchdog.clearDelivered()
    }

    /// Whether the fields have drifted from what is being sent.
    ///
    /// Deliberately says nothing about whether anything is running — the view
    /// owns that, and combining the two here would mean two sources of truth for
    /// the same fact.
    var configChanged: Bool {
        endpoint != activeEndpoint || key != activeKey
    }

    let monitor = NowPlayingMonitor()

    /// Every failure that reached the status row, kept for the history screen.
    let events = EventLog()

    private let keepAlive = KeepAlive()
    private let watchdog = SilenceWatchdog()
    private var relay: PresenceRelay?
    private var bag = Set<AnyCancellable>()
    private var heartbeat: Task<Void, Never>?

    /// Whether this session has ever had a push land.
    ///
    /// The whole distinction the retry logic turns on. A first push that fails
    /// means the configuration is wrong — a bad key, a bad address, nothing
    /// listening — and retrying a wrong answer just produces it again, so that
    /// fails loudly and at once. A push that fails *after* one succeeded means
    /// the configuration is known good and something transient happened to the
    /// path, which is worth waiting out rather than announcing.
    private var everConnected = false

    /// How many pushes have failed in a row. Drives the retry spacing.
    private var failureRun = 0

    /// When to give up on an interrupted session. Set on the first failure
    /// after a good push, cleared whenever one lands.
    private var retryUntil: Date?
    private var correction: Task<Void, Never>?

    init() {
        // Nested ObservableObjects don't bubble. Without this, a view watching
        // the controller never hears that the monitor changed, and the rows
        // reading it refresh only by luck, when something else on the
        // controller happens to publish. That luck ran out the moment Now
        // Playing stopped depending on a push.
        monitor.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &bag)

        events.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &bag)

        monitor.$track
            .combineLatest(monitor.$isPlaying)
            // `explicit` beside the key, not in it: the clean and explicit
            // editions of a song share a title, artist and album, so moving
            // from one to the other would otherwise wait for the next
            // heartbeat to say so. The key stays what the cover is cached by.
            .removeDuplicates {
                $0.0?.key == $1.0?.key && $0.0?.explicit == $1.0?.explicit && $0.1 == $1.1
            }
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                // Deliberately ignore the captured values and re-read current
                // state at send time; see sendNow().
                self?.handleChange()
            }
            .store(in: &bag)
    }

    /// Starts a session. Whether one began is readable from `isRunning`,
    /// which also covers the session ending later without being asked to.
    ///
    /// Every failure below leaves something on screen that explains itself: a
    /// failure notice, or the access prompt at the top of the screen.
    func start() async {
        // One at a time. start() awaits twice before it sets isRunning, and
        // coming to the front now autostarts as well as launching does — so
        // without this, a launch could start two sessions at once, each with
        // its own heartbeat loop pushing forever.
        guard !starting, !isRunning else { return }
        starting = true
        defer { starting = false }

        // Distinguish "you typed http" from "that isn't an address at all".
        // iOS blocks plain HTTP at the network layer anyway, so without this the
        // failure surfaces as an unreachable endpoint — which is the same
        // message a dead receiver produces, and exactly the ambiguity worth
        // avoiding.
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") {
            fail(FailureNotice(
                summary: "HTTPS Required",
                explanation: "Ammy only sends over HTTPS, because iOS blocks plain HTTP. Change the start of the URL to https://."))
            return
        }

        guard let resolved = PresenceRelay.normalised(trimmed),
              let relay = PresenceRelay(endpoint: trimmed, key: key)
        else {
            fail(FailureNotice(
                summary: "Invalid Address",
                explanation: "That URL can't be used. Check that it's a complete web address."))
            return
        }

        // Store and display what will actually be used, not what was typed. If a
        // scheme was added, the field visibly changes to match — the person is
        // never left believing Ammy is sending somewhere it isn't.
        endpoint = resolved.absoluteString
        UserDefaults.standard.set(endpoint, forKey: "relay_endpoint")
        UserDefaults.standard.set(key, forKey: "relay_key")

        // Snapshot what this session is actually using. Taken after the scheme
        // has been resolved, so an endpoint typed without https compares equal
        // to itself afterwards rather than reading as an edit.
        activeEndpoint = endpoint
        activeKey = key

        self.relay = relay
        keepAlive.start()

        // Before anything can be scheduled. An unauthorized center accepts
        // notification requests and delivers none of them, so skipping this
        // makes the watchdog look like it works right up until it matters.
        await watchdog.requestAuthorizationIfNeeded()

        await monitor.start()

        guard monitor.authorized else {
            // Deliberately silent. The access prompt at the top of the screen
            // already says so and offers the fix; a failure notice on top of
            // it would say the same thing twice.
            //
            // But the keepalive started above has to stop: with no session
            // there is nothing to tear it down later, and it went on playing
            // silence — keeping the app alive in the background — forever.
            keepAlive.stop()
            self.relay = nil
            return
        }

        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await MainActor.run { self.nextDelay() }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run { self.sendNow() }
            }
        }

        linkStatus = "Connecting"
        resolving = true
        isRunning = true
        session += 1
        handleChange()
    }

    func stop() async {
        // Clear the presence on the way out, but don't make stopping wait for
        // it. Stopping is a local decision and should take effect the moment
        // it's asked for; awaiting this meant that whenever the relay was
        // unreachable — the one time you most want to stop — both buttons sat
        // dead for as long as the request took. A relay that can't be reached
        // has nothing to clear anyway.
        if let relay {
            Task { await relay.push(track: nil, playing: false) }
        }

        teardown()
    }

    /// End the session, leaving `status` behind on the row.
    ///
    /// `stop()` is this plus a farewell to the relay. A failed push gets the
    /// teardown without the farewell: there is nothing on the other end to
    /// tell, and trying would only start another doomed request.
    ///
    /// Bumping `session` here is what silences anything else still in the air.
    /// Cancelling the watchdog is right either way — it exists to notice an
    /// app that died while it was supposed to be reporting, and after this
    /// nothing is supposed to be reporting.
    private func teardown(reason: FailureNotice? = nil) {
        heartbeat?.cancel(); heartbeat = nil
        correction?.cancel(); correction = nil
        relay = nil
        keepAlive.stop()
        watchdog.cancel()

        // Ordered after cancel() on purpose: cancel() clears the watchdog's
        // note, and this leaves a better one in its place. Without it a session
        // that dies in the background is completely silent — the teardown
        // clears the dead-man's switch that used to be the only thing that
        // would eventually speak up.
        // A reason present at all is what makes this a failure rather than a
        // deliberate stop — which is why it replaced the separate flag that
        // used to say so.
        if let reason {
            events.record(.failed, summary: reason.summary)
            announce(reason)
        }

        session += 1
        everConnected = false
        failureRun = 0
        retryUntil = nil
        isRunning = false
        linkStatus = "Disconnected"
        resolving = false
        activeEndpoint = ""
        activeKey = ""
    }

    /// Push immediately, then again shortly after. currentPlaybackTime is
    /// unreliable for a second or two following a track change — it can still
    /// report the previous song's position — so the first push may carry a bad
    /// elapsed value and the follow-up corrects the progress bar.
    private func handleChange() {
        sendNow()

        correction?.cancel()
        correction = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.sendNow() }
        }
    }

    private func sendNow() {
        guard let relay else { return }
        let gen = session

        // Confirm the silence is actually still playing before reporting on it,
        // so the snapshot below describes a checked state rather than a
        // remembered one. This also guarantees the engine gets verified at
        // least every 30s even if KeepAlive's own timer is throttled while the
        // app is in the background.
        keepAlive.verify()
        let diag = DeviceDiagnostics.snapshot(keepAlive: keepAlive.diagnostics)

        monitor.refresh()
        guard var track = monitor.track, monitor.isPlaying else {
            Task {
                let outcome = await relay.push(track: nil, playing: false, diag: diag)
                await MainActor.run {
                    guard self.session == gen else { return }
                    DeviceDiagnostics.recordPush(ok: outcome.delivered)
                    // A "nothing playing" push counts as much as any other:
                    // what is being measured is whether the link works, not
                    // whether music is on.
                    outcome.delivered ? self.handleSuccess()
                                      : self.handleFailure(outcome)
                }
            }
            return
        }

        // Freshest possible position, taken at the moment of sending.
        track.elapsed = monitor.liveElapsed
        Task {
            let outcome = await relay.push(track: track, playing: true, diag: diag)
            await MainActor.run {
                guard self.session == gen else { return }
                DeviceDiagnostics.recordPush(ok: outcome.delivered)
                outcome.delivered ? self.handleSuccess()
                                  : self.handleFailure(outcome)
            }
        }
    }
}
