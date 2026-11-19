import UIKit
import XCTest

/// bar-width-lab, never merged: each Widths variant, the real Ammy and Apple's own apps, photographed as they open, with the frames of everything in the bottom third of the screen. The workflow runs it once in dark mode and once in light, and says which in LAB_SUFFIX. Everything goes to LAB_OUT.
final class WidthsUITests: XCTestCase {
    private var outDir: String { ProcessInfo.processInfo.environment["LAB_OUT"] ?? NSTemporaryDirectory() }
    private var suffix: String { ProcessInfo.processInfo.environment["LAB_SUFFIX"] ?? "" }
    private var lines: [String] = []

    override func setUp() {
        continueAfterFailure = true
    }

    private func now() -> String { String(format: "%.3f", Date().timeIntervalSince1970) }

    private func write(_ text: String, to name: String) {
        try? text.write(toFile: (outDir as NSString).appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func log(_ line: String) {
        lines.append("\(now()) \(line)")
        print("[lab] \(line)")
        write(lines.joined(separator: "\n") + "\n", to: "frames\(suffix).txt")
    }

    @MainActor
    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name + suffix + ".png"))
    }

    private func fmt(_ r: CGRect) -> String {
        String(format: "x=%.2f y=%.2f w=%.2f h=%.2f maxX=%.2f maxY=%.2f", r.minX, r.minY, r.width, r.height, r.maxX, r.maxY)
    }

    /// Everything the app's accessibility tree has in the screen's bottom third.
    @MainActor
    private func bottom(_ app: XCUIApplication, _ tag: String) {
        let screen = app.windows.firstMatch.frame
        log("\(tag) window=[\(fmt(screen))]")
        let types: [(String, XCUIElement.ElementType)] = [
            ("tabBar", .tabBar), ("toolbar", .toolbar), ("button", .button), ("searchField", .searchField),
        ]
        for (name, type) in types {
            for element in app.descendants(matching: type).allElementsBoundByIndex.prefix(120) {
                guard element.exists else { continue }
                let r = element.frame
                guard r.maxY > screen.height * 0.66, r.width > 0, r.height > 0, r.height < screen.height * 0.5 else { continue }
                log("\(tag) \(name) '\(element.label)' id='\(element.identifier)' [\(fmt(r))]")
            }
        }
        write(app.debugDescription, to: "\(tag)\(suffix)__tree.txt")
    }

    @MainActor
    private func open(_ app: XCUIApplication, _ tag: String) {
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
        Thread.sleep(forTimeInterval: 3.0)
        shot(tag)
        bottom(app, tag)
    }

    /// Each first-run page's own button, photographed, then pressed, a few times over: Apple's full-width buttons in their own sheets.
    @MainActor
    private func walkWelcome(_ app: XCUIApplication, _ tag: String) {
        for step in 1...3 {
            let candidates = ["Continue", "Get Started", "Not Now", "Next", "OK", "Done", "Allow"]
            guard let label = candidates.first(where: { app.buttons[$0].firstMatch.exists }) else { return }
            let button = app.buttons[label].firstMatch
            log("\(tag) welcome \(step): '\(label)' [\(fmt(button.frame))]")
            button.tap()
            Thread.sleep(forTimeInterval: 2.5)
            shot("\(tag)__after\(step)")
            bottom(app, "\(tag)__after\(step)")
        }
    }

    @MainActor
    func testWidths() {
        for variant in ["tab5", "tab4search", "tab3", "tab2", "accessory", "toolbar2", "toolbar1", "toolbarsearch"] {
            let app = XCUIApplication()
            app.launchArguments = ["-variant", variant]
            open(app, "widths-\(variant)")
            app.terminate()
        }

        // Ammy as released, with no address, so its Start shows and nothing starts.
        let ammy = XCUIApplication(bundleIdentifier: "com.local.ammy")
        open(ammy, "ammy")
        ammy.terminate()

        let apple: [(String, String)] = [
            ("settings", "com.apple.Preferences"), ("photos", "com.apple.mobileslideshow"),
            ("files", "com.apple.DocumentsApp"), ("health", "com.apple.Health"),
            ("reminders", "com.apple.reminders"), ("safari", "com.apple.mobilesafari"),
            ("contacts", "com.apple.MobileAddressBook"), ("calendar", "com.apple.mobilecal"),
            ("shortcuts", "com.apple.shortcuts"), ("freeform", "com.apple.freeform"),
            ("journal", "com.apple.journal"), ("passwords", "com.apple.Passwords"),
            ("wallet", "com.apple.Passbook"), ("maps", "com.apple.Maps"),
        ]
        for (tag, bundle) in apple {
            let app = XCUIApplication(bundleIdentifier: bundle)
            log("\(tag) launching \(bundle)")
            open(app, tag)
            walkWelcome(app, tag)
            app.terminate()
        }
        log("done")
    }
}
