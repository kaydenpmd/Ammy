import XCTest

/// Drives Apple's own apps and records, for each screen worth seeing, a
/// screenshot at rest at the top, another after one swipe up, and the
/// accessibility tree (`debugDescription`) of both, in LAB_OUT. Nothing here
/// asserts: a screen that can't be reached is logged in steps.log and skipped.
///
/// Environment (passed by the workflow with the TEST_RUNNER_ prefix):
/// LAB_OUT, the output folder; LAB_APPS, every installed bundle id;
/// LAB_VISIBLE, the visible system apps; LAB_ONLY, app slugs to run (blank
/// runs all).
final class AppleAppsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor func test01Settings() { Lab.shared.settings() }
    @MainActor func test01SettingsSearch() { Lab.shared.settingsSearch() }
    @MainActor func test02Files() { Lab.shared.generic("files", "com.apple.DocumentsApp") }
    @MainActor func test03Contacts() { Lab.shared.generic("contacts", "com.apple.MobileAddressBook") }
    // Summary's own "Get Started" (a card on the page) opened Sharing in run
    // 41416881668, so it isn't a blocker here.
    @MainActor func test04Health() { Lab.shared.generic("health", "com.apple.Health", ignore: ["Get Started"]) }
    @MainActor func test05Reminders() { Lab.shared.generic("reminders", "com.apple.reminders") }
    @MainActor func test06Shortcuts() { Lab.shared.generic("shortcuts", "com.apple.shortcuts") }
    @MainActor func test07Passwords() { Lab.shared.generic("passwords", "com.apple.Passwords") }
    // Face Gallery was still a spinner at capture in run 41416881668.
    @MainActor func test08Watch() { Lab.shared.generic("watch", "com.apple.Bridge", settle: 40) }
    @MainActor func test09News() { Lab.shared.generic("news", "com.apple.news") }
    @MainActor func test10Photos() { Lab.shared.generic("photos", "com.apple.mobileslideshow") }
    @MainActor func test11Messages() { Lab.shared.generic("messages", "com.apple.MobileSMS") }
    @MainActor func test12Calendar() {
        Lab.shared.generic("calendar", "com.apple.mobilecal") { lab, app in
            lab.visit(app, "calendar", button: "Calendars", screen: "calendars")
        }
    }
    @MainActor func test13Wallet() { Lab.shared.generic("wallet", "com.apple.Passbook") }
    @MainActor func test14Fitness() { Lab.shared.generic("fitness", "com.apple.Fitness") }
    @MainActor func test15Journal() { Lab.shared.generic("journal", "com.apple.journal") }
    @MainActor func test16Freeform() { Lab.shared.generic("freeform", "com.apple.freeform") }
    @MainActor func test17Mail() { Lab.shared.generic("mail", "com.apple.mobilemail") }
    @MainActor func test18Notes() { Lab.shared.generic("notes", "com.apple.mobilenotes") }
    @MainActor func test19Clock() { Lab.shared.generic("clock", "com.apple.mobiletimer") }
    @MainActor func test20Music() { Lab.shared.generic("music", "com.apple.Music") }
    @MainActor func test21Podcasts() { Lab.shared.generic("podcasts", "com.apple.podcasts") }
    @MainActor func test22Home() { Lab.shared.generic("home", "com.apple.Home") }
    @MainActor func test30Others() { Lab.shared.others() }
}

/// One element of a snapshot, with the types of everything above it.
struct Node {
    let type: XCUIElement.ElementType
    let label: String
    let identifier: String
    let frame: CGRect
    let enabled: Bool
    let ancestors: [XCUIElement.ElementType]

    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
    func under(_ t: XCUIElement.ElementType) -> Bool { ancestors.contains(t) }
}

@MainActor
final class Lab {
    static let shared = Lab()

    let out: URL
    let installed: Set<String>?
    let visible: [String]
    let only: Set<String>
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    var screen = CGRect(x: 0, y: 0, width: 375, height: 667)
    /// In-page buttons that look like first-run buttons but are the page's own.
    var ignoredBlockers: Set<String> = []
    private var logHandle: FileHandle?

