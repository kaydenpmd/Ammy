import XCTest

/// Drives each variant through the same gestures. The app logs every frame
/// itself (Probe.swift); this only launches it, scrolls, and takes
/// screenshots so each variant's look is on record too.
///
/// jitter-lab-inline: option 2 of the section-header question, an inline
/// title with the bar back on the Form. (A) "ammy" is the large title with
/// the bar on the Form, the known jump; (B) "inlineForm" is option 2;
/// (C) "inlineStack" is an inline title with the bar on the stack.
/// "stackMargins" (build 156's arrangement, large title) and "inlineNone"
/// (an inline title, no bar) are references.
final class JitterLabUITests: XCTestCase {
    private static let variants = ["ammy", "inlineForm", "inlineStack", "stackMargins", "inlineNone"]
    /// Ammy's own sections, and ten more, so a drag never reaches the end of
    /// the list and rubber-bands.
    private static let contents = ["ammy", "long"]

    private var outDir: String {
        ProcessInfo.processInfo.environment["LAB_OUT"] ?? NSTemporaryDirectory()
    }

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func test1Slow() { sweep("slow") }
    @MainActor
    func test2Slower() { sweep("slower") }
    @MainActor
    func test3Drag() { sweep("drag") }
    @MainActor
    func test4Flick() { sweep("flick") }

    /// (B) with History opened and left every way UIKit offers: Back, a swipe
    /// all the way, and a swipe let go, which UIKit calls off. The bar is the
    /// page's, so it should go with the page and never sit over History.
    @MainActor
    func test5History() {
        for variant in ["inlineForm"] {
            let tag = "\(variant)__history"
            XCTContext.runActivity(named: tag) { _ in
                var notes: [String] = []
                let app = launch(variant, content: "ammy", tag: tag)
                func note(_ what: String) {
                    let start = app.buttons["Start"]
                    let exists = start.exists
                    let frame = exists ? "\(start.frame)" : "-"
                    let hittable = exists && start.isHittable
                    notes.append("\(Date().timeIntervalSince1970) \(what) | Start exists=\(exists) hittable=\(hittable) frame=\(frame) | History bar=\(app.navigationBars["History"].exists)")
                    write(notes, to: tag + "-marks.txt")
                }
                shot(tag + "__0_launch")
                // History may sit under the bar or below the fold on an SE.
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1.5)
                note("scrolled")
                let history = app.buttons["History"]
                let back = app.navigationBars["History"].buttons.element(boundBy: 0)
                let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                let far = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                let near = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))

                note("push 1"); history.tap()
                shot(tag + "__1_push_mid")
                Thread.sleep(forTimeInterval: 1.5)
                shot(tag + "__2_history"); note("History shown")
                note("back"); back.tap()
                shot(tag + "__3_pop_mid")
                Thread.sleep(forTimeInterval: 1.5)
                shot(tag + "__4_back"); note("back, settled")

                note("push 2"); history.tap(); Thread.sleep(forTimeInterval: 1.5)
                note("History shown")
                note("swipe all the way")
                edge.press(forDuration: 0.05, thenDragTo: far,
                           withVelocity: XCUIGestureVelocity(rawValue: 1500), thenHoldForDuration: 0)
                shot(tag + "__5_swipe_end")
                Thread.sleep(forTimeInterval: 1.5)
                shot(tag + "__6_after_swipe"); note("after the full swipe")
                if app.navigationBars["History"].exists {
                    note("back, as the swipe didn't take"); back.tap(); Thread.sleep(forTimeInterval: 1.5)
                }

                note("push 3"); history.tap(); Thread.sleep(forTimeInterval: 1.5)
                note("swipe let go")
                edge.press(forDuration: 0.05, thenDragTo: near,
                           withVelocity: XCUIGestureVelocity(rawValue: 300), thenHoldForDuration: 0.5)
                shot(tag + "__7_letgo_end")
                Thread.sleep(forTimeInterval: 1.5)
                shot(tag + "__8_after_letgo"); note("after the let-go swipe")
                if app.navigationBars["History"].exists {
                    note("back after the let-go swipe"); back.tap(); Thread.sleep(forTimeInterval: 1.5)
                }
                shot(tag + "__9_end"); note("end")
                app.terminate()
            }
        }
    }

    /// Scrolled to the end: the last row should clear the button.
    @MainActor
    func test6Bottom() {
        for variant in ["inlineForm", "inlineStack", "ammy", "stackMargins"] {
            let tag = "\(variant)__bottom"
            XCTContext.runActivity(named: tag) { _ in
                let app = launch(variant, content: "ammy", tag: tag)
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1.5)
                app.swipeUp()
                Thread.sleep(forTimeInterval: 2.0)
                let history = app.buttons["History"]
                let start = app.buttons["Start"]
                let lines = [
                    "History exists=\(history.exists) frame=\(history.exists ? "\(history.frame)" : "-")",
                    "Start exists=\(start.exists) frame=\(start.exists ? "\(start.frame)" : "-")",
                    "window frame=\(app.windows.firstMatch.frame)",
                ]
                write(lines, to: tag + ".txt")
                shot(tag)
                app.terminate()
            }
        }
    }

    @MainActor
    private func sweep(_ gesture: String) {
        for content in Self.contents {
            for variant in Self.variants {
                run(variant, content: content, gesture: gesture)
            }
        }
    }

    @MainActor
    private func launch(_ variant: String, content: String, tag: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-variant", variant, "-content", content]
        app.launchEnvironment = ["LAB_OUT": outDir, "LAB_TAG": tag]
        app.launch()
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 1.0)
        return app
    }

    @MainActor
    private func run(_ variant: String, content: String, gesture: String) {
        let tag = "\(variant)__\(content)__\(gesture)"
        XCTContext.runActivity(named: tag) { _ in
            let app = launch(variant, content: content, tag: tag)
            if gesture == "slow" { shot(tag + "__0") }

            let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            switch gesture {
            case "slow":
                // The lab's slow drag down from the top.
                low.press(forDuration: 0.3, thenDragTo: middle,
                          withVelocity: XCUIGestureVelocity(rawValue: 150), thenHoldForDuration: 0.5)
            case "slower":
                // Slower again, over the same distance.
                low.press(forDuration: 0.3, thenDragTo: middle,
                          withVelocity: XCUIGestureVelocity(rawValue: 80), thenHoldForDuration: 0.5)
            case "drag":
                // The lab's fast drag.
                low.press(forDuration: 0.3, thenDragTo: high,
                          withVelocity: XCUIGestureVelocity(rawValue: 600), thenHoldForDuration: 0.5)
            case "flick":
                low.press(forDuration: 0.01, thenDragTo: middle,
                          withVelocity: .fast, thenHoldForDuration: 0)
            default:
                break
            }
            Thread.sleep(forTimeInterval: 2.0)
            if gesture == "slow" || gesture == "drag" { shot(tag + "__1") }
            app.terminate()
        }
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
}
