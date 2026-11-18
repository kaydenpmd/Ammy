import UIKit
import XCTest

/// pip-bar-lab, never merged: the real Ammy, built from this branch with the
/// probe in it (Ammy/LabProbe.swift) and its bar picked at launch by `-labBar`:
/// "fix" (this branch: the bar's room in the page's UIKit safe area, so
/// Picture in Picture rests above it), "main" (build 201 as released) and
/// "form148" (the bar on the Form, the jump's positive control).
/// `-labRunning YES` shows a session without sending anything, so the bar
/// says Stop, and an edit to the URL brings Restart beside it.
///
/// test1PiP floats PiPHost's magenta video in PiP and reads PiP's frame from
/// SpringBoard's own element for it ("PIP-SBInteractionPassThroughView",
/// found in pip-lab). The other tests have no PiP; they check that nothing
/// else about the bar changed: the keyboard, the large title's jump, the end
/// of the page and the slides to History.
///
/// The workflow runs each test in its own xcodebuild, with the simulator in
/// dark mode. The probe logs every frame to LAB_OUT, the screen recording
/// covers everything, and the marks are seconds since 1970, to line them up.
final class PiPBarLabUITests: XCTestCase {
    private var outDir: String {
        ProcessInfo.processInfo.environment["LAB_OUT"] ?? NSTemporaryDirectory()
    }

    private var pipLines: [String] = []

    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: Output

    private func now() -> String { String(format: "%.3f", Date().timeIntervalSince1970) }

