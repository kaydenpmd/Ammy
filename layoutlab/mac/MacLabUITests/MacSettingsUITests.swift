import XCTest

/// Drives System Settings and saves, for each page, the window's picture, the
/// whole screen, and the accessibility tree (every element's frame, in points).
final class MacSettingsUITests: XCTestCase {
    // The runner is sandboxed; its own tmp folder is the one place it can write.
    private let out = NSTemporaryDirectory()
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.systempreferences")

    private func log(_ text: String) {
        let line = String(format: "%.3f %@\n", Date().timeIntervalSince1970, text)
        let url = URL(fileURLWithPath: out).appendingPathComponent("events.txt")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func attach(_ data: Data, _ name: String, _ type: String) {
        let a = XCTAttachment(data: data, uniformTypeIdentifier: type)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func save(_ name: String) {
        let dir = URL(fileURLWithPath: out)
        let w = settings.windows.firstMatch
        if w.exists { attach(w.screenshot().pngRepresentation, name + "-window.png", "public.png") }
        attach(Data(settings.debugDescription.utf8), name + ".txt", "public.plain-text")
        let window = settings.windows.firstMatch
        if window.exists {
            try? window.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name + "-window.png"))
            log("window \(name) frame \(NSStringFromRect(window.frame))")
        }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name + "-screen.png"))
        try? settings.debugDescription.write(to: dir.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        log("saved \(name)")
    }

    @discardableResult
    private func click(_ label: String) -> Bool {
        for q in [settings.outlines.cells, settings.cells, settings.buttons, settings.staticTexts] {
            let e = q.matching(NSPredicate(format: "label == %@ OR title == %@ OR value == %@", label, label, label)).firstMatch
            if e.waitForExistence(timeout: 4), e.isHittable {
                log("click \(label)")
                e.click()
                return true
            }
        }
        log("couldn't find \(label)")
        return false
    }

    func testSystemSettings() throws {
        settings.launch()
        sleep(5)
        save("root")
        for page in ["General", "Appearance", "Wi-Fi", "Privacy & Security", "Desktop & Dock", "Notifications"] {
            if click(page) { sleep(3); save(page.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "&", with: "and")) }
        }
        // A page inside a page: General › About, then back.
        if click("General") { sleep(2) }
        if click("About") { sleep(3); save("general-about") }
        let back = settings.buttons.matching(NSPredicate(format: "label == 'Back' OR identifier == 'go back'")).firstMatch
        if back.waitForExistence(timeout: 3) { log("click Back"); back.click(); sleep(2); save("general-back") }
    }
}
