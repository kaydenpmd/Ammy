import XCTest

/// a11y-lab-nowplaying: the Now Playing card's accessibility element in the
/// real Ammy, built twice from this branch:
///
///   change   main's working tree on 4 Nov 2026: the row's
///            .accessibilityElement(children: .combine) followed by
///            .accessibilityLabel { label in Text("Now Playing"); label }
///   control  the same code without that modifier (AmmyApp.swift at 5e63c79)
///
/// The workflow installs one, runs these, then the other, and passes which in
/// LAB_BUILD, the appearance in LAB_APPEARANCE, and the output folder in
/// LAB_OUT. States, each from a fresh launch:
///
///   1 notPlaying    media access granted, nothing playing (no Music app)
///   2 short         -a11yLabTrack short: "Blue", Joni Mitchell
///   3 explicit      -a11yLabTrack explicit: "HUMBLE.", Kendrick Lamar, E
///   4 long          -a11yLabTrack long: a title and artist that both scroll;
///                   read at rest and again while the lines move
///   5 notAvailable  media access revoked by the workflow (simctl privacy)
///   6, 7            performAccessibilityAudit in the short and long states
///
/// For each state: a screenshot of the top of the page; every element whose
/// label contains the state's text, with its label, value, frame and
/// debugDescription (<name>-<moment>-card.txt); the whole element tree
/// (<name>-<moment>-tree.txt); and the app's own account of what it vends to
/// VoiceOver, traits included (<name>-ax-<moment>.json, written by
/// Ammy/A11yLab.swift when asked). <name>.marks.txt times everything.
final class A11yLabUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var outDir: URL { URL(fileURLWithPath: env["LAB_OUT"] ?? NSTemporaryDirectory()) }
    private var build: String { env["LAB_BUILD"] ?? "unknown" }
    private var appearance: String { env["LAB_APPEARANCE"] ?? "unknown" }

    private static let shortTitle = "Blue"
    private static let explicitTitle = "HUMBLE."
    private static let longTitle = "Prime Time Golden Hour Show (Soundtrack)"

    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: States

    @MainActor func test1NotPlaying() { state("notPlaying", track: nil, expect: "Not Playing") }
    @MainActor func test2Short() { state("short", track: "short", expect: Self.shortTitle) }
    @MainActor func test3Explicit() { state("explicit", track: "explicit", expect: Self.explicitTitle) }
    @MainActor func test4Long() { state("long", track: "long", expect: Self.longTitle) }
    @MainActor func test5NotAvailable() { state("notAvailable", track: nil, expect: "Not Available") }

    @MainActor
    private func state(_ state: String, track: String?, expect: String) {
        let name = "\(build)-\(state)-\(appearance)"
        let app = launch(name, track: track)
        let shownAt = waitForCard(app, containing: expect, name: name)
        // The row reads the list's top inset 150 ms after its heights stop
        // changing, and makes the cover's thumbnail in a task: a second
        // covers both, and leaves a long line well inside its first rest.
        Thread.sleep(forTimeInterval: 1.0)
        shot(name + "-top")
        // The app's own account straight away: it takes a few milliseconds,
        // where XCUITest's reads below take seconds, so for the long title
        // this one is the one made while the lines are still at rest.
        requestDump(name, label: "early")
        record(app, expect: expect, name: name, moment: "rest")
        if state == "long" {
            let song = songShownAt(name) ?? shownAt
            // While both lines move: about 8 s after the song showed, past
            // the first rest, before the loop ends.
            let wait = song.addingTimeInterval(8).timeIntervalSinceNow
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            shot(name + "-moving")
            record(app, expect: expect, name: name, moment: "moving")
            // The second loop's rest: the loop is 3 s plus the artist line's
            // 468.5 pt at 30 pt/s, 18.6 s, and its eased hold keeps the lines
            // still for about 5 s after that.
            let rest2 = song.addingTimeInterval(19.4).timeIntervalSinceNow
            if rest2 > 0 { Thread.sleep(forTimeInterval: rest2) }
            shot(name + "-loop2")
            record(app, expect: expect, name: name, moment: "loop2")
            if appearance == "dark" {
                // Once a second for 16 s: the rest of the loop and the start
                // of the next, which begins at rest again.
                burst(name, seconds: 16, every: 1)
            }
        }
        app.terminate()
    }

    // MARK: The audit

    @MainActor func test6AuditShort() { audit("short", expect: Self.shortTitle) }
    @MainActor func test7AuditLong() { audit("long", expect: Self.longTitle) }

    /// The audit again, timed against the song: as soon as the card shows,
    /// while a long title's lines are still, and 8 s in, while they move,
    /// twice each, and once more for the short and explicit songs. Each
    /// file says when its audit ran.
    @MainActor
    func test8AuditTimed() {
        let runs: [(String, String, Double, Int)] = [
            ("long", Self.longTitle, 0, 1), ("long", Self.longTitle, 8, 1),
            ("long", Self.longTitle, 0, 2), ("long", Self.longTitle, 8, 2),
            ("short", Self.shortTitle, 0, 2), ("explicit", Self.explicitTitle, 0, 1),
        ]
        for (track, expect, delay, round) in runs {
            auditTimed(track, expect: expect, startAfter: delay, round: round)
        }
    }

    @MainActor
    private func auditTimed(_ track: String, expect: String, startAfter delay: Double, round: Int) {
        let name = "\(build)-audit-\(track)-at\(Int(delay))-r\(round)-\(appearance)"
        let app = launch(name, track: track)
        let shownAt = waitForCard(app, containing: expect, name: name)
        let song = songShownAt(name) ?? shownAt
        let wait = song.addingTimeInterval(delay).timeIntervalSinceNow
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        shot(name + "-before")
        let issues = Lines()
        var lines: [String] = []
        let began = Date()
        mark(name, "audit begins")
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                issues.items.append(Self.describe(issue))
                return true
            }
            lines = issues.items
            lines.append("audit returned; \(issues.items.count) issue(s)")
        } catch {
            lines = issues.items
            lines.append("audit threw: \(error)")
        }
        let ended = Date()
        mark(name, "audit ends")
        lines.append(String(format: "audit ran from %.2f to %.2f s after the song showed", began.timeIntervalSince(song), ended.timeIntervalSince(song)))
        write(lines, to: name + ".txt")
        shot(name + "-after")
        app.terminate()
    }

    @MainActor
    private func audit(_ track: String, expect: String) {
        let name = "\(build)-audit-\(track)-\(appearance)"
        let app = launch(name, track: track)
        _ = waitForCard(app, containing: expect, name: name)
        Thread.sleep(forTimeInterval: 1.0)
        shot(name + "-before")
        let issues = Lines()
        var lines: [String] = []
        let started = Date()
        mark(name, "audit begins")
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                issues.items.append(Self.describe(issue))
                return true
            }
            lines = issues.items
            lines.append("audit returned after \(String(format: "%.1f", Date().timeIntervalSince(started))) s; \(issues.items.count) issue(s)")
        } catch {
            lines = issues.items
            lines.append("audit threw after \(String(format: "%.1f", Date().timeIntervalSince(started))) s: \(error)")
        }
        mark(name, "audit ends")
        write(lines, to: name + ".txt")
        shot(name + "-after")
        app.terminate()
    }

    /// Collects the audit's issues from its handler.
    private final class Lines {
        var items: [String] = []
    }

    @MainActor
    private static func describe(_ issue: XCUIAccessibilityAuditIssue) -> String {
        var s = "type=\(auditName(issue.auditType)) | compact=\(issue.compactDescription) | detailed=\(issue.detailedDescription)"
        if let element = issue.element {
            if element.exists {
                s += " | element: type=\(element.elementType.rawValue) label=\(quote(element.label)) frame=\(element.frame)"
            } else {
                s += " | element no longer exists"
            }
        } else {
            s += " | no element"
        }
        return s
    }

    private static func auditName(_ type: XCUIAccessibilityAuditType) -> String {
        let known: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "elementDetection"), (.hitRegion, "hitRegion"),
            (.sufficientElementDescription, "sufficientElementDescription"), (.dynamicType, "dynamicType"),
            (.textClipped, "textClipped"), (.trait, "trait"),
        ]
        let names = known.filter { type.contains($0.0) }.map(\.1)
        return names.isEmpty ? "raw:\(type.rawValue)" : names.joined(separator: "+")
    }

    // MARK: Pieces

    @MainActor
    private func launch(_ name: String, track: String?) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.local.ammy")
        app.launchArguments = track.map { ["-a11yLabTrack", $0] } ?? []
        app.launchEnvironment = ["LAB_OUT": outDir.path, "LAB_TAG": name]
        mark(name, "launch \(app.launchArguments)")
        app.launch()
        mark(name, "launched, state \(app.state.rawValue)")
        return app
    }

    /// Waits for the card to say what the state expects, and returns when it
    /// first did, as near as the test can tell.
    @MainActor
    private func waitForCard(_ app: XCUIApplication, containing expect: String, name: String) -> Date {
        let started = Date()
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", expect)).firstMatch
        let found = card.waitForExistence(timeout: 20)
        let at = Date()
        mark(name, "an element containing \(Self.quote(expect)) exists=\(found) after \(String(format: "%.2f", at.timeIntervalSince(started))) s")
        if found {
            // One quick read of the first match, the card itself, before
            // anything else: for the long title, while its lines are still.
            let label = card.label
            let frame = card.frame
            let line = "\(now()) first read: label=\(Self.quote(label)) frame=\(frame)"
            write([line], to: "\(name)-first-card.txt")
            mark(name, "first read done")
        }
        return at
    }

    /// When Ammy published the lab's song, from the probe's record.
    private func songShownAt(_ name: String) -> Date? {
        let url = outDir.appendingPathComponent("\(name).probe.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.contains("\"k\":\"track\"") {
            if let data = line.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let wall = object["wall"] as? Double {
                return Date(timeIntervalSince1970: wall)
            }
        }
        return nil
    }

    /// Every element whose label contains `expect`: its snapshot's attributes
    /// and its debugDescription; then the whole tree; then the app's own dump.
    @MainActor
    private func record(_ app: XCUIApplication, expect: String, name: String, moment: String) {
        var lines = ["\(now()) \(moment): elements whose label contains \(Self.quote(expect))"]
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", expect))
        let elements = query.allElementsBoundByIndex
        lines.append("count: \(elements.count)")
        for (i, element) in elements.enumerated() {
            lines.append("[\(i)]")
            do {
                let snapshot = try element.snapshot()
                lines.append("  elementType: \(snapshot.elementType.rawValue)")
                lines.append("  label: \(Self.quote(snapshot.label))")
                lines.append("  value: \(Self.quoteAny(snapshot.value))")
                lines.append("  identifier: \(Self.quote(snapshot.identifier))")
                lines.append("  title: \(Self.quote(snapshot.title))")
                lines.append("  placeholderValue: \(Self.quoteAny(snapshot.placeholderValue))")
                lines.append("  frame: \(snapshot.frame)")
                lines.append("  enabled: \(snapshot.isEnabled) selected: \(snapshot.isSelected)")
                lines.append("  children: \(snapshot.children.count)")
                let keys = snapshot.dictionaryRepresentation.keys.map(\.rawValue).sorted()
                lines.append("  attribute keys: \(keys.joined(separator: ", "))")
            } catch {
                lines.append("  snapshot failed: \(error)")
            }
            lines.append("  debugDescription:")
            lines += element.debugDescription.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }
        }
        lines.append("\(now()) done")
        write(lines, to: "\(name)-\(moment)-card.txt")
        write([app.debugDescription], to: "\(name)-\(moment)-tree.txt")
        mark(name, "\(moment): \(elements.count) element(s) recorded, tree written")
        requestDump(name, label: moment)
    }

    /// Asks Ammy's lab probe for everything it vends to VoiceOver, and waits
    /// for the file.
    private func requestDump(_ name: String, label: String) {
        let request = outDir.appendingPathComponent("\(name).axreq.\(label)")
        let response = outDir.appendingPathComponent("\(name)-ax-\(label).json")
        try? Data().write(to: request)
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: response.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        let ok = FileManager.default.fileExists(atPath: response.path)
        mark(name, "in-app dump \(label): \(ok ? "written" : "MISSING after 10 s")")
    }

    @MainActor
    private func shot(_ name: String) {
        let before = now()
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let after = now()
        do {
            try data.write(to: outDir.appendingPathComponent(name + ".png"))
        } catch {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        appendLine("\(before) \(after) \(name)", to: "shots.txt")
    }

    @MainActor
    private func burst(_ name: String, seconds: Double, every: Double) {
        let start = Date()
        var k = 0
        while Double(k) * every < seconds {
            let wait = start.addingTimeInterval(Double(k) * every).timeIntervalSinceNow
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            shot(String(format: "%@-burst-%02d", name, k))
            k += 1
        }
    }

    private func mark(_ name: String, _ what: String) {
        appendLine("\(now()) \(what)", to: "\(name).marks.txt")
    }

    private func now() -> String { String(format: "%.3f", Date().timeIntervalSince1970) }

    private func write(_ lines: [String], to file: String) {
        try? lines.joined(separator: "\n")
            .write(to: outDir.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    private func appendLine(_ line: String, to file: String) {
        let url = outDir.appendingPathComponent(file)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// A string as Swift would write it, so separators and any unusual
    /// characters show exactly.
    private static func quote(_ s: String) -> String {
        s.debugDescription
    }

    private static func quoteAny(_ v: Any?) -> String {
        guard let v else { return "nil" }
        if let s = v as? String { return "String " + s.debugDescription }
        return "\(type(of: v)) \(v)"
    }
}
