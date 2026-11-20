import UIKit
import XCTest

/// wide-bar-lab, never merged.
///
/// test1Ammy: the real Ammy, built from this branch, its bar placed at launch (Ammy/LabSwitch.swift): as released (21 pt from the sides and the bottom) and as Apple's wide bottom button (38 and 38), with the buttons at the large control size and at extraLarge. At rest with Start, with Stop, and with Stop and Restart; at the end of the page; and with the keyboard up for the URL and the Key.
///
/// test2Reference: does Apple put its wide bottom button above the keyboard anywhere? Settings' Apple Account sign-in, then every other Apple app in LAB_APPS: each screen's buttons and fields are logged and photographed, a first-run button is pressed, and any text field met is tapped so the keyboard comes up.
///
/// Everything goes to LAB_OUT: frames.txt (one line per element, seconds since 1970), a screenshot per step and each screen's accessibility tree.
final class WideBarUITests: XCTestCase {
    private var outDir: String { ProcessInfo.processInfo.environment["LAB_OUT"] ?? NSTemporaryDirectory() }
    private var lines: [String] = []
    private var logName = "frames.txt"

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
        write(lines.joined(separator: "\n") + "\n", to: logName)
    }

    @MainActor
    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png"))
    }

    private func fmt(_ r: CGRect) -> String {
        String(format: "x=%.2f y=%.2f w=%.2f h=%.2f maxX=%.2f maxY=%.2f", r.minX, r.minY, r.width, r.height, r.maxX, r.maxY)
    }

    /// Every button, field, cell and keyboard on screen, with the window, and the tree in its own file.
    @MainActor
    private func dump(_ app: XCUIApplication, _ tag: String, tree: Bool = true) {
        log("\(tag) window=[\(fmt(app.windows.firstMatch.frame))]")
        let types: [(String, XCUIElement.ElementType)] = [
            ("button", .button), ("textField", .textField), ("secureTextField", .secureTextField),
            ("searchField", .searchField), ("cell", .cell), ("keyboard", .keyboard), ("navigationBar", .navigationBar),
        ]
        for (name, type) in types {
            for element in app.descendants(matching: type).allElementsBoundByIndex.prefix(60) where element.exists {
                let r = element.frame
                guard r.width > 0, r.height > 0 else { continue }
                log("\(tag) \(name) '\(element.label.prefix(60))' [\(fmt(r))]")
            }
        }
        if tree { write(app.debugDescription, to: "\(tag)__tree.txt") }
    }

    // MARK: 1. Ammy's bar, as released and as Apple's wide button

    private struct Placement {
        let name: String
        let side: Int, bottom: Int, keyboardGap: Int
        let size: String
    }

    @MainActor
    private func launchAmmy(_ p: Placement, running: Bool, textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.local.ammy")
        app.launchArguments = ["-labSide", "\(p.side)", "-labBottom", "\(p.bottom)", "-labKeyboardGap", "\(p.keyboardGap)",
                               "-labSize", p.size, "-labRunning", running ? "YES" : "NO",
                               "-relay_endpoint", "https://lab.invalid/now-playing"]
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        app.launch()
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 2.0)
        return app
    }

    @MainActor
    func test1Ammy() {
        logName = "frames-ammy.txt"
        // wide-bar-check: one placement, the wide-bar branch's own constants (38 from the sides and the bottom, 10 above the keyboard). The launch switch is gone, so these numbers go unread.
        let placements = [
            Placement(name: "new2", side: 38, bottom: 38, keyboardGap: 10, size: "large"),
        ]
        for p in placements {
            // Start, at the top of the page.
            var app = launchAmmy(p, running: false)
            shot("\(p.name)__start")
            dump(app, "\(p.name)__start")
            app.terminate()

            // Stop, at the top, then at the end of the page.
            app = launchAmmy(p, running: true)
            shot("\(p.name)__stop")
            dump(app, "\(p.name)__stop", tree: false)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)),
                       withVelocity: .fast, thenHoldForDuration: 0)
            Thread.sleep(forTimeInterval: 2.5)
            shot("\(p.name)__stop_end")
            dump(app, "\(p.name)__stop_end", tree: false)
            app.terminate()

            // The keyboard: the URL tapped, a letter typed (Restart comes beside Stop), then Return.
            app = launchAmmy(p, running: true)
            let url = app.textFields["URL"]
            if url.waitForExistence(timeout: 5) {
                url.tap()
                _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
                Thread.sleep(forTimeInterval: 1.5)
                shot("\(p.name)__kbURL")
                dump(app, "\(p.name)__kbURL", tree: false)
                url.typeText("x")
                Thread.sleep(forTimeInterval: 1.5)
                shot("\(p.name)__kbURL_typed")
                dump(app, "\(p.name)__kbURL_typed", tree: false)
                url.typeText("\n")
                Thread.sleep(forTimeInterval: 2.0)
                shot("\(p.name)__stop_restart")
                dump(app, "\(p.name)__stop_restart", tree: false)
            } else {
                log("\(p.name): no URL field")
            }
            app.terminate()

            // The Key field, which sits lower: where iOS scrolls it to.
            app = launchAmmy(p, running: false)
            let key = app.secureTextFields["Key"]
            if key.waitForExistence(timeout: 5) {
                key.tap()
                _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
                Thread.sleep(forTimeInterval: 1.5)
                shot("\(p.name)__kbKey")
                dump(app, "\(p.name)__kbKey", tree: false)
            }
            app.terminate()

            // For the recording: Start alone, the keyboard up and down again, each moment stamped, so the frames between show how the buttons widen and narrow on the way.
            app = launchAmmy(p, running: false)
            let field = app.textFields["URL"]
            if field.waitForExistence(timeout: 5) {
                Thread.sleep(forTimeInterval: 1.0)
                log("\(p.name) motion: tapping URL")
                field.tap()
                Thread.sleep(forTimeInterval: 3.0)
                dump(app, "\(p.name)__motion_up", tree: false)
                log("\(p.name) motion: pressing Return")
                field.typeText("\n")
                Thread.sleep(forTimeInterval: 3.0)
                dump(app, "\(p.name)__motion_down", tree: false)
                log("\(p.name) motion: done")
            }
            app.terminate()

            // The largest ordinary text size: the buttons grow, the placement holds.
            app = launchAmmy(p, running: false, textSize: "UICTContentSizeCategoryXXXL")
            shot("\(p.name)__start_XXXL")
            dump(app, "\(p.name)__start_XXXL", tree: false)
            app.terminate()

            // History and back: the bar steps aside for the page's copy and returns.
            app = launchAmmy(p, running: true)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)),
                       withVelocity: .fast, thenHoldForDuration: 0)
            Thread.sleep(forTimeInterval: 2.0)
            let history = app.buttons["History"]
            if history.waitForExistence(timeout: 5) {
                history.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
                Thread.sleep(forTimeInterval: 2.5)
                shot("\(p.name)__history")
                dump(app, "\(p.name)__history", tree: false)
                let back = app.navigationBars["History"].buttons.element(boundBy: 0)
                if back.exists {
                    back.tap()
                    Thread.sleep(forTimeInterval: 2.5)
                }
                shot("\(p.name)__history_back")
                dump(app, "\(p.name)__history_back", tree: false)
            } else {
                log("\(p.name): no History row")
            }
            app.terminate()
        }
        log("done")
    }

    // MARK: 2. Apple's wide button and the keyboard

    private static let firstRun = ["Continue", "Get Started", "Next", "Not Now", "Skip", "OK", "Done", "Set Up Later", "Sign in Manually"]

    /// Taps the first text field on screen, if there is one, and records the screen with the keyboard up.
    @MainActor
    private func tryKeyboard(_ app: XCUIApplication, _ tag: String) -> Bool {
        let candidates = [app.textFields.firstMatch, app.secureTextFields.firstMatch, app.searchFields.firstMatch]
        guard let field = candidates.first(where: { $0.exists && $0.isHittable }) else { return false }
        log("\(tag) tapping field '\(field.label.prefix(40))' [\(fmt(field.frame))]")
        field.tap()
        let shown = app.keyboards.firstMatch.waitForExistence(timeout: 4)
        Thread.sleep(forTimeInterval: 1.5)
        log("\(tag) keyboard shown=\(shown)")
        shot("\(tag)__keyboard")
        dump(app, "\(tag)__keyboard")
        // A new simulator's first keyboard comes up under a card about sliding to type (run 44531445473); its Continue sits inside the keyboard's frame. Press it, so the keyboard itself shows.
        if shown {
            let top = app.keyboards.firstMatch.frame.minY
            let tips = app.buttons.matching(NSPredicate(format: "label == 'Continue'")).allElementsBoundByIndex
            if let tip = tips.first(where: { $0.exists && $0.frame.minY > top && $0.frame.height < 40 }) {
                log("\(tag) pressing the keyboard card's Continue [\(fmt(tip.frame))]")
                tip.tap()
                Thread.sleep(forTimeInterval: 1.5)
                shot("\(tag)__keyboard_clear")
                dump(app, "\(tag)__keyboard_clear", tree: false)
            }
        }
        if shown {
            field.typeText("a")
            Thread.sleep(forTimeInterval: 1.0)
            shot("\(tag)__keyboard_typed")
            dump(app, "\(tag)__keyboard_typed", tree: false)
        }
        return shown
    }

    /// One app: its first screen, then up to `steps` first-run buttons, trying the keyboard on every screen.
    @MainActor
    private func walk(_ app: XCUIApplication, _ tag: String, steps: Int) {
        shot("\(tag)__0")
        dump(app, "\(tag)__0")
        if tryKeyboard(app, "\(tag)__0") { return }
        for step in 1...steps {
            guard let label = Self.firstRun.first(where: { app.buttons[$0].firstMatch.exists && app.buttons[$0].firstMatch.isHittable }) else { return }
            let button = app.buttons[label].firstMatch
            log("\(tag) step \(step): pressing '\(label)' [\(fmt(button.frame))]")
            button.tap()
            Thread.sleep(forTimeInterval: 2.5)
            shot("\(tag)__\(step)")
            dump(app, "\(tag)__\(step)")
            if tryKeyboard(app, "\(tag)__\(step)") { return }
        }
    }

    /// Taps the first element whose label contains `text`, whatever its type.
    @MainActor
    private func tapLabel(_ app: XCUIApplication, containing text: String, _ tag: String) -> Bool {
        let match = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        guard match.waitForExistence(timeout: 6) else {
            log("\(tag): nothing labelled '\(text)'")
            return false
        }
        log("\(tag): tapping '\(match.label.prefix(60))' [\(fmt(match.frame))]")
        match.tap()
        Thread.sleep(forTimeInterval: 3.5)
        return true
    }

    // MARK: 3. Settings' Apple Account sheets, with the keyboard

    /// Run 44527315193 reached the Apple Account sheet and stopped: its two choices are cards, not buttons named for them. This goes on through each: Sign in Manually, whose page has an address field, and Don't have an Apple Account?, whose pages have name fields. Every page is photographed and listed, and the first field on each is tapped so the keyboard comes up.
    @MainActor
    func test3SignIn() {
        logName = "frames-signin.txt"
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        // "Apple Account" is written with a no-break space, so the second label is matched by its start (run 44531445473 found nothing labelled "have an Apple Account").
        for (flow, choice) in [("manual", "Sign in Manually"), ("create", "t have an")] {
            settings.launch()
            _ = settings.wait(for: .runningForeground, timeout: 20)
            Thread.sleep(forTimeInterval: 3)
            guard tapLabel(settings, containing: "Sign in to access", flow) else {
                settings.terminate()
                continue
            }
            shot("\(flow)__1_sheet")
            dump(settings, "\(flow)__1_sheet")
            _ = tapLabel(settings, containing: choice, flow)
            shot("\(flow)__2")
            dump(settings, "\(flow)__2")
            if !tryKeyboard(settings, "\(flow)__2") {
                // Run 44534193959: the page in between asks an age range, on cards. Adult leads on to the pages with fields.
                if tapLabel(settings, containing: "Adult", flow) {
                    shot("\(flow)__2b")
                    dump(settings, "\(flow)__2b")
                    if tryKeyboard(settings, "\(flow)__2b") {
                        settings.terminate()
                        continue
                    }
                }
                for step in 3...5 {
                    guard let label = ["Continue", "Next", "Create", "Myself", "OK"].first(where: { settings.buttons[$0].firstMatch.exists && settings.buttons[$0].firstMatch.isHittable }) else { break }
                    log("\(flow) step \(step): pressing '\(label)'")
                    settings.buttons[label].firstMatch.tap()
                    Thread.sleep(forTimeInterval: 3)
                    shot("\(flow)__\(step)")
                    dump(settings, "\(flow)__\(step)")
                    if tryKeyboard(settings, "\(flow)__\(step)") { break }
                }
            }
            settings.terminate()
        }
        log("done")
    }

    // MARK: 4. What Apple does float above the keyboard: a bottom search field

    /// Settings' and Contacts' search fields sit in the bottom toolbar. Tapped, where do they go, and how far above the keyboard?
    @MainActor
    func test4Search() {
        logName = "frames-search.txt"
        for (tag, bundle) in [("settings", "com.apple.Preferences"), ("contacts", "com.apple.MobileAddressBook")] {
            let app = XCUIApplication(bundleIdentifier: bundle)
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 20)
            Thread.sleep(forTimeInterval: 3)
            shot("\(tag)-search__0")
            dump(app, "\(tag)-search__0", tree: false)
            _ = tryKeyboard(app, "\(tag)-search")
            app.terminate()
        }
        log("done")
    }

    @MainActor
    func test2Reference() {
        logName = "frames-reference.txt"
        let installed = Set((ProcessInfo.processInfo.environment["LAB_APPS"] ?? "").split(separator: ",").map(String.init))
        log("installed: \(installed.sorted().joined(separator: " "))")

        // Settings' Apple Account sign-in: the sheet with an address field and a Continue button.
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        _ = settings.wait(for: .runningForeground, timeout: 20)
        Thread.sleep(forTimeInterval: 3)
        shot("signin__0")
        dump(settings, "signin__0")
        let row = settings.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Apple Account' OR label CONTAINS[c] 'Sign in'")).firstMatch
        if row.waitForExistence(timeout: 5) {
            log("signin row '\(row.label.prefix(60))' [\(fmt(row.frame))]")
            row.tap()
            Thread.sleep(forTimeInterval: 4)
            walk(settings, "signin", steps: 3)
        } else {
            log("signin: no Apple Account row")
        }
        settings.terminate()

        let apps: [(String, String)] = [
            ("health", "com.apple.Health"), ("fitness", "com.apple.Fitness"), ("journal", "com.apple.journal"),
            ("wallet", "com.apple.Passbook"), ("passwords", "com.apple.Passwords"), ("maps", "com.apple.Maps"),
            ("freeform", "com.apple.freeform"), ("translate", "com.apple.Translate"), ("news", "com.apple.news"),
            ("feedback", "com.apple.appleseed.FeedbackAssistant"), ("messages", "com.apple.MobileSMS"),
            ("contacts", "com.apple.MobileAddressBook"), ("reminders", "com.apple.reminders"),
        ]
        for (tag, bundle) in apps {
            guard installed.contains(bundle) else {
                log("\(tag): \(bundle) isn't installed")
                continue
            }
            let app = XCUIApplication(bundleIdentifier: bundle)
            log("\(tag) launching \(bundle)")
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 20)
            Thread.sleep(forTimeInterval: 3)
            walk(app, tag, steps: 4)
            app.terminate()
        }
        log("done")
    }
}
