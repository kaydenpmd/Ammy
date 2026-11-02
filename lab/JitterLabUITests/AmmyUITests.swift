import XCTest

/// header-lab-option1: the real Ammy, built from this branch with the probe in
/// it (Ammy/LabProbe.swift) and its layout picked at launch by `-labLayout`:
///
///   option1         main's working tree on 2 Nov 2026: no section headers,
///                   the bar on the stack, safeAreaPadding for its room
///   option1Margins  option 1 with build 156's two contentMargins instead
///   main156         build 156 as released: headers and contentMargins
///   largeForm       option 1's page with the bar on the Form (build 148's
///                   bar): the positive control for the jump
///
/// The workflow runs each test in its own xcodebuild, so an app that XCTest
/// can't close costs one test, not the rest; it switches the appearance and
/// media access between them and says which in LAB_SUFFIX. The probe logs
/// every frame to LAB_OUT, the screen recording covers everything, and the
/// marks are seconds since 1970, to line them up with it.
final class AmmyUITests: XCTestCase {
    private var outDir: String {
        ProcessInfo.processInfo.environment["LAB_OUT"] ?? NSTemporaryDirectory()
    }

    /// "-dark", "-light" or "", from the workflow, for files whose test runs
    /// more than once.
    private var suffix: String {
        ProcessInfo.processInfo.environment["LAB_SUFFIX"] ?? ""
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

    /// The whole accessibility tree, frames included: it carries the vertical
    /// scroll bar's track and knob even while the indicator is hidden.
    @MainActor
    private func dump(_ app: XCUIApplication, _ name: String) {
        write([app.debugDescription], to: name + ".txt")
    }

    private func now() -> String { "\(Date().timeIntervalSince1970)" }

    /// The text size the larger-text tests launch with: XXXL, the largest
    /// before the accessibility sizes, so the page outgrows a Face ID phone's
    /// screen and has an end to scroll to.
    private static let largeText = "UICTContentSizeCategoryXXXL"

    @MainActor
    private func launch(_ layout: String, tag: String, textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.local.ammy")
        app.launchArguments = ["-labLayout", layout]
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
    private func frames(_ app: XCUIApplication) -> [String] {
        let history = app.buttons["History"]
        let start = app.buttons["Start"]
        return [
            "History exists=\(history.exists) frame=\(history.exists ? "\(history.frame)" : "-")",
            "Start exists=\(start.exists) frame=\(start.exists ? "\(start.frame)" : "-")",
            "window frame=\(app.windows.firstMatch.frame)",
        ]
    }

    // MARK: 1. The jump

    @MainActor func test1aScrollOption1() { scroll("option1") }
    @MainActor func test1bScrollMain156() { scroll("main156") }
    @MainActor func test1cScrollLargeForm() { scroll("largeForm") }
    @MainActor func test1dScrollOption1Margins() { scroll("option1Margins") }

    /// Option 1 and build 156 flicked again, three more times each, from a
    /// fresh launch each time, to see how much a flick's lag varies.
    @MainActor
    func test1eFlicks() {
        for round in 2...4 {
            for layout in ["option1", "main156"] {
                scroll(layout, gestures: ["flick"], suffix: "\(round)")
            }
        }
    }

    /// Each layout at the larger text size, dragged slowly and fast.
    @MainActor
    func test1fScrollLargeText() {
        for layout in ["option1", "main156", "largeForm", "option1Margins"] {
            scroll(layout, gestures: ["slow", "drag"], suffix: "XXXL", textSize: Self.largeText)
        }
    }

    /// Scrolled down from the top, from a fresh launch each time: slowly, more
    /// slowly, fast, and flicked, as the jitter lab does.
    @MainActor
    private func scroll(_ layout: String, gestures: [String] = ["slow", "slower", "drag", "flick"],
                        suffix: String = "", textSize: String? = nil) {
        var marks: [String] = []
        for gesture in gestures {
            let tag = "real-\(layout)__\(gesture)\(suffix)"
            let app = launch(layout, tag: tag, textSize: textSize)
            if gesture == "slow" { shot(tag + "__0") }
            let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            marks.append("\(now()) start \(tag)")
            write(marks, to: "scroll-marks-\(layout)\(suffix).txt")
            switch gesture {
            case "slow":
                low.press(forDuration: 0.3, thenDragTo: middle,
                          withVelocity: XCUIGestureVelocity(rawValue: 150), thenHoldForDuration: 0.5)
            case "slower":
                low.press(forDuration: 0.3, thenDragTo: middle,
                          withVelocity: XCUIGestureVelocity(rawValue: 80), thenHoldForDuration: 0.5)
            case "drag":
                low.press(forDuration: 0.3, thenDragTo: high,
                          withVelocity: XCUIGestureVelocity(rawValue: 600), thenHoldForDuration: 0.5)
            default:
                low.press(forDuration: 0.01, thenDragTo: middle,
                          withVelocity: .fast, thenHoldForDuration: 0)
            }
            marks.append("\(now()) end \(tag)")
            write(marks, to: "scroll-marks-\(layout)\(suffix).txt")
            Thread.sleep(forTimeInterval: 1.5)
            if gesture == "slow" || gesture == "drag" { shot(tag + "__1") }
            app.terminate()
        }
    }

    // MARK: 2. The end of the page

    /// Scrolled to the end: where History ends against the button, the
    /// scroll bar's track (from the accessibility tree), and a screenshot
    /// straight after the last swipe, while the indicator still shows.
    @MainActor
    func test2Bottom() { bottom("bottom", textSize: nil) }

    /// The same at the larger text size, where the page is longer than a Face
    /// ID phone's screen too.
    @MainActor
    func test2bBottomLargeText() { bottom("bottomXXXL", textSize: Self.largeText) }

    /// The same with media access revoked, which the workflow arranges: the
    /// prompt's section at the top makes the page long enough to have an end
    /// on an iPhone 17e at the default text size.
    @MainActor
    func test2cBottomPrompt() { bottom("bottomPrompt", textSize: nil) }

    @MainActor
    private func bottom(_ name: String, textSize: String?) {
        for layout in ["option1", "main156", "option1Margins", "largeForm"] {
            let tag = "real-\(layout)__\(name)"
            let app = launch(layout, tag: tag, textSize: textSize)
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1.5)
            app.swipeUp()
            shot(tag + "__moving")
            Thread.sleep(forTimeInterval: 2.0)
            app.swipeUp()
            shot(tag + "__again")
            Thread.sleep(forTimeInterval: 2.0)
            write(frames(app), to: tag + ".txt")
            dump(app, tag + "__tree")
            shot(tag)
            app.terminate()
        }
    }

    // MARK: 3. History

    @MainActor func test3aHistoryOption1() { history("option1") }
    @MainActor func test3bHistoryMain156() { history("main156") }

    /// History opened and left every way UIKit offers: Back, a swipe all the
    /// way, and a swipe let go, which UIKit calls off, followed by Back. The
    /// marks are written as they happen, so a run that stops early still has
    /// them, and each says whether the Start button is there.
    @MainActor
    private func history(_ layout: String) {
        let tag = "real-\(layout)__history"
        var marks: [String] = []
        let app = launch(layout, tag: tag)
        func mark(_ what: String) {
            let start = app.buttons["Start"]
            let exists = start.exists
            let frame = exists ? "\(start.frame)" : "-"
            let hittable = exists && start.isHittable
            marks.append("\(now()) \(what) | Start exists=\(exists) hittable=\(hittable) frame=\(frame) | History bar=\(app.navigationBars["History"].exists)")
            write(marks, to: tag + "-marks.txt")
        }
        shot(tag + "__0_launch")
        // History sits below the fold on an SE.
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

    // MARK: 4. The keyboard

    /// The URL field, then the Key field, tapped from the top of the page:
    /// where the field, the keyboard and the button end up.
    @MainActor
    func test4Keyboard() {
        for layout in ["option1", "main156"] {
            for field in ["URL", "Key"] {
                let tag = "real-\(layout)__kb\(field)"
                let app = launch(layout, tag: tag)
                let element = field == "URL" ? app.textFields["URL"] : app.secureTextFields["Key"]
                var lines = ["before: \(field) exists=\(element.exists) frame=\(element.exists ? "\(element.frame)" : "-")"]
                lines += frames(app)
                lines.append("\(now()) tap \(field)")
                write(lines, to: tag + ".txt")
                element.tap()
                let keyboard = app.keyboards.firstMatch
                let shown = keyboard.waitForExistence(timeout: 5)
                Thread.sleep(forTimeInterval: 1.5)
                shot(tag)
                lines.append("\(now()) keyboard exists=\(shown) frame=\(shown ? "\(keyboard.frame)" : "-")")
                lines.append("after: \(field) exists=\(element.exists) frame=\(element.exists ? "\(element.frame)" : "-") hittable=\(element.exists && element.isHittable)")
                lines += frames(app)
                write(lines, to: tag + ".txt")
                dump(app, tag + "__tree")
                app.terminate()
            }
        }
    }

    // MARK: 5. At rest

    /// Each layout at rest at the top, then at the end of the page, for
    /// pixel comparisons. The workflow runs it in light and in dark.
    @MainActor
    func test5Rest() { rest("rest", textSize: nil) }

    /// The same at the larger text size.
    @MainActor
    func test5bRestLargeText() { rest("restXXXL", textSize: Self.largeText) }

    /// The same with media access revoked: the prompt at the top, and a page
    /// long enough to have an end on an iPhone 17e.
    @MainActor
    func test5cRestPrompt() { rest("restPrompt", textSize: nil) }

    @MainActor
    private func rest(_ name: String, textSize: String?) {
        for layout in ["option1", "main156", "option1Margins", "largeForm"] {
            let tag = "real-\(layout)__\(name)\(suffix)"
            let app = launch(layout, tag: tag, textSize: textSize)
            Thread.sleep(forTimeInterval: 1.0)
            shot(tag + "__top")
            dump(app, tag + "__top_tree")
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1.5)
            app.swipeUp()
            // Long enough for the scroll indicator to fade.
            Thread.sleep(forTimeInterval: 3.0)
            shot(tag + "__end")
            write(frames(app), to: tag + "__end.txt")
            dump(app, tag + "__end_tree")
            app.terminate()
        }
    }

    // MARK: 6. The media-access prompt

    /// Run with media access revoked: the prompt at the top of the page.
    @MainActor
    func test6Prompt() {
        for layout in ["option1", "main156"] {
            let tag = "real-\(layout)__prompt\(suffix)"
            let app = launch(layout, tag: tag)
            Thread.sleep(forTimeInterval: 1.0)
            shot(tag)
            dump(app, tag + "__tree")
            app.terminate()
        }
    }
}
