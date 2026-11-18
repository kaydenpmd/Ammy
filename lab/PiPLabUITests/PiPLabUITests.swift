import UIKit
import XCTest

/// pip-lab, never merged. PiPHost floats a magenta video in Picture in
/// Picture; then the Home Screen and each app in turn come to the front, and
/// the PiP window is found by its colour, measured where it arrives, dragged
/// towards each corner and measured where it settles. The last corner is the
/// bottom right, so every app after the first is reached with PiP resting
/// there over the app before it: if PiP moved for an app's bar, its arrival
/// would show it. The keyboard, which PiP is known to keep clear of, is the
/// positive control at the end.
///
/// Everything goes to LAB_OUT: pip.txt (one line per step, seconds since
/// 1970), a screenshot per measurement, each app's accessibility tree, and
/// SpringBoard's elements that name PiP.
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

    @MainActor
    private func describe(_ element: XCUIElement, _ name: String) -> String {
        guard element.exists else { return "\(name)=none" }
        return "\(name)=[\(fmt(element.frame))]"
    }

    // MARK: Finding the window

    /// The PiP window: the bounding box, in points, of the screen's magenta
    /// pixels, and how much of that box is magenta (a lone window fills nearly
    /// all of it; anything else magenta on screen would lower it). Nil when
    /// fewer than 400 points' worth are found.
    @MainActor
    private func findPiP(_ shot: XCUIScreenshot) -> (rect: CGRect, fill: Double)? {
        guard let cg = shot.image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1, count = 0
        pixels.withUnsafeBufferPointer { p in
            for y in 0..<h {
                let row = y * w * 4
                for x in 0..<w {
                    let i = row + x * 4
                    if p[i] > 200, p[i + 2] > 200, p[i + 1] < 70 {
                        count += 1
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                        if y < minY { minY = y }
                        if y > maxY { maxY = y }
                    }
                }
            }
        }
        let scale = CGFloat(w) / max(screen.width, 1)
        guard count > Int(400 * scale * scale), maxX >= minX, maxY >= minY else { return nil }
        let box = Double((maxX - minX + 1) * (maxY - minY + 1))
        let rect = CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                          width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        return (rect, Double(count) / box)
    }

    /// SpringBoard's own elements whose identifier or label names PiP.
    @MainActor
    private func springboardPiPElements() -> String {
        let query = springboard.descendants(matching: .any).matching(NSPredicate(format:
            "identifier CONTAINS[c] 'pip' OR identifier CONTAINS[c] 'picture' OR identifier CONTAINS[c] 'pegasus' OR label CONTAINS[c] 'picture in picture'"))
        let found = query.allElementsBoundByIndex.prefix(12).map { e in
            "type \(e.elementType.rawValue) id '\(e.identifier)' label '\(e.label)' [\(fmt(e.frame))]"
        }
        return found.isEmpty ? "none" : found.joined(separator: " | ")
    }

    @MainActor
    @discardableResult
    private func measure(_ tag: String) -> CGRect? {
        var shot = XCUIScreen.main.screenshot()
        var found = findPiP(shot)
        if found == nil {
            // PiP's controls dim the video for a few seconds after a touch.
            Thread.sleep(forTimeInterval: 3)
            shot = XCUIScreen.main.screenshot()
            found = findPiP(shot)
        }
        save(shot, tag)
        if let found {
            log("\(tag) pip=[\(fmt(found.rect))] fill=\(String(format: "%.3f", found.fill)) fromBottom=\(String(format: "%.1f", screen.height - found.rect.maxY))")
        } else {
            log("\(tag) pip=none")
        }
        return found?.rect
    }

    // MARK: Moving it

    private let corners: [(name: String, right: Bool, bottom: Bool)] = [
        ("topLeft", false, false), ("topRight", true, false), ("bottomLeft", false, true), ("bottomRight", true, true),
    ]

    /// A slow drag with a pause before letting go, so PiP settles in the
    /// corner it's left nearest rather than being thrown.
    @MainActor
    private func drag(in app: XCUIApplication, from: CGPoint, to: CGPoint) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: from.x, dy: from.y))
            .press(forDuration: 0.15, thenDragTo: origin.withOffset(CGVector(dx: to.x, dy: to.y)),
                   withVelocity: XCUIGestureVelocity(rawValue: 500), thenHoldForDuration: 0.3)
    }

    /// Drags the window towards each corner in turn: its centre to where a
    /// window that size would sit 16 pt from the side and 64 pt from the top
    /// or 40 pt from the bottom, then measures where the system lets it rest.
    @MainActor
    private func visitCorners(_ name: String, in app: XCUIApplication) {
        for corner in corners {
            guard let r = findPiP(XCUIScreen.main.screenshot())?.rect else {
                log("\(name) \(corner.name): no window to drag")
                continue
            }
            let target = CGPoint(x: corner.right ? screen.width - r.width / 2 - 16 : r.width / 2 + 16,
                                 y: corner.bottom ? screen.height - r.height / 2 - 40 : r.height / 2 + 64)
            log("\(name) drag \(corner.name) from (\(Int(r.midX)), \(Int(r.midY))) to (\(Int(target.x)), \(Int(target.y)))")
            drag(in: app, from: CGPoint(x: r.midX, y: r.midY), to: target)
            Thread.sleep(forTimeInterval: 2.0)
            measure("\(name)__\(corner.name)")
        }
    }

    @MainActor
    private func visit(_ name: String, bundle: String, arguments: [String] = []) {
        let app = XCUIApplication(bundleIdentifier: bundle)
        app.launchArguments = arguments
        log("\(name) launching \(bundle) \(arguments.joined(separator: " "))")
        app.launch()
        let foreground = app.wait(for: .runningForeground, timeout: 20)
        Thread.sleep(forTimeInterval: 2.5)
        log("\(name) foreground=\(foreground) \(describe(app.tabBars.firstMatch, "tabBar")) \(describe(app.toolbars.firstMatch, "toolbar")) \(describe(app.buttons["Start"], "start"))")
        write(app.debugDescription, to: "\(name)__tree.txt")
        log("\(name) springboard: \(springboardPiPElements())")
        measure("\(name)__arrive")
        visitCorners(name, in: app)
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
        save(XCUIScreen.main.screenshot(), "host__ready")
        host.buttons["startPiP"].tap()
        var started = false
        for _ in 0..<30 {
            if status.label.contains("didStart") {
                started = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        log("host started=\(started) status: \(status.label.replacingOccurrences(of: "\n", with: " / "))")
        Thread.sleep(forTimeInterval: 2)
        measure("host__started")

        // Home. If the button didn't start PiP, leaving the app may: the host
        // allows PiP to start on its own from inline playback.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
        write(springboard.debugDescription, to: "home__springboard_tree.txt")
        log("home springboard: \(springboardPiPElements())")
        measure("home__arrive")
        visitCorners("home", in: springboard)

        visit("ammy", bundle: "com.local.ammy", arguments: ["-relay_endpoint", "https://lab.invalid/now-playing"])
        for variant in ["none", "tabbar", "accessory", "toolbar", "safeareabar"] {
            visit("bars-\(variant)", bundle: "com.local.bars", arguments: ["-variant", variant])
        }
        visit("files", bundle: "com.apple.DocumentsApp")
        visit("photos", bundle: "com.apple.mobileslideshow")
        visit("settings", bundle: "com.apple.Preferences")

        // The positive control: PiP resting bottom right over Ammy, then the
        // keyboard for the URL field.
        let ammy = XCUIApplication(bundleIdentifier: "com.local.ammy")
        ammy.activate()
        _ = ammy.wait(for: .runningForeground, timeout: 10)
        Thread.sleep(forTimeInterval: 2)
        measure("ammy-keyboard__before")
        let url = ammy.textFields["URL"]
        if url.waitForExistence(timeout: 5) {
            url.tap()
            let shown = ammy.keyboards.firstMatch.waitForExistence(timeout: 5)
            Thread.sleep(forTimeInterval: 2)
            log("ammy-keyboard shown=\(shown) \(describe(ammy.keyboards.firstMatch, "keyboard")) \(describe(ammy.buttons["Start"], "start"))")
            measure("ammy-keyboard__up")
        } else {
            log("ammy-keyboard: no URL field")
        }
        log("done")
    }
}
