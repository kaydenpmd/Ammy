import UIKit
import XCTest

/// pip-lab, never merged. PiPHost floats a magenta video in Picture in
/// Picture; then each app or Bars variant comes to the front in turn, and
/// the PiP window's frame is read from SpringBoard's own element for it
/// ("PIP-SBInteractionPassThroughView", found in run 44280673989): where it
/// arrives (resting bottom right over the app before), then dragged to the
/// bottom left, then back to the bottom right. The keyboard, which PiP is
/// known to keep clear of, is the positive control at the end.
///
/// Everything goes to LAB_OUT: pip.txt (one line per step, seconds since
/// 1970), a screenshot per measurement, and each app's accessibility tree.
final class PiPLabUITests: XCTestCase {
    private var outDir: String {
        ProcessInfo.processInfo.environment["LAB_OUT"] ?? NSTemporaryDirectory()
    }
    private var lines: [String] = []

    @MainActor private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    @MainActor private var screen: CGSize { UIScreen.main.bounds.size }

    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: Output

    private func now() -> String { String(format: "%.3f", Date().timeIntervalSince1970) }

    private func log(_ line: String) {
        lines.append("\(now()) \(line)")
        print("[lab] \(line)")
        write(lines.joined(separator: "\n") + "\n", to: "pip.txt")
    }

    private func write(_ text: String, to name: String) {
        try? text.write(toFile: (outDir as NSString).appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    @MainActor
    private func save(_ shot: XCUIScreenshot, _ name: String) {
        let url = URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png")
        do {
            try shot.pngRepresentation.write(to: url)
        } catch {
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func fmt(_ r: CGRect) -> String {
        String(format: "x=%.1f y=%.1f w=%.1f h=%.1f maxY=%.1f", r.minX, r.minY, r.width, r.height, r.maxY)
    }

    // MARK: The window and the bars

    @MainActor
    private func pipFrame() -> CGRect? {
        let element = springboard.descendants(matching: .any)["PIP-SBInteractionPassThroughView"]
        return element.exists ? element.frame : nil
    }

    @MainActor
    @discardableResult
    private func record(_ tag: String) -> CGRect? {
        let frame = pipFrame()
        save(XCUIScreen.main.screenshot(), tag)
        if let frame {
            log("\(tag) pip=[\(fmt(frame))] fromBottom=\(String(format: "%.1f", screen.height - frame.maxY))")
        } else {
            log("\(tag) pip=none")
        }
        return frame
    }

    /// Every tab bar and toolbar the app reports, and its Start or Stop.
    @MainActor
    private func bars(_ app: XCUIApplication) -> String {
        var parts: [String] = []
        for (name, query) in [("tabBar", app.tabBars), ("toolbar", app.toolbars)] {
            for (i, element) in query.allElementsBoundByIndex.enumerated() where element.exists {
                parts.append("\(name)\(i)=[\(fmt(element.frame))]")
            }
        }
        for label in ["Start", "Stop", "Accessory"] {
            let element = app.descendants(matching: .any)[label].firstMatch
            if element.exists { parts.append("\(label)=[\(fmt(element.frame))]") }
        }
        return parts.joined(separator: " ")
    }

    /// Answers SpringBoard's alerts (Ammy asks for notifications when its
    /// session starts) so they don't dim the screen for the rest of the run.
    @MainActor
    private func answerAlerts() {
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.exists else { return }
            let allow = alert.buttons["Allow"]
            let button = allow.exists ? allow : alert.buttons.element(boundBy: alert.buttons.count - 1)
            log("alert '\(alert.label)': tapping '\(button.label)'")
            button.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    // MARK: Moving it

    /// A slow drag with a pause before letting go, so PiP settles in the
    /// corner it's left nearest rather than being thrown.
    @MainActor
    private func dragPiP(toRight right: Bool, in app: XCUIApplication) {
        guard let r = pipFrame() else {
            log("no PiP to drag")
            return
        }
        let target = CGPoint(x: right ? screen.width - r.width / 2 - 16 : r.width / 2 + 16,
                             y: screen.height - r.height / 2 - 40)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: r.midX, dy: r.midY))
            .press(forDuration: 0.15, thenDragTo: origin.withOffset(CGVector(dx: target.x, dy: target.y)),
                   withVelocity: XCUIGestureVelocity(rawValue: 500), thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 2.0)
    }

    @MainActor
    private func visit(_ name: String, bundle: String, arguments: [String] = []) {
        let app = XCUIApplication(bundleIdentifier: bundle)
        app.launchArguments = arguments
        log("\(name) launching \(bundle) \(arguments.joined(separator: " "))")
        app.launch()
        let foreground = app.wait(for: .runningForeground, timeout: 20)
        Thread.sleep(forTimeInterval: 2.0)
        answerAlerts()
        Thread.sleep(forTimeInterval: 1.0)
        log("\(name) foreground=\(foreground) \(bars(app))")
        write(app.debugDescription, to: "\(name)__tree.txt")
        record("\(name)__arrive")
        dragPiP(toRight: false, in: app)
        record("\(name)__bottomLeft")
        dragPiP(toRight: true, in: app)
        record("\(name)__bottomRight")
    }

    // MARK: The run

    @MainActor
    func testPiP() {
        log("screen \(screen.width) x \(screen.height) pt, scale \(UIScreen.main.scale)")
        let host = XCUIApplication()
        host.launchEnvironment = ["LAB_OUT": outDir]
        host.launch()
        let status = host.staticTexts["status"]
        var possible = false
        for _ in 0..<60 {
            if status.exists, status.label.contains("possible=true") {
                possible = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        log("host possible=\(possible) status: \(status.exists ? status.label.replacingOccurrences(of: "\n", with: " / ") : "-")")
        host.buttons["startPiP"].tap()
        var started = false
        for _ in 0..<30 {
            if status.label.contains("didStart") {
                started = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        log("host started=\(started)")
        Thread.sleep(forTimeInterval: 2)
        record("host__started")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
        record("home__arrive")
        dragPiP(toRight: true, in: springboard)
        record("home__bottomRight")

        let variants = ["none", "toolbar", "tabbar", "accessory", "safeareabar", "addlsafe", "tabbar-hidden",
                        "toolbar-hidden", "toolbar-wide", "safeareainset", "uikit-edge", "uikit-toolbar"]
        for variant in variants {
            visit("bars-\(variant)", bundle: "com.local.bars", arguments: ["-variant", variant])
        }
        visit("ammy", bundle: "com.local.ammy", arguments: ["-relay_endpoint", "https://lab.invalid/now-playing"])
        visit("settings", bundle: "com.apple.Preferences")

        // The positive control: PiP resting bottom right over Ammy, then the
        // keyboard for the URL field.
        let ammy = XCUIApplication(bundleIdentifier: "com.local.ammy")
        ammy.activate()
        _ = ammy.wait(for: .runningForeground, timeout: 10)
        Thread.sleep(forTimeInterval: 2)
        answerAlerts()
        record("ammy-keyboard__before")
        let url = ammy.textFields["URL"]
        if url.waitForExistence(timeout: 5) {
            url.tap()
            let shown = ammy.keyboards.firstMatch.waitForExistence(timeout: 5)
            Thread.sleep(forTimeInterval: 2)
            log("ammy-keyboard shown=\(shown) keyboard=\(ammy.keyboards.firstMatch.exists ? fmt(ammy.keyboards.firstMatch.frame) : "none") \(bars(ammy))")
            record("ammy-keyboard__up")
        } else {
            log("ammy-keyboard: no URL field")
        }
        log("done")
    }
}
