import Foundation
import Combine

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

    /// Called whenever the app comes to the front, to retract any notification
    /// that has already fired. Opening the app answers what they were asking.
    func appDidBecomeActive() {
        watchdog.clearDelivered()
    }

    /// What Ammy can see playing right now, whether or not a session is running.
    ///
    /// Read from the device rather than from the last push, on purpose. What is
    /// playing and whether the relay can be reached are separate facts, and the
    /// row that answers the first has no business going blank because of the
    /// second — which is exactly what it used to do.
    var nowPlaying: String {
        guard monitor.authorized else { return "—" }
        guard let track = monitor.track, monitor.isPlaying else { return "Nothing Playing" }
        return "\(track.title) — \(track.artist)"
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

    private let keepAlive = KeepAlive()
    private let watchdog = SilenceWatchdog()
    private var relay: PresenceRelay?
    private var bag = Set<AnyCancellable>()
    private var heartbeat: Task<Void, Never>?
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

        monitor.$track
            .combineLatest(monitor.$isPlaying)
            .removeDuplicates { $0.0?.key == $1.0?.key && $0.1 == $1.1 }
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
    /// message in the status row, or Media Access reading Not Granted.
    func start() async {
        // Distinguish "you typed http" from "that isn't an address at all".
        // iOS blocks plain HTTP at the network layer anyway, so without this the
        // failure surfaces as an unreachable endpoint — which is the same
        // message a dead receiver produces, and exactly the ambiguity worth
        // avoiding.
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") {
            linkStatus = "Address must be https — iOS blocks plain http"
            return
        }

        guard let resolved = PresenceRelay.normalised(trimmed),
              let relay = PresenceRelay(endpoint: trimmed, key: key)
        else {
            linkStatus = "That address doesn't look right"
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
            // Deliberately silent. Media Access already reads Not Granted one
            // row down, and that row is the one the fact belongs to — saying it
            // again under Endpoint only put the news where nobody would look
            // for it.
            return
        }

        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self else { return }
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

        teardown(status: "Disconnected")
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
    private func teardown(status: String, notify: Bool = false) {
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
        if notify { watchdog.reportFailure(status) }

        session += 1
        isRunning = false
        linkStatus = status
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
                    guard outcome.delivered else {
                        return self.teardown(status: outcome.summary, notify: true)
                    }
                    self.linkStatus = "Connected"
                    self.resolving = false
                    // The watchdog measures whether the app is alive, not
                    // whether music is playing — so a successful "nothing
                    // playing" push counts just as much.
                    self.watchdog.postpone()
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
                guard outcome.delivered else {
                    return self.teardown(status: outcome.summary, notify: true)
                }
                self.linkStatus = "Connected"
                self.resolving = false
                self.watchdog.postpone()
            }
        }
    }
}
