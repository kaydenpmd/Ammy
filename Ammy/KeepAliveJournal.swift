import Foundation

/// What the keepalive did, kept on disk, so the first push after a silence can
/// say what happened after the last push that got through.
///
/// The receiver only ever has the last snapshot before a silence. Everything
/// after it (the retries, the hold running out, the suspension, an `.ended`
/// that did or didn't come) happened where nothing could report it. On
/// 4 Nov 2026 that was the whole story: the log knew the 18:50:06 failure and
/// nothing about the seconds after it.
///
/// One line per event, appended from a background queue and synchronized after
/// each line, so the file survives the process being suspended and then
/// killed. A second, tiny file is overwritten on every 10 s health tick with
/// the time and the engine's state: since a suspended process can't write, the
/// last value in it is when the process stopped running, to within one tick.
enum KeepAliveJournal {
    private static let queue = DispatchQueue(label: "com.local.ammy.keepalive-journal", qos: .utility)
    private static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    private static let logURL = folder.appendingPathComponent("keepalive.log")
    private static let aliveURL = folder.appendingPathComponent("keepalive.alive")
    private static let keepLines = 400

    /// The previous process's last lines and last stamp, read once, before this
    /// process writes anything. Then the file is trimmed and this run starts
    /// with a header line (version, build, date and time).
    static let previousRun: (tail: [String], lastAlive: String?)? = {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let lines = ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
        let alive = try? String(contentsOf: aliveURL, encoding: .utf8)
        let header = "\(Date().formatted(.iso8601)) --- launch, Ammy \(Bundle.main.displayVersion)"
        let kept = (lines.suffix(keepLines) + [header]).joined(separator: "\n") + "\n"
        try? kept.write(to: logURL, atomically: true, encoding: .utf8)
        guard !lines.isEmpty || alive != nil else { return nil }
        return (Array(lines.suffix(25)), alive)
    }()

    static func note(_ text: String) {
        _ = previousRun // the previous run is read before this one adds to it
        let line = "\(Date().formatted(.iso8601)) \(text)\n"
        queue.async {
            guard let handle = try? FileHandle(forWritingTo: logURL) else {
                try? Data(line.utf8).write(to: logURL)
                return
            }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.synchronize()
        }
    }

    static func alive(_ summary: String) {
        _ = previousRun // likewise: the previous stamp is read before this one replaces it
        let text = "\(Date().formatted(.iso8601)) \(summary)"
        queue.async { try? Data(text.utf8).write(to: aliveURL, options: .atomic) }
    }
}