    init() {
        let env = ProcessInfo.processInfo.environment
        let dir = URL(fileURLWithPath: env["LAB_OUT"] ?? NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        out = dir
        let all = Lab.list(env, "LAB_APPS")
        installed = all.isEmpty ? nil : Set(all)
        visible = Lab.list(env, "LAB_VISIBLE")
        only = Set(Lab.list(env, "LAB_ONLY"))
    }

    static func list(_ env: [String: String], _ key: String) -> [String] {
        (env[key] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Output

    func log(_ text: String) {
        print("[lab] \(text)")
        let line = String(format: "%.3f ", Date().timeIntervalSince1970) + text + "\n"
        if logHandle == nil {
            let url = out.appendingPathComponent("steps.log")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            logHandle = try? FileHandle(forWritingTo: url)
            _ = try? logHandle?.seekToEnd()
        }
        logHandle?.write(Data(line.utf8))
    }

    func write(_ text: String, _ name: String) {
        try? Data(text.utf8).write(to: out.appendingPathComponent(name))
    }

    func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: out.appendingPathComponent(name + ".png"))
    }

    func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    func slugify(_ text: String) -> String {
        var result = ""
        var dash = false
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber {
                result.append(ch)
                dash = false
            } else if !dash && !result.isEmpty {
                result.append("-")
                dash = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "x" : result
    }

    // MARK: - Reading and touching the screen

    /// The whole tree in one snapshot, which is far quicker than a query per
    /// label.
    func nodes(_ app: XCUIApplication) -> [Node] {
        guard let root = try? app.snapshot() else { return [] }
        if root.frame.width > 0 && root.frame.height > 0 { screen = root.frame }
        var list: [Node] = []
        func walk(_ s: XCUIElementSnapshot, _ path: [XCUIElement.ElementType]) {
            list.append(Node(type: s.elementType, label: s.label, identifier: s.identifier,
                             frame: s.frame, enabled: s.isEnabled, ancestors: path))
            let below = path + [s.elementType]
            for child in s.children { walk(child, below) }
        }
        walk(root, [])
        return list
    }

    func onScreen(_ f: CGRect) -> Bool {
        f.width > 1 && f.height > 1 && f.midX > 0 && f.midX < screen.maxX && f.midY > 0 && f.midY < screen.maxY
    }

    func tap(_ app: XCUIApplication, _ point: CGPoint) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: point.x, dy: point.y))
            .tap()
    }

    /// A controlled drag rather than a fling, so a swipe moves the page by
    /// a known amount and stops.
    func drag(_ app: XCUIApplication, from: CGFloat, to: CGFloat) {
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        a.press(forDuration: 0.05, thenDragTo: b,
                withVelocity: XCUIGestureVelocity(rawValue: 900), thenHoldForDuration: 0.2)
    }

    func toTop(_ app: XCUIApplication) {
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        pause(1)
    }

    // MARK: - Capture

    /// What the task asks of every screen: at rest at the top, then after one
    /// swipe up, with the accessibility tree of each.
    func capture(_ app: XCUIApplication, _ slug: String, _ screenName: String) {
        let base = "\(slug)-\(screenName)"
        pause(1.5)
        shot("\(base)-top")
        write(app.debugDescription, "\(base).txt")
        drag(app, from: 0.75, to: 0.35)
        pause(1.5)
        shot("\(base)-scrolled")
        write(app.debugDescription, "\(base)-scrolled.txt")
        log("captured \(base)")
    }

    // MARK: - First-run screens and permission prompts

    static let alertOrder = [
        "Don’t Allow", "Don't Allow", "Not Now", "Later", "Ask App Not to Track", "Continue", "OK",
        "Allow While Using App", "Allow Once", "Allow", "Close", "Dismiss", "Done", "Cancel",
    ]
    static let screenOrder = [
        "Not Now", "Skip", "Set Up Later", "Set Up Later in Settings", "Later", "Remind Me Later",
        "Maybe Later", "No Thanks", "Ask Me Later", "Don’t Allow", "Don't Allow", "Continue",
        "Get Started", "Next", "OK", "Done", "Close", "Dismiss", "Allow",
    ]
    /// Bar buttons are a screen's own controls, except these.
    static let barAllowed: Set<String> = [
        "Not Now", "Skip", "Later", "Don’t Allow", "Don't Allow", "Continue", "Next", "Done", "Close",
        "Dismiss", "Allow",
    ]

    func pick(_ list: [Node], _ order: [String]) -> Node? {
        for label in order {
            if let n = list.first(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }) {
                return n
            }
        }
        return nil
    }

    func findBlocker(_ app: XCUIApplication) -> (point: CGPoint, what: String)? {
        // Springboard owns the permission prompts.
        let system = nodes(springboard).filter {
            $0.type == .button && $0.enabled && $0.under(.alert) && onScreen($0.frame)
        }
        if let n = pick(system, Lab.alertOrder) { return (n.center, "system alert button '\(n.label)'") }
        let all = nodes(app)
        let alerts = all.filter {
            $0.type == .button && $0.enabled && ($0.under(.alert) || $0.under(.sheet)) && onScreen($0.frame)
        }
        if let n = pick(alerts, Lab.alertOrder) { return (n.center, "alert button '\(n.label)'") }
        let buttons = all.filter { n in
            n.type == .button && n.enabled && onScreen(n.frame) && !n.under(.tabBar) && !n.under(.keyboard)
                && ((!n.under(.navigationBar) && !n.under(.toolbar)) || Lab.barAllowed.contains(n.label))
                && !ignoredBlockers.contains(n.label)
        }
        if let n = pick(buttons, Lab.screenOrder) { return (n.center, "button '\(n.label)'") }
        return nil
    }

    @discardableResult
    func clearBlockers(_ app: XCUIApplication, _ tag: String, rounds: Int = 15) -> Int {
        for round in 0..<rounds {
            guard let found = findBlocker(app) else { return round }
            shot("\(tag)-blocker-\(round)")
            log("\(tag): blocker \(round): tapping \(found.what)")
            tap(app, found.point)
            pause(2)
        }
        log("\(tag): still blocked after \(rounds) rounds")
        return rounds
    }

    // MARK: - Navigation

    func backButton(_ app: XCUIApplication) -> Node? {
        nodes(app).first {
            $0.type == .button && $0.under(.navigationBar) && onScreen($0.frame)
                && ($0.identifier == "BackButton" || $0.label == "Back")
        }
    }

    func tabs(_ app: XCUIApplication) -> [Node] {
        var seen = Set<String>()
        var list: [Node] = []
        for n in nodes(app) where n.type == .button && n.under(.tabBar) && !n.label.isEmpty && onScreen(n.frame) {
            if seen.insert(n.label).inserted { list.append(n) }
        }
        // Search last: it can raise the keyboard over the tab bar.
        return list.filter { $0.label != "Search" } + list.filter { $0.label == "Search" }
    }

    func shouldRun(_ slug: String, _ bundle: String) -> Bool {
        if !only.isEmpty && !only.contains(slug) { return false }
        if let installed, !installed.contains(bundle) {
            log("\(slug): \(bundle) is not installed")
            return false
        }
        return true
    }

    func launch(_ slug: String, _ bundle: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: bundle)
        log("\(slug): launching \(bundle)")
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 20) {
            log("\(slug): not in the foreground after launch")
        }
        pause(3)
        return app
    }

    /// Where a root screen has a back button (Contacts' Lists, Files' Browse,
    /// Shortcuts' Shortcuts), the screen above it is the one that matters.
    func climb(_ app: XCUIApplication, _ slug: String, _ screenName: String) {
        var name = screenName
        for _ in 0..<2 {
            guard let back = backButton(app) else { return }
            log("\(slug): \(name) has a back button '\(back.label)'; going up")
            tap(app, back.center)
            pause(2)
            name += "-up"
            capture(app, slug, name)
        }
    }

    /// Launch, get past first-run screens, then capture every tab, or the
    /// root where there are none, and the screen above each.
    func generic(_ slug: String, _ bundle: String, ignore: Set<String> = [], settle: Double = 0,
                 extras: ((Lab, XCUIApplication) -> Void)? = nil) {
        guard shouldRun(slug, bundle) else { return }
        ignoredBlockers = ignore
        defer { ignoredBlockers = [] }
        let app = launch(slug, bundle)
        clearBlockers(app, slug)
        let tabList = tabs(app)
        log("\(slug): tabs \(tabList.map { $0.label })")
        if tabList.isEmpty {
            waitForSpinners(app, slug, settle)
            capture(app, slug, "root")
            climb(app, slug, "root")
        } else {
            for tab in tabList {
                // A scrolled page can shrink the tab bar; bring it back first.
                toTop(app)
                guard let current = tabs(app).first(where: { $0.label == tab.label }) else {
                    log("\(slug): tab '\(tab.label)' is gone")
                    continue
                }
                tap(app, current.center)
                pause(2)
                let name = "tab-" + slugify(tab.label)
                clearBlockers(app, "\(slug)-\(name)")
                waitForSpinners(app, "\(slug)-\(name)", settle)
                capture(app, slug, name)
                climb(app, slug, name)
            }
        }
        extras?(self, app)
        app.terminate()
    }

    /// Waits, up to `seconds`, for every on-screen activity indicator to go.
    func waitForSpinners(_ app: XCUIApplication, _ tag: String, _ seconds: Double) {
        guard seconds > 0 else { return }
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            let busy = nodes(app).contains { $0.type == .activityIndicator && onScreen($0.frame) }
            if !busy {
                log("\(tag): settled after \(Int(Date().timeIntervalSince(start))) s")
                return
            }
            pause(1)
        }
        log("\(tag): still loading after \(Int(seconds)) s")
    }

    /// Opens a sheet or page from a button on the current screen, captures
    /// it, and closes it.
    func visit(_ app: XCUIApplication, _ slug: String, button label: String, screen name: String) {
        guard let n = nodes(app).first(where: { $0.type == .button && $0.label == label && onScreen($0.frame) }) else {
            log("\(slug): no '\(label)' button")
            return
        }
        tap(app, n.center)
        pause(2)
        capture(app, slug, name)
        if let done = nodes(app).first(where: { $0.type == .button && ($0.label == "Done" || $0.label == "Close") }) {
            tap(app, done.center)
            pause(1.5)
        }
    }

    static let known: Set<String> = [
        "com.apple.Preferences", "com.apple.DocumentsApp", "com.apple.MobileAddressBook", "com.apple.Health",
        "com.apple.reminders", "com.apple.shortcuts", "com.apple.Passwords", "com.apple.Bridge",
        "com.apple.news", "com.apple.mobileslideshow", "com.apple.MobileSMS", "com.apple.mobilecal",
        "com.apple.Passbook", "com.apple.Fitness", "com.apple.journal", "com.apple.freeform",
        "com.apple.mobilemail", "com.apple.mobilenotes", "com.apple.mobiletimer", "com.apple.Music",
        "com.apple.podcasts", "com.apple.Home",
    ]

    /// Any other visible Apple app, the same way.
    func others() {
        let list = visible.filter {
            $0.hasPrefix("com.apple.") && !Lab.known.contains($0) && $0 != "com.apple.springboard"
        }
        log("others: \(list)")
        for bundle in list.prefix(12) {
            let last = String(bundle.split(separator: ".").last ?? "")
            generic("other-" + slugify(last), bundle)
        }
    }

    // MARK: - Settings

    /// Pages under Settings, by the labels of the rows that lead to them.
    /// Any whose first row isn't at the top level is skipped.
    static let settingsPaths: [[String]] = [
        ["General"],
        ["General", "About"],
        ["General", "Keyboard"],
        ["General", "Language & Region"],
        ["General", "Date & Time"],
        ["General", "AutoFill & Passwords"],
        ["General", "Fonts"],
        ["Accessibility"],
        ["Accessibility", "Display & Text Size"],
        ["Accessibility", "VoiceOver"],
        ["Accessibility", "Motion"],
        ["Privacy & Security"],
        ["Privacy & Security", "Location Services"],
        ["Developer"],
        ["Search"],
        ["Display & Brightness"],
        ["Camera"],
        ["Apps"],
        ["Apps", "Safari"],
        ["Notifications"],
        ["Home Screen & App Library"],
        ["Game Center"],
        ["Siri"],
        ["Wallpaper"],
        ["StandBy"],
        ["Control Center"],
        ["Screen Time"],
        ["Battery"],
        ["Sounds & Haptics"],
        ["Focus"],
        ["Emergency SOS"],
        ["Wallet & Apple Pay"],
        ["Action Button"],
        ["Touch ID & Passcode"],
        ["Face ID & Passcode"],
    ]

    func goRoot(_ app: XCUIApplication) {
        for _ in 0..<6 {
            guard let back = backButton(app) else { return }
            tap(app, back.center)
            pause(1.2)
        }
        log("goRoot: still not at the root after six backs")
    }

    /// Every label at the top level, scrolled through once.
    func inventory(_ app: XCUIApplication) -> [String] {
        var seen: [String] = []
        for step in 0..<8 {
            for n in nodes(app) where !n.under(.navigationBar) && !n.label.isEmpty
                && (n.type == .staticText || n.type == .button || n.type == .cell) {
                if !seen.contains(n.label) { seen.append(n.label) }
            }
            if step < 7 {
                drag(app, from: 0.8, to: 0.3)
                pause(0.8)
            }
        }
        toTop(app)
        return seen
    }

    func findRow(_ app: XCUIApplication, _ label: String) -> Node? {
        let all = nodes(app)
        let matches = all.filter { n in
            n.label == label && (n.type == .cell || n.type == .button || n.type == .staticText)
                && !n.under(.navigationBar) && !n.under(.tabBar) && !n.under(.toolbar) && !n.under(.searchField)
                && n.frame.minY > 90 && n.frame.maxY < screen.maxY - 70 && n.frame.height > 1
        }
        return matches.first { $0.type == .cell } ?? matches.first { $0.type == .button } ?? matches.first
    }

    func open(_ app: XCUIApplication, _ label: String) -> Bool {
        for attempt in 0..<10 {
            if let row = findRow(app, label) {
                tap(app, row.center)
                pause(2)
                return true
            }
            if attempt < 9 {
                drag(app, from: 0.75, to: 0.4)
                pause(0.8)
            }
        }
        return false
    }

    func settings() {
        let slug = "settings"
        let bundle = "com.apple.Preferences"
        guard shouldRun(slug, bundle) else { return }
        let app = launch(slug, bundle)
        goRoot(app)
        clearBlockers(app, slug, rounds: 3)
        capture(app, slug, "root")
        toTop(app)
        let rows = inventory(app)
        write(rows.joined(separator: "\n"), "settings-root-rows.txt")
        // If the inventory missed even General, it can't be trusted to skip.
        let filter = rows.contains("General")
        var missing: Set<String> = []
        for path in Lab.settingsPaths {
            let title = path.joined(separator: " > ")
            if (filter && !rows.contains(path[0])) || missing.contains(path[0]) {
                log("settings: skipping \(title): no '\(path[0])' row")
                continue
            }
            goRoot(app)
            toTop(app)
            var reached = true
            for (i, label) in path.enumerated() {
                if !open(app, label) {
                    log("settings: couldn't find '\(label)' for \(title)")
                    if i == 0 { missing.insert(label) }
                    reached = false
                    break
                }
            }
            if reached { capture(app, slug, path.map { slugify($0) }.joined(separator: "-")) }
        }
        app.terminate()
    }

    /// A short drag held still at the end, so the list moves by about the
    /// drag and doesn't fling (the general drag flung the top level about
    /// 670 pt for 267, past Search and Home Screen & App Library).
    func nudge(_ app: XCUIApplication, from: CGFloat, to: CGFloat) {
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        a.press(forDuration: 0.3, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 1.0)
        pause(1)
    }

    /// Settings > Search alone: the page the owner compared against, an
    /// inline title over section headers. At the top level its row sits
    /// behind the floating search field, so this nudges the list until the
    /// row is clear and taps it by its identifier.
    func settingsSearch() {
        let slug = "settings-search"
        let bundle = "com.apple.Preferences"
        guard shouldRun(slug, bundle) else { return }
        let app = launch(slug, bundle)
        goRoot(app)
        toTop(app)
        var reached = false
        for attempt in 0..<12 {
            guard let row = nodes(app).first(where: { $0.identifier == "com.apple.settings.search" }) else {
                log("\(slug): no row with identifier com.apple.settings.search")
                break
            }
            let f = row.frame
            log("\(slug): attempt \(attempt), row at y=\(Int(f.minY))")
            if f.minY > 110 && f.maxY < screen.maxY - 100 {
                tap(app, row.center)
                pause(2)
                reached = true
                break
            }
            if f.minY > 110 {
                nudge(app, from: 0.62, to: 0.52)
            } else {
                nudge(app, from: 0.45, to: 0.55)
            }
        }
        if reached {
            capture(app, "settings", "search")
        } else {
            log("\(slug): couldn't reach Search")
        }
        app.terminate()
    }
}
