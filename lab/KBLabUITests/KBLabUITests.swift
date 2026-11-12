import XCTest

/// keyboard-lab, never merged: the real Ammy, built from this branch with the
/// probe in it (Ammy/LabProbe.swift) and its bar picked at launch by `-labBar`
/// (LabProbe.swift's `Lab` says what each variant is). `-labRunning YES`
/// shows a session without sending anything, so the bar says Stop, and an
/// edit to the URL or Key brings Restart beside it.
///
/// The workflow runs each test in its own xcodebuild, with the simulator in
/// dark mode. The probe logs every frame to LAB_OUT, the screen recording
/// covers everything, and the marks are seconds since 1970, to line them up.
final class KBLabUITests: XCTestCase {
    private var outDir: String {
        ProcessInfo.processInfo.environment["LAB_OUT"] ?? NSTemporaryDirectory()
    }

    override func setUp() {
        continueAfterFailure = true
    }

    private func write(_ lines: [String], to name: String) {
        try? lines.joined(separator: "\n")
            .write(toFile: (outDir as NSString).appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    @MainActor
    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let url = URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png")
        do {
            try data.write(to: url)
        } catch {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func now() -> String { "\(Date().timeIntervalSince1970)" }

    private static let largeText = "UICTContentSizeCategoryXXXL"

    @MainActor
    private func launch(_ variant: String, tag: String, running: Bool, textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.local.ammy")
        app.launchArguments = ["-labBar", variant,
                               "-relay_endpoint", "https://lab.invalid/now-playing",
                               "-labRunning", running ? "YES" : "NO"]
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launchEnvironment = ["LAB_OUT": outDir, "LAB_TAG": tag]
        app.launch()
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 1.5)
        return app
    }

    @MainActor
    private func describe(_ element: XCUIElement, _ name: String) -> String {
        let exists = element.exists
        return "\(name) exists=\(exists) hittable=\(exists && element.isHittable) frame=\(exists ? "\(element.frame)" : "-")"
    }

    @MainActor
    private func frames(_ app: XCUIApplication) -> [String] {
        [
            describe(app.buttons["Stop"], "Stop"),
            describe(app.buttons["Restart"], "Restart"),
            describe(app.buttons["Start"], "Start"),
            describe(app.keyboards.firstMatch, "keyboard"),
            describe(app.textFields["URL"], "URL"),
            describe(app.secureTextFields["Key"], "Key"),
            "window frame=\(app.windows.firstMatch.frame)",
        ]
    }

    // MARK: 1. The keyboard

    /// Each variant with a session showing: at rest, then the URL field (and,
    /// from a fresh launch, the Key field) tapped and one letter typed, which
    /// splits the bar into Stop and Restart. The fix and build 172 also with
    /// no session, where the bar is Start alone.
    @MainActor
    func test1Keyboard() {
        let cases: [(String, Bool)] = [
            ("fix", true), ("main", true), ("form148", true), ("ignore", true),
            ("fix", false), ("main", false),
        ]
        for (variant, running) in cases {
            let state = running ? "running" : "idle"
            for field in ["URL", "Key"] {
                let tag = "\(variant)__\(state)__kb\(field)"
                let app = launch(variant, tag: tag, running: running)
                var lines = ["\(now()) launched"] + frames(app)
                if field == "URL" { shot("\(variant)__\(state)__rest") }
                write(lines, to: tag + ".txt")
                let element = field == "URL" ? app.textFields["URL"] : app.secureTextFields["Key"]
                lines.append("\(now()) tap \(field)")
                element.tap()
                let shown = app.keyboards.firstMatch.waitForExistence(timeout: 5)
                lines.append("\(now()) keyboard shown=\(shown)")
                Thread.sleep(forTimeInterval: 1.0)
                shot(tag + "__focused")
                lines += frames(app)
                lines.append("\(now()) type x")
                element.typeText("x")
                Thread.sleep(forTimeInterval: 1.5)
                lines.append("\(now()) typed")
                lines += frames(app)
                shot(tag)
                write(lines, to: tag + ".txt")
                write([app.debugDescription], to: tag + "__tree.txt")
                app.terminate()
            }
        }
    }

    // MARK: 2. The jump

    /// Scrolled down from the top, from a fresh launch each time, as the
    /// jitter lab and header-lab-option1 did. form148 is the positive
    /// control: its bar on the Form jumped in every earlier lab.
    @MainActor
    func test2Scroll() {
        for variant in ["fix", "main", "form148"] {
            scroll(variant, gestures: ["slow", "drag", "flick"], suffix: "")
            scroll(variant, gestures: ["slow", "drag"], suffix: "XXXL", textSize: Self.largeText)
        }
    }

    @MainActor
    private func scroll(_ variant: String, gestures: [String], suffix: String, textSize: String? = nil) {
        var marks: [String] = []
        for gesture in gestures {
            let tag = "scroll-\(variant)__\(gesture)\(suffix)"
            let app = launch(variant, tag: tag, running: true, textSize: textSize)
            let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            marks.append("\(now()) start \(tag)")
            write(marks, to: "scroll-marks-\(variant)\(suffix).txt")
            switch gesture {
            case "slow":
                low.press(forDuration: 0.3, thenDragTo: middle,
                          withVelocity: XCUIGestureVelocity(rawValue: 150), thenHoldForDuration: 0.5)
            case "drag":
                low.press(forDuration: 0.3, thenDragTo: high,
                          withVelocity: XCUIGestureVelocity(rawValue: 600), thenHoldForDuration: 0.5)
            default:
                low.press(forDuration: 0.01, thenDragTo: middle,
                          withVelocity: .fast, thenHoldForDuration: 0)
            }
            marks.append("\(now()) end \(tag)")
            write(marks, to: "scroll-marks-\(variant)\(suffix).txt")
            Thread.sleep(forTimeInterval: 1.5)
            if gesture == "drag" { shot(tag) }
            app.terminate()
        }
    }
}
