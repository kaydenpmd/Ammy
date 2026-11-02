import XCTest

/// The real Ammy, installed beside the lab app, scrolled slowly down from the
/// top with its bar on the stack and then on the Form (the temporary
/// barOnStack switch, forced through the launch arguments). The screen
/// recording is the measurement; this writes when each run's drag starts.
final class AmmyUITests: XCTestCase {
    private var outDir: String {
        ProcessInfo.processInfo.environment["LAB_OUT"] ?? NSTemporaryDirectory()
    }

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testAmmySlow() {
        var marks: [String] = []
        for round in 0..<2 {
            for onStack in [true, false] {
                let app = XCUIApplication(bundleIdentifier: "com.local.ammy")
                app.launchArguments = ["-barOnStack", onStack ? "YES" : "NO"]
                app.launch()
                _ = app.navigationBars.firstMatch.waitForExistence(timeout: 15)
                Thread.sleep(forTimeInterval: 1.5)
                let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                marks.append("\(Date().timeIntervalSince1970) start \(onStack ? "stack" : "form") round \(round)")
                low.press(forDuration: 0.3, thenDragTo: middle,
                          withVelocity: XCUIGestureVelocity(rawValue: 150), thenHoldForDuration: 0.5)
                marks.append("\(Date().timeIntervalSince1970) end \(onStack ? "stack" : "form") round \(round)")
                Thread.sleep(forTimeInterval: 1.5)
                let shot = XCUIScreen.main.screenshot().pngRepresentation
                try? shot.write(to: URL(fileURLWithPath: outDir)
                    .appendingPathComponent("ammy-\(onStack ? "stack" : "form")-\(round).png"))
                app.terminate()
            }
        }
        try? marks.joined(separator: "\n")
            .write(toFile: (outDir as NSString).appendingPathComponent("ammy-marks.txt"), atomically: true, encoding: .utf8)
    }
}