    private func write(_ lines: [String], to name: String) {
        try? (lines.joined(separator: "\n") + "\n")
            .write(toFile: (outDir as NSString).appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// One line of test1's record, pip.txt, written out at once so a run that
    /// stops early keeps what it had.
    private func log(_ line: String) {
        pipLines.append("\(now()) \(line)")
        print("[lab] \(line)")
        write(pipLines, to: "pip.txt")
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

    private func fmt(_ r: CGRect) -> String {
        String(format: "x=%.2f y=%.2f w=%.2f h=%.2f maxY=%.2f", r.minX, r.minY, r.width, r.height, r.maxY)
    }

    /// The screen, from SpringBoard's own element. The test runner's
    /// UIScreen.main said 320 x 480 on the 17e copy on iOS 26.5 (run
    /// 44397032602), which threw every drag to the top of the screen.
    @MainActor private var screen: CGSize {
        let frames = [springboard.frame, springboard.windows.firstMatch.frame]
        return frames.max(by: { $0.width * $0.height < $1.width * $1.height })?.size ?? UIScreen.main.bounds.size
    }

    @MainActor private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    // MARK: Ammy

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

    /// keyboard-lab's block of frames, with History added; analyse.py reads
    /// it a block at a time, ending at the window line.
    @MainActor
    private func frames(_ app: XCUIApplication) -> [String] {
        [
            describe(app.buttons["Stop"], "Stop"),
            describe(app.buttons["Restart"], "Restart"),
            describe(app.buttons["Start"], "Start"),
            describe(app.keyboards.firstMatch, "keyboard"),
            describe(app.textFields["URL"], "URL"),
            describe(app.secureTextFields["Key"], "Key"),
            describe(app.buttons["History"], "History"),
            "window frame=\(app.windows.firstMatch.frame)",
        ]
    }

    /// The bar's buttons, on one line, for pip.txt.
    @MainActor
    private func bars(_ app: XCUIApplication) -> String {
        var parts: [String] = []
        for label in ["Start", "Stop", "Restart"] {
            let element = app.buttons[label]
            if element.exists { parts.append("\(label)=[\(fmt(element.frame))]") }
        }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists { parts.append("keyboard=[\(fmt(keyboard.frame))]") }
        let url = app.textFields["URL"]
        if url.exists { parts.append("URL=[\(fmt(url.frame))]") }
        return parts.joined(separator: " ")
    }

    // MARK: Picture in Picture

    @MainActor
    private func pipFrame() -> CGRect? {
        let element = springboard.descendants(matching: .any)["PIP-SBInteractionPassThroughView"]
        return element.exists ? element.frame : nil
    }

    @MainActor
    @discardableResult
    private func record(_ tag: String) -> CGRect? {
        let frame = pipFrame()
        shot(tag)
        if let frame {
            log("\(tag) pip=[\(fmt(frame))] fromBottom=\(String(format: "%.2f", screen.height - frame.maxY))")
        } else {
            log("\(tag) pip=none")
        }
        return frame
    }

    /// Answers SpringBoard's alerts so they don't dim the screen for the rest
    /// of the run.
    @MainActor
    private func answerAlerts() {
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.exists else { return }
            let allow = alert.buttons["Allow"]
            let button = allow.exists ? allow : alert.buttons.element(boundBy: alert.buttons.count - 1)
            log("alert '\(alert.label)': tapping '\(button.label)'")
            button.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    /// A slow drag with a pause before letting go, so PiP settles in the
    /// corner it's left nearest rather than being thrown.
    @MainActor
    private func dragPiP(toRight right: Bool, in app: XCUIApplication) {
        guard let r = pipFrame() else {
            log("no PiP to drag")
            return
        }
        let target = CGPoint(x: right ? screen.width - r.width / 2 - 16 : r.width / 2 + 16,
                             y: screen.height - r.height / 2 - 40)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: r.midX, dy: r.midY))
            .press(forDuration: 0.15, thenDragTo: origin.withOffset(CGVector(dx: target.x, dy: target.y)),
                   withVelocity: XCUIGestureVelocity(rawValue: 500), thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 2.0)
    }

    // MARK: 1. Picture in Picture over the bar

    /// PiP over Ammy with each bar: arriving from the Home Screen's corner,
    /// then dragged to each bottom corner, with no session (Start) and with
    /// one (Stop); then the URL field's keyboard (and, with a session, a
    /// letter typed, so Restart comes beside Stop); then over History, which
    /// has no bar, and back.
    @MainActor
    func test1PiP() {
        log("screen \(screen.width) x \(screen.height) pt (SpringBoard's), UIScreen.main \(UIScreen.main.bounds.size), scale \(UIScreen.main.scale)")
        let host = XCUIApplication()
        host.launchEnvironment = ["LAB_OUT": outDir]
        host.launch()
        let status = host.staticTexts["status"]
        var possible = false
        for _ in 0..<60 {
            if status.exists, status.label.contains("possible=true") {
                possible = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        log("host possible=\(possible) status: \(status.exists ? status.label.replacingOccurrences(of: "\n", with: " / ") : "-")")
        host.buttons["startPiP"].tap()
        var started = false
        for _ in 0..<30 {
            if status.label.contains("didStart") {
                started = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        log("host started=\(started)")
        Thread.sleep(forTimeInterval: 2)
        record("host__started")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
        dragPiP(toRight: true, in: springboard)
        record("home__bottomRight")

        for variant in ["main", "fix"] {
            for running in [false, true] {
                let tag = "pip-\(variant)-\(running ? "running" : "idle")"
                let app = launch(variant, tag: tag, running: running)
                Thread.sleep(forTimeInterval: 1.0)
                answerAlerts()
                log("\(tag) \(bars(app))")
                write(frames(app), to: tag + ".txt")
                record("\(tag)__arrive")
                dragPiP(toRight: false, in: app)
                record("\(tag)__bottomLeft")
                dragPiP(toRight: true, in: app)
                record("\(tag)__bottomRight")
                let url = app.textFields["URL"]
                if url.waitForExistence(timeout: 5) {
                    url.tap()
                    let shown = app.keyboards.firstMatch.waitForExistence(timeout: 5)
                    Thread.sleep(forTimeInterval: 1.5)
                    if running {
                        url.typeText("x")
                        Thread.sleep(forTimeInterval: 1.5)
                    }
                    log("\(tag)__kb shown=\(shown) \(bars(app))")
                    record("\(tag)__kb")
                } else {
                    log("\(tag): no URL field")
                }
                app.terminate()
            }

            let tag = "pip-\(variant)-history"
            let app = launch(variant, tag: tag, running: false)
            Thread.sleep(forTimeInterval: 1.0)
            record("\(tag)__main")
            // History sits below the fold on an SE.
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1.5)
            let history = app.buttons["History"]
            if history.waitForExistence(timeout: 5) {
                history.tap()
                Thread.sleep(forTimeInterval: 2.5)
                log("\(tag) History bar=\(app.navigationBars["History"].exists) \(bars(app))")
                record("\(tag)__history")
                let back = app.navigationBars["History"].buttons.element(boundBy: 0)
                if back.exists {
                    back.tap()
                    Thread.sleep(forTimeInterval: 2.5)
                }
                log("\(tag) back \(bars(app))")
                record("\(tag)__back")
            } else {
                log("\(tag): no History row")
            }
            app.terminate()
        }
        host.terminate()
        log("done")
    }

    // MARK: 2. The keyboard

    /// keyboard-lab's test: each bar with a session and without, the URL and
    /// Key fields each tapped from a fresh launch and one letter typed: where
    /// the keyboard, the bar's buttons and the field end up.
    @MainActor
    func test2Keyboard() {
        let cases: [(String, Bool)] = [("fix", true), ("main", true), ("fix", false), ("main", false)]
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

    // MARK: 3. The large title's jump

    /// Scrolled down from the top, from a fresh launch each time, as the
    /// jitter lab, header-lab-option1 and keyboard-lab did. form148 is the
    /// positive control: its bar on the Form jumped in every earlier lab.
    @MainActor
    func test3Scroll() {
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

    // MARK: 4. The top and the end of the page

    /// header-lab-option1's test: each bar at rest at the top, then scrolled
    /// to the end, where History ends against the button, at the default
    /// text size and at XXXL, with a session showing (Stop).
    @MainActor
    func test4Ends() {
        for (name, textSize) in [("ends", nil), ("endsXXXL", Self.largeText)] as [(String, String?)] {
            for variant in ["fix", "main"] {
                let tag = "\(variant)__\(name)"
                let app = launch(variant, tag: tag, running: true, textSize: textSize)
                Thread.sleep(forTimeInterval: 1.0)
                shot(tag + "__top")
                var lines = ["\(now()) top"] + frames(app)
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1.5)
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1.5)
                app.swipeUp()
                shot(tag + "__moving")
                // Long enough for the scroll indicator to fade.
                Thread.sleep(forTimeInterval: 3.0)
                shot(tag + "__end")
                lines.append("\(now()) end")
                lines += frames(app)
                write(lines, to: tag + ".txt")
                write([app.debugDescription], to: tag + "__tree.txt")
                app.terminate()
            }
        }
    }

    // MARK: 5. History

    @MainActor func test5History() {
        history("fix")
        history("main")
    }

    /// header-lab-option1's test: History opened and left every way UIKit
    /// offers: Back, a swipe all the way, and a swipe let go, which UIKit
    /// calls off, followed by Back. Each mark says whether Stop is there.
    @MainActor
    private func history(_ variant: String) {
        let tag = "\(variant)__history"
        var marks: [String] = []
        let app = launch(variant, tag: tag, running: true)
        func mark(_ what: String) {
            let stop = app.buttons["Stop"]
            let exists = stop.exists
            let frame = exists ? "\(stop.frame)" : "-"
            let hittable = exists && stop.isHittable
            marks.append("\(now()) \(what) | Stop exists=\(exists) hittable=\(hittable) frame=\(frame) | History bar=\(app.navigationBars["History"].exists)")
            write(marks, to: tag + "-marks.txt")
        }
        shot(tag + "__0_launch")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1.5)
        mark("scrolled")
        shot(tag + "__0_scrolled")
        let history = app.buttons["History"]
        let back = app.navigationBars["History"].buttons.element(boundBy: 0)
        func backIfStillThere(_ why: String) {
            if app.navigationBars["History"].exists {
                mark(why)
                back.tap()
                Thread.sleep(forTimeInterval: 2)
            }
        }
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let far = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let near = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))

        mark("push 1"); history.tap()
        shot(tag + "__1_push_mid")
        Thread.sleep(forTimeInterval: 2)
        shot(tag + "__2_history"); mark("History shown")
        mark("back"); back.tap()
        shot(tag + "__3_pop_mid")
        Thread.sleep(forTimeInterval: 2)
        shot(tag + "__4_back"); mark("back, settled")

        mark("push 2"); history.tap(); Thread.sleep(forTimeInterval: 2)
        mark("History shown")
        mark("swipe all the way")
        edge.press(forDuration: 0.05, thenDragTo: far,
                   withVelocity: XCUIGestureVelocity(rawValue: 1500), thenHoldForDuration: 0)
        shot(tag + "__5_swipe_end")
        Thread.sleep(forTimeInterval: 2)
        shot(tag + "__6_after_swipe"); mark("after the full swipe")
        backIfStillThere("back, as the swipe didn't take")

        mark("push 3"); history.tap(); Thread.sleep(forTimeInterval: 2)
        mark("History shown")
        mark("swipe let go")
        edge.press(forDuration: 0.05, thenDragTo: near,
                   withVelocity: XCUIGestureVelocity(rawValue: 300), thenHoldForDuration: 0.5)
        shot(tag + "__7_letgo_end")
        Thread.sleep(forTimeInterval: 2)
        shot(tag + "__8_after_letgo"); mark("after the let-go swipe")
        backIfStillThere("back after the let-go swipe")
        shot(tag + "__9_end"); mark("end")
        app.terminate()
    }
}
