import XCTest

/// Drives each variant through the same gestures. The app logs every frame
/// itself (Probe.swift); this only launches it, scrolls, and takes a
/// screenshot before and after the plain drag so each variant's look is on
/// record too.
final class JitterLabUITests: XCTestCase {
    private static let variants = [
        "none", "ammy", "inset", "build39", "tall", "thin", "zero", "clear87",
        "onStack", "toolbar", "list", "scroll", "margins", "padding", "hard", "noEffect",
    ]

    private var outDir: String {
        ProcessInfo.processInfo.environment["LAB_OUT"] ?? NSTemporaryDirectory()
    }

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func test1Slow() { sweep("slow") }
    @MainActor
    func test2Drag() { sweep("drag") }
    @MainActor
    func test3Flick() { sweep("flick") }
    @MainActor
    func test4Up() { sweep("up") }

    @MainActor
    func test5Long() {
        for variant in ["none", "ammy", "margins", "toolbar"] {
            run(variant, content: "long", gesture: "slow")
        }
    }

    @MainActor
    private func sweep(_ gesture: String) {
        for variant in Self.variants {
            run(variant, content: "ammy", gesture: gesture)
        }
    }

    @MainActor
    private func run(_ variant: String, content: String, gesture: String) {
        let tag = "\(variant)__\(content)__\(gesture)"
        XCTContext.runActivity(named: tag) { _ in
            let app = XCUIApplication()
            app.launchArguments = ["-variant", variant, "-content", content]
            app.launchEnvironment = ["LAB_OUT": outDir, "LAB_TAG": tag]
            app.launch()
            _ = app.navigationBars.firstMatch.waitForExistence(timeout: 15)
            Thread.sleep(forTimeInterval: 1.0)
            if gesture == "slow" { shot(tag + "__0") }

            let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            switch gesture {
            case "slow":
                // About a point a frame, like the crawl in the owner's recording.
                low.press(forDuration: 0.3, thenDragTo: middle,
                          withVelocity: XCUIGestureVelocity(rawValue: 150), thenHoldForDuration: 0.5)
            case "drag":
                low.press(forDuration: 0.3, thenDragTo: high,
                          withVelocity: XCUIGestureVelocity(rawValue: 600), thenHoldForDuration: 0.5)
            case "flick":
                low.press(forDuration: 0.01, thenDragTo: middle,
                          withVelocity: .fast, thenHoldForDuration: 0)
            case "hold":
                let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                from.press(forDuration: 0.05, thenDragTo: middle,
                           withVelocity: XCUIGestureVelocity(rawValue: 200), thenHoldForDuration: 1.5)
            case "up":
                low.press(forDuration: 0.05, thenDragTo: high,
                          withVelocity: XCUIGestureVelocity(rawValue: 600), thenHoldForDuration: 0.3)
                Thread.sleep(forTimeInterval: 1.5)
                high.press(forDuration: 0.05, thenDragTo: low,
                           withVelocity: XCUIGestureVelocity(rawValue: 600), thenHoldForDuration: 0.3)
            default:
                break
            }
            Thread.sleep(forTimeInterval: 2.0)
            if gesture == "slow" { shot(tag + "__1") }
            app.terminate()
        }
    }

    @MainActor
    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let url = URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png")
        do {
            try data.write(to: url)
        } catch {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
