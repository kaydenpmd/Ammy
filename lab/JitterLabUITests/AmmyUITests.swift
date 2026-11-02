import XCTest

/// The real Ammy, installed beside the lab app. The screen recording is the
/// measurement; these write when each gesture starts, as seconds since 1970,
/// to line them up with it.
final class AmmyUITests: XCTestCase {
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

    private func mark(_ marks: inout [String], _ what: String) {
        marks.append("\(Date().timeIntervalSince1970) \(what)")
    }

    /// History opened and left every way UIKit offers, for the bottom bar's
    /// fade: Back, a swipe all the way, and a swipe let go, which UIKit calls
    /// off, followed by Back.
    @MainActor
    func testAmmyHistory() {
        var marks: [String] = []
        let app = XCUIApplication(bundleIdentifier: "com.local.ammy")
        app.launch()
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 1.5)
        // History sits below the fold on an SE.
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1.5)
        let history = app.buttons["History"]
        let back = app.navigationBars["History"].buttons.element(boundBy: 0)
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let far = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let near = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))

        mark(&marks, "push 1"); history.tap(); Thread.sleep(forTimeInterval: 2)
        mark(&marks, "back"); back.tap(); Thread.sleep(forTimeInterval: 2)
        mark(&marks, "push 2"); history.tap(); Thread.sleep(forTimeInterval: 2)
        mark(&marks, "swipe all the way")
        edge.press(forDuration: 0.1, thenDragTo: far,
                   withVelocity: XCUIGestureVelocity(rawValue: 600), thenHoldForDuration: 0.1)
        Thread.sleep(forTimeInterval: 2)
        mark(&marks, "push 3"); history.tap(); Thread.sleep(forTimeInterval: 2)
        mark(&marks, "swipe let go")
        edge.press(forDuration: 0.1, thenDragTo: near,
                   withVelocity: XCUIGestureVelocity(rawValue: 300), thenHoldForDuration: 0.4)
        Thread.sleep(forTimeInterval: 2)
        mark(&marks, "back after the let-go swipe"); back.tap(); Thread.sleep(forTimeInterval: 2)
        let shot = XCUIScreen.main.screenshot().pngRepresentation
        try? shot.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("ammy-history-end.png"))
        app.terminate()
        write(marks, to: "ammy-history-marks.txt")
    }

    /// Scrolled slowly down from the top, twice, from a fresh launch each
    /// time: the large title should collapse with the finger.
    @MainActor
    func testAmmySlow() {
        var marks: [String] = []
        for round in 0..<2 {
            let app = XCUIApplication(bundleIdentifier: "com.local.ammy")
            app.launch()
            _ = app.navigationBars.firstMatch.waitForExistence(timeout: 15)
            Thread.sleep(forTimeInterval: 1.5)
            let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            mark(&marks, "start round \(round)")
            low.press(forDuration: 0.3, thenDragTo: middle,
                      withVelocity: XCUIGestureVelocity(rawValue: 150), thenHoldForDuration: 0.5)
            mark(&marks, "end round \(round)")
            Thread.sleep(forTimeInterval: 1.5)
            let shot = XCUIScreen.main.screenshot().pngRepresentation
            try? shot.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("ammy-slow-\(round).png"))
            app.terminate()
        }
        write(marks, to: "ammy-marks.txt")
    }
}
