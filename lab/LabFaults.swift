// Lab only (keepalive-lab, never merged). Copied into Ammy/ by
// lab/make-lab-tree.py for the lab build; the pure builds never see it.
// Makes 4 Nov 2026's failure happen on demand in the simulator, and writes a
// probe line every second so a script outside the simulator can see when the
// process stops running. Inert unless launched with -labOut.
//
//   -labOut DIR         probe.txt goes here (a host path; Documents if refused)
//   -labStopAt S        S seconds after the app first enters the background:
//                       stop the engine, post a synthetic .began, then call
//                       verify() at once, as the 18:50:06 push did
//   -labFailStage NAME  "engine.start" (default; 4 Nov's 'what') or "setActive"
//   -labFailFor F       that stage throws for F seconds after the stop
//   -labEndAt E         post a synthetic .ended E seconds after the stop
//   -labNoHold YES      control arm: holdOpen() returns at once (main's behaviour)
//   -labFailFromLaunch YES  the failure window starts at launch instead, so
//                       the engine never runs in this process (see install)

import AVFoundation
import UIKit

enum LabFaults {
    private static let defaults = UserDefaults.standard
    static var active: Bool { defaults.string(forKey: "labOut") != nil }
    static var noHold: Bool { defaults.bool(forKey: "labNoHold") }
    /// The notification prompt would wait for a tap nobody makes.
    static var skipNotificationAsk: Bool { active }
    private static var stoppedAt: Date?
    private static var probe: FileHandle?
    private static var probeTimer: Timer?
    private static var observer: NSObjectProtocol?

    // MARK: - Injected failures

    static func activate(_ session: AVAudioSession) throws {
        if failing("setActive") {
            write("LABFAIL setActive '!pri'")
            throw NSError(domain: NSOSStatusErrorDomain, code: 561_017_449,
                          userInfo: [NSLocalizedDescriptionKey: "Session activation failed (lab)"])
        }
        try session.setActive(true)
    }

    static func start(_ engine: AVAudioEngine) throws {
        if failing("engine.start") {
            write("LABFAIL engine.start 'what'")
            throw NSError(domain: "com.apple.coreaudio.avfaudio", code: 2_003_329_396)
        }
        try engine.start()
    }

    private static func failing(_ stage: String) -> Bool {
        guard let stoppedAt,
              (defaults.string(forKey: "labFailStage") ?? "engine.start") == stage
        else { return false }
        return Date().timeIntervalSince(stoppedAt) < defaults.double(forKey: "labFailFor")
    }

    // MARK: - Probe and trigger

    @MainActor
    static func install(stopEngine: @escaping () -> Void,
                        verify: @escaping () -> Void,
                        state: @escaping () -> KeepAliveDiagnostics?) {
        guard let dir = defaults.string(forKey: "labOut") else { return }
        openProbe(in: dir)

        // The simulator's in-process audio HAL takes MediaPlayback and
        // AudioRecording RunningBoard assertions the first time the engine
        // really starts and keeps them for the life of the process (run
        // 43113016498), so a stop after that never lets the simulator suspend
        // the app. Failing from launch means the engine never started in this
        // process, so nothing but the hold keeps it running once backgrounded.
        if defaults.bool(forKey: "labFailFromLaunch") {
            stoppedAt = Date()
            write("FAULT fail from launch (failStage=\(defaults.string(forKey: "labFailStage") ?? "engine.start") failFor=\(defaults.double(forKey: "labFailFor")) noHold=\(noHold))")
        }

        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { write(line(state())) }
        }
        RunLoop.main.add(timer, forMode: .common)
        probeTimer = timer

        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                write("BACKGROUND")
                guard stoppedAt == nil, defaults.object(forKey: "labStopAt") != nil else { return }
                let s = defaults.double(forKey: "labStopAt")
                DispatchQueue.main.asyncAfter(deadline: .now() + s) {
                    MainActor.assumeIsolated {
                        guard stoppedAt == nil else { return }
                        stoppedAt = Date()
                        write("FAULT stop engine, post .began, verify (failStage=\(defaults.string(forKey: "labFailStage") ?? "engine.start") failFor=\(defaults.double(forKey: "labFailFor")) noHold=\(noHold))")
                        stopEngine()
                        post(.began)
                        verify()
                        write("FAULTDONE " + line(state()))
                        if defaults.object(forKey: "labEndAt") != nil {
                            DispatchQueue.main.asyncAfter(deadline: .now() + defaults.double(forKey: "labEndAt")) {
                                write("FAULT post .ended")
                                post(.ended)
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private static func line(_ k: KeepAliveDiagnostics?) -> String {
        let app = UIApplication.shared
        let left = app.backgroundTimeRemaining
        var fields = [
            String(format: "%.3f", Date().timeIntervalSince1970),
            "pid=\(getpid())",
            "state=\(app.applicationState.rawValue)",
        ]
        if let k {
            fields += [
                "engine=\(k.engineRunning ? 1 : 0)",
                "node=\(k.nodePlaying ? 1 : 0)",
                "want=\(k.running ? 1 : 0)",
                "holds=\(k.holds) saves=\(k.holdSaves) expiries=\(k.holdExpiries) refusals=\(k.holdRefusals)",
                "fails=\(k.resumeFailures) run=\(k.failRun) retries=\(k.retries) heals=\(k.selfHeals) resumes=\(k.resumes)",
            ]
        }
        fields.append("bgleft=\(left.isFinite && left < 100_000 ? String(format: "%.1f", left) : "-")")
        return fields.joined(separator: " ")
    }

    /// A synthetic notice through the real observer. It does not interrupt the
    /// real session, which is why the lab can't test what iOS does with one.
    private static func post(_ type: AVAudioSession.InterruptionType) {
        var info: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if type == .ended {
            info[AVAudioSessionInterruptionOptionKey] = AVAudioSession.InterruptionOptions.shouldResume.rawValue
        }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
                                        object: AVAudioSession.sharedInstance(), userInfo: info)
    }

    private static func openProbe(in dir: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var path = (dir as NSString).appendingPathComponent("probe.txt")
        if !fm.fileExists(atPath: path), !fm.createFile(atPath: path, contents: nil) {
            path = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("probe.txt").path
            if !fm.fileExists(atPath: path) { fm.createFile(atPath: path, contents: nil) }
        }
        probe = FileHandle(forWritingAtPath: path)
        _ = try? probe?.seekToEnd()
        write("START pid=\(getpid()) path=\(path) args=\(ProcessInfo.processInfo.arguments.dropFirst().joined(separator: " "))")
    }

    private static func write(_ line: String) {
        guard let probe else { return }
        let stamped = line.first?.isNumber == true ? line : String(format: "%.3f ", Date().timeIntervalSince1970) + line
        try? probe.write(contentsOf: Data((stamped + "\n").utf8))
        try? probe.synchronize()
    }
}
