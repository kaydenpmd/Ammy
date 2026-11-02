import XCTest

/// Ammy's screen three ways, for the section-header question:
///
///   current    build 156 as it is: a large title over three headed sections
///   noHeaders  option 1: the large title, the three headers removed
///   inline     option 2: the headers kept, the title inline
///
/// Each variant is launched fresh for each position, with -HeaderLabDemo, so
/// the screen shows a track, an address, Connected and Stop. Positions:
///
///   top        at rest, as the app opens
///   mid        a slow drag of 120 pt up, let go: past the large title's
///              52 pt collapse, if the page is tall enough to stay there
///   mid-held   the same drag, photographed from outside (simctl, by the
///              workflow) while the finger is still down, for a page too short
///              to stay scrolled once let go
///   bottom     swiped up until History is clear of the bar
///
/// Each position is saved to LAB_OUT as <variant>-<position>.png, with the
/// element tree and its frames, in points, beside it as .txt.
final class HeaderLabUITests: XCTestCase {
    private static let variants = ["current", "noHeaders", "inline"]

    private var outDir: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["LAB_OUT"] ?? NSTemporaryDirectory())
    }

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    private func launch(_ variant: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.local.ammy")
        app.launchArguments = ["-HeaderLab", variant, "-HeaderLabDemo"]
        app.launch()
        if !app.buttons["Stop"].waitForExistence(timeout: 20) {
            note("\(variant): no Stop button 20 s after launch")
        }
        // Time for the Now Playing row to measure the list's insets (it waits
        // for 150 ms of stillness) and to make its cover's thumbnail.
        Thread.sleep(forTimeInterval: 2)
        return app
    }

    @MainActor
    private func save(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        do {
            try shot.pngRepresentation.write(to: outDir.appendingPathComponent("\(name).png"))
        } catch {
            note("\(name): couldn't write the screenshot: \(error)")
        }
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? app.debugDescription.write(to: outDir.appendingPathComponent("\(name).txt"),
                                        atomically: true, encoding: .utf8)
    }

    /// Anything that didn't go to plan, so a missing or odd picture has a
    /// reason beside it.
    private func note(_ line: String) {
        let url = outDir.appendingPathComponent("notes.txt")
        let text = "\(Date().timeIntervalSince1970) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Asks the workflow's helper to photograph the simulator `delay` seconds
    /// from now, with simctl, which can do it while a gesture is under way.
    private func requestOutsideShot(_ name: String, after delay: Double) {
        try? "\(delay)".write(to: outDir.appendingPathComponent("\(name).request"),
                              atomically: true, encoding: .utf8)
    }

    private func waitForOutsideShot(_ name: String) {
        let done = outDir.appendingPathComponent("\(name).done").path
        let deadline = Date().addingTimeInterval(12)
        while !FileManager.default.fileExists(atPath: done), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        if !FileManager.default.fileExists(atPath: done) {
            note("\(name): the helper never took it")
        }
    }

    @MainActor
    func testTop() {
        for variant in Self.variants {
            let app = launch(variant)
            save(app, "\(variant)-top")
            app.terminate()
        }
    }

    @MainActor
    func testMid() {
        for variant in Self.variants {
            let app = launch(variant)
            // Started low on the page, on the Status rows, clear of the text
            // fields, and slow enough to leave no momentum when let go.
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            let to = from.withOffset(CGVector(dx: 0, dy: -120))
            requestOutsideShot("\(variant)-mid-held", after: 2.5)
            from.press(forDuration: 0.2, thenDragTo: to,
                       withVelocity: XCUIGestureVelocity(rawValue: 300), thenHoldForDuration: 4)
            waitForOutsideShot("\(variant)-mid-held")
            Thread.sleep(forTimeInterval: 2)
            save(app, "\(variant)-mid")
            app.terminate()
        }
    }

    @MainActor
    func testBottom() {
        for variant in Self.variants {
            let app = launch(variant)
            let history = app.buttons["History"]
            let stop = app.buttons["Stop"]
            for attempt in 1...4 {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 2)
                if history.exists, stop.exists, history.frame.maxY <= stop.frame.minY {
                    break
                }
                note("\(variant): History not clear of the bar after swipe \(attempt)")
            }
            save(app, "\(variant)-bottom")
            app.terminate()
        }
    }
}
