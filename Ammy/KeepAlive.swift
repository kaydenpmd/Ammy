import AVFoundation
import Foundation

/// A snapshot of the keepalive's health, sent to the relay on every push.
///
/// This exists because the app cannot report its own death. The relay only ever
/// sees that pushes stopped, never why — so the last snapshot before the silence
/// is the only evidence there will be. `note_silence()` on the relay prints it
/// onto the "phone stopped checking in" line for exactly that reason.
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

    var interruptionsBegan = 0
    var interruptionsEnded = 0
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
        ]
        if let lastError { d["last_error"] = lastError }
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
/// leaves it true and lets `verify()` try again on the next tick. Before
/// Sept 2026 a failed `resume()` at startup returned early with `running` still
/// false, so the observers were never installed and nothing ever retried — the
/// app then ran with no keepalive at all and nothing anywhere said so.
final class KeepAlive {

    // Recreated wholesale after a media services reset or a configuration
    // change, so these are `var`.
    private var engine = AVAudioEngine()
    private var node = AVAudioPlayerNode()

    private var running = false
    private var wired = false
    private var observers: [NSObjectProtocol] = []
    private var healthTimer: Timer?

    private var diag = KeepAliveDiagnostics()
    private var lastResumeAt: Date?

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
        resume()
    }

    func stop() {
        guard running else { return }
        running = false
        healthTimer?.invalidate()
        healthTimer = nil
        removeObservers()
        node.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
            resume()
        }
    }

    // MARK: - Recovery

    /// Bring session and engine back up. Idempotent, so it serves as the
    /// initial start, the interruption recovery, and the self-heal.
    @discardableResult
    private func resume() -> Bool {
        // Already healthy — don't schedule a second looping buffer onto a node
        // that is already playing one.
        if engine.isRunning && node.isPlaying {
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
            return fail("setCategory: \(error.localizedDescription)")
        }
        do {
            try session.setActive(true)
        } catch {
            return fail("setActive: \(error.localizedDescription)")
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)
        else {
            return fail("could not build silence buffer")
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
            return fail("engine.start: \(error.localizedDescription)")
        }

        node.scheduleBuffer(buffer, at: nil, options: .loops)
        node.volume = 0
        node.play()

        diag.resumes += 1
        diag.lastError = nil
        lastResumeAt = Date()
        refreshDiagnostics()
        return true
    }

    /// Record a failure and leave `running` alone. The verify timer will try
    /// again in a few seconds; the relay will see `resume_failures` climbing
    /// and `last_error` explaining why.
    private func fail(_ reason: String) -> Bool {
        diag.resumeFailures += 1
        diag.lastError = reason
        refreshDiagnostics()
        return false
    }

    /// Tear the audio graph down and build a fresh one. Required after a media
    /// services reset (every audio object is invalid) and the safest response
    /// to a configuration change, where the hardware format may have changed
    /// underneath an existing connection.
    private func rebuild() {
        node.stop()
        engine.stop()
        engine = AVAudioEngine()
        node = AVAudioPlayerNode()
        wired = false
        resume()
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
                self.refreshDiagnostics()
                return
            }

            // Deliberately ignoring `shouldResume`: that hint is about whether
            // *media* should resume. This is a keepalive, and it always should.
            self.diag.interruptionsEnded += 1
            self.resume()
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

    private func startHealthTimer() {
        healthTimer?.invalidate()
        let timer = Timer(timeInterval: verifyInterval, repeats: true) { [weak self] _ in
            self?.verify()
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
