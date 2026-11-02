import XCTest

/// The real Ammy, installed beside the lab app, built from this branch with
/// the probe in it (Ammy/LabProbe.swift) and its layout picked at launch by
/// `-labLayout`: "largeForm" (A, build 148: a large title, the bar on the
/// Form), "inlineForm" (B, option 2: an inline title, the bar on the Form),
/// "inlineStack" (C: an inline title, the bar on the stack as build 156 has
/// it) and "main" (build 156 as shipped). The probe logs every frame to
/// LAB_OUT, the screen recording covers the History slides, and the marks
/// are seconds since 1970, to line them up with it.
final class AmmyUITests: XCTestCase {
    private static let layouts = ["largeForm", "inlineForm", "inlineStack", "main"]

    private var outDir: String {
        ProcessInfo.processInfo.environment["LAB_OUT"] ?? NSTemporaryDirectory()
    }

    override func setUp() {
        continueAfterFailure = true
    }

    private func write(_ marks: [String], to name: String) {
        try? marks.joined(separator: "\n")
            .write(toFile: (outDir as NSString).appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    @MainActor
    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png"))
    }

    @MainActor
    private func launch(_ layout: String, tag: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.local.ammy")
        app.launchArguments = ["-labLayout", layout]
        app.launchEnvironment = ["LAB_OUT": outDir, "LAB_TAG": tag]
        app.launch()
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 1.5)
        return app
    }

    /// Each layout scrolled down from the top, from a fresh launch each time:
    /// slowly, more slowly, fast, and flicked.
    @MainActor
    func test1AmmyScroll() {
        var marks: [String] = []
        for layout in Self.layouts {
            for gesture in ["slow", "slower", "drag", "flick"] {
                let tag = "real-\(layout)__\(gesture)"
                let app = launch(layout, tag: tag)
                if gesture == "slow" { shot(tag + "__0") }
                let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
                let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                marks.append("\(Date().timeIntervalSince1970) start \(tag)")
                write(marks, to: "ammy-scroll-marks.txt")
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
                marks.append("\(Date().timeIntervalSince1970) end \(tag)")
                write(marks, to: "ammy-scroll-marks.txt")
                Thread.sleep(forTimeInterval: 1.5)
                if gesture == "slow" || gesture == "drag" { shot(tag + "__1") }
                app.terminate()
            }
        }
    }

    /// Option 2 with History opened and left every way UIKit offers: Back, a
    /// swipe all the way, and a swipe let go, which UIKit calls off, followed
    /// by Back. The marks are written as they happen, so a run that stops
    /// early still has them, and each says whether the Start button is there.
    @MainActor
    func test2AmmyHistory() {
        for layout in ["inlineForm"] {
            let tag = "real-\(layout)__history"
            var marks: [String] = []
            let app = launch(layout, tag: tag)
            func mark(_ what: String) {
                let start = app.buttons["Start"]
                let exists = start.exists
                let frame = exists ? "\(start.frame)" : "-"
                let hittable = exists && start.isHittable
                marks.append("\(Date().timeIntervalSince1970) \(what) | Start exists=\(exists) hittable=\(hittable) frame=\(frame) | History bar=\(app.navigationBars["History"].exists)")
                write(marks, to: tag + "-marks.txt")
            }
            shot(tag + "__0_launch")
            // History sits below the fold on an SE.
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1.5)
            mark("scrolled")
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

    /// Scrolled to the end: the last row should clear the button.
    @MainActor
    func test3AmmyBottom() {
        for layout in ["inlineForm", "main", "largeForm"] {
            let tag = "real-\(layout)__bottom"
            let app = launch(layout, tag: tag)
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1.5)
            app.swipeUp()
            Thread.sleep(forTimeInterval: 2.0)
            let history = app.buttons["History"]
            let start = app.buttons["Start"]
            write([
                "History exists=\(history.exists) frame=\(history.exists ? "\(history.frame)" : "-")",
                "Start exists=\(start.exists) frame=\(start.exists ? "\(start.frame)" : "-")",
                "window frame=\(app.windows.firstMatch.frame)",
            ], to: tag + ".txt")
            shot(tag)
            app.terminate()
        }
    }
}
