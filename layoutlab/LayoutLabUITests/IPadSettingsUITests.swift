import XCTest

/// Drives Settings on an iPad simulator, in landscape and in portrait, and
/// saves for each screen a screenshot and the accessibility tree. Every tap is
/// logged with its time to events.txt, so pushes can be found in the run's
/// screen recording.
final class IPadSettingsUITests: XCTestCase {
    private let out = ProcessInfo.processInfo.environment["LAB_OUT"] ?? NSTemporaryDirectory()
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

    private func log(_ text: String) {
        let line = String(format: "%.3f %@\n", Date().timeIntervalSince1970, text)
        let url = URL(fileURLWithPath: out).appendingPathComponent("events.txt")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func save(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
        try? settings.debugDescription.write(
            to: URL(fileURLWithPath: out).appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        log("saved \(name)")
    }

    /// Taps the first cell, button or text with this label.
    @discardableResult
    private func tap(_ label: String) -> Bool {
        for q in [settings.cells, settings.buttons, settings.staticTexts] {
            let e = q.matching(NSPredicate(format: "label == %@", label)).firstMatch
            if e.waitForExistence(timeout: 4), e.isHittable {
                log("tap \(label)")
                e.tap()
                return true
            }
        }
        log("couldn't find \(label)")
        return false
    }

    private func back() {
        let b = settings.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
        if b.waitForExistence(timeout: 3) { log("tap Back"); b.tap() } else { log("no back button") }
    }

    func testSettings() throws {
        for (tag, orientation) in [("landscape", UIDeviceOrientation.landscapeLeft), ("portrait", .portrait)] {
            XCUIDevice.shared.orientation = orientation
            settings.terminate()
            settings.launch()
            sleep(4)
            save("\(tag)-root")

            // A sidebar choice, then a push inside the detail column, then back.
            if tap("General") { sleep(3); save("\(tag)-general") }
            if tap("About") { sleep(3); save("\(tag)-general-about") }
            back(); sleep(3); save("\(tag)-general-back")

            for page in ["Accessibility", "Display & Brightness", "Wi-Fi", "Privacy & Security"] {
                if tap(page) { sleep(3); save("\(tag)-" + page.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "&", with: "and")) }
            }

            // Scroll the detail column once, for headers and footers below the fold.
            settings.swipeUp()
            sleep(2)
            save("\(tag)-privacy-scrolled")
        }
    }
}
