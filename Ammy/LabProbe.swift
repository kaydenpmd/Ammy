// Lab only: keyboard-lab, never merged. header-lab-option1's per-frame probe
// (itself the jitter lab's), compiled into the real Ammy so its scrolling can
// be measured as before, plus the keyboard, the two bottom-edge readings and
// where each copy of the bar is. It runs only when the UI test sets LAB_OUT
// and LAB_TAG.

import ObjectiveC
import QuartzCore
import SwiftUI
import UIKit

/// How ContentView places the bar, from the `-labBar` launch argument:
///   fix      the keyboard-bar branch: the inset read without the keyboard
///   main     build 172 as released: one reading, the keyboard counted
///   form148  build 148's arrangement: the bar on the Form, one reading
///   ignore   the bar ignores the home indicator's inset, padded by edgeGap
enum Lab {
    static var variant: String { UserDefaults.standard.string(forKey: "labBar") ?? "fix" }
    static var content: String { "ammy" }
}

/// Logs, once per display frame, where the Form's content and the navigation
/// bar actually are, plus every contentOffset and inset change as it happens,
/// with the call stack whenever the offset reverses or moves while nobody is
/// touching it. One JSON object per line.
///
/// Records, by "k":
///   start   the run's tag, variant, OS
///   attach  the scroll view found, and its superview chain
///   f       one display frame: link timestamps, contentOffset (model and
///           presented), the content origin's y in the window (model "cy" and
///           presented "pcy"), the scroll view's frame, its insets, content
///           height, the navigation bar's bottom edge and height, and the
///           tracking/decelerating flags
///   o       a contentOffset change, with "st" (stack) on reversals and on
///           changes made while neither tracking nor decelerating
///   ci      a contentInset change, always with a stack
///   aic     adjustedContentInsetDidChange, always with a stack
///   ind     the scroll view's indicator subviews, by class, once attached
///   kb      a keyboard notification: its end frame, and the focused
///           field's frame in the window
///   bar     a copy of the bar laid out somewhere new (labFrame): which
///           copy ("stack", "page" or "form") and its frame in the window
/// Frames also carry the vertical indicator's insets ("vit", "vib"), whether
/// UIKit adjusts them ("aas"), and the indicator view itself, in the window
/// ("viy" top, "vih" height, "via" alpha).
@MainActor
final class Probe: NSObject {
    static let shared = Probe()

    private var link: CADisplayLink?
    private weak var scroll: UIScrollView?
    private weak var navBar: UINavigationBar?
    private var handle: FileHandle?
    private var offsetObservation: NSKeyValueObservation?
    private var insetObservation: NSKeyValueObservation?
    private var frameIndex = 0
    private var lastDelta: CGFloat = 0
    private var stacksLogged = 0
    private let origin = CACurrentMediaTime()
    /// Symbolising a stack takes tens of milliseconds, which on the main
    /// thread is itself a hitch, so the main thread only grabs the return
    /// addresses and this queue names them and writes every record.
    private let writer = DispatchQueue(label: "probe.writer")

    func start(directory: String, tag: String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var path = (directory as NSString).appendingPathComponent(tag + ".jsonl")
        if !FileManager.default.createFile(atPath: path, contents: nil) {
            // Fall back to the app's own container if the host path is refused.
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            path = docs.appendingPathComponent(tag + ".jsonl").path
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        handle = FileHandle(forWritingAtPath: path)
        print("[probe] writing \(path)")
        UIScrollView.installProbeSwizzle()
        UIWindow.installTouchSwizzle()
        observeKeyboard()
        emit([
            "k": "start", "tag": tag, "wall": Date().timeIntervalSince1970,
            "now": n(CACurrentMediaTime() - origin),
            "variant": Lab.variant, "content": Lab.content,
            "os": UIDevice.current.systemVersion,
            "scale": UIScreen.main.scale,
            "fps": UIScreen.main.maximumFramesPerSecond,
        ])
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    // MARK: Per frame

    @objc private func tick(_ link: CADisplayLink) {
        frameIndex += 1
        guard let window = keyWindow else { return }
        if scroll?.window == nil { attach(in: window) }
        if navBar?.window == nil {
            navBar = all(UINavigationBar.self, in: window).first
        }
        var d: [String: Any] = [
            "k": "f", "f": frameIndex,
            "t": n(link.timestamp - origin), "tt": n(link.targetTimestamp - origin),
            "now": n(CACurrentMediaTime() - origin),
        ]
        if let s = scroll {
            let presented = s.layer.presentation() ?? s.layer
            d["oy"] = n(s.contentOffset.y)
            d["poy"] = n(presented.bounds.origin.y)
            d["cy"] = n(s.convert(CGPoint.zero, to: nil).y)
            d["pcy"] = n(presentedY(of: s.layer, localY: 0, root: window.layer))
            d["fy"] = n(s.superview?.convert(s.frame, to: nil).minY ?? .nan)
            d["fh"] = n(s.frame.height)
            d["ait"] = n(s.adjustedContentInset.top)
            d["aib"] = n(s.adjustedContentInset.bottom)
            d["cit"] = n(s.contentInset.top)
            d["cib"] = n(s.contentInset.bottom)
            d["sat"] = n(s.safeAreaInsets.top)
            d["sab"] = n(s.safeAreaInsets.bottom)
            d["ch"] = n(s.contentSize.height)
            d["vit"] = n(s.verticalScrollIndicatorInsets.top)
            d["vib"] = n(s.verticalScrollIndicatorInsets.bottom)
            d["aas"] = s.automaticallyAdjustsScrollIndicatorInsets
            if let indicator = verticalIndicator(of: s) {
                let r = indicator.convert(indicator.bounds, to: nil)
                d["viy"] = n(r.minY)
                d["vih"] = n(r.height)
                d["via"] = n(indicator.alpha)
            }
            d["trk"] = s.isTracking
            d["drg"] = s.isDragging
            d["dec"] = s.isDecelerating
            let pan = s.panGestureRecognizer
            d["pst"] = pan.state.rawValue
            if pan.state == .began || pan.state == .changed {
                d["pan"] = n(pan.location(in: nil).y)
            }
        }
        if let bar = navBar {
            d["nb"] = n(bar.convert(CGPoint(x: 0, y: bar.bounds.maxY), to: nil).y)
            d["pnb"] = n(presentedY(of: bar.layer, localY: bar.bounds.maxY, root: window.layer))
            d["nh"] = n(bar.bounds.height)
        }
        emit(d)
    }

    // MARK: Events

    private func attach(in window: UIWindow) {
        let scrolls = all(UIScrollView.self, in: window).filter { !($0 is UITextView) && $0.bounds.height > 200 }
        guard let s = scrolls.first(where: { $0 is UICollectionView })
            ?? scrolls.max(by: { $0.bounds.height < $1.bounds.height }) else { return }
        scroll = s
        var chain: [String] = []
        var view: UIView? = s
        while let current = view {
            chain.append(String(describing: type(of: current)))
            view = current.superview
        }
        emit([
            "k": "attach", "f": frameIndex, "cls": String(describing: type(of: s)), "chain": chain,
            "behavior": s.contentInsetAdjustmentBehavior.rawValue,
        ])
        emit([
            "k": "ind", "f": frameIndex,
            "views": s.subviews.map { String(describing: type(of: $0)) }.filter { $0.contains("ndicator") },
        ])
        offsetObservation = s.observe(\.contentOffset, options: [.old, .new]) { [weak self] view, change in
            let old = change.oldValue?.y, new = change.newValue?.y
            MainActor.assumeIsolated { self?.offsetChanged(view, old: old, new: new) }
        }
        insetObservation = s.observe(\.contentInset, options: [.old, .new]) { [weak self] view, change in
            let old = change.oldValue, new = change.newValue
            MainActor.assumeIsolated { self?.insetChanged(view, old: old, new: new) }
        }
    }

    private func offsetChanged(_ s: UIScrollView, old: CGFloat?, new: CGFloat?) {
        guard let new else { return }
        let delta = new - (old ?? new)
        var d: [String: Any] = [
            "k": "o", "f": frameIndex, "now": n(CACurrentMediaTime() - origin),
            "y": n(new), "d": n(delta), "trk": s.isTracking, "dec": s.isDecelerating,
        ]
        let reversal = abs(delta) > 0.5 && lastDelta != 0 && (delta > 0) != (lastDelta > 0)
        let unattended = !s.isTracking && !s.isDecelerating && abs(delta) > 0.01
        var addresses: [UInt]?
        if (reversal || unattended) && stacksLogged < 600 {
            addresses = stack()
            d["why"] = reversal ? "reversal" : "unattended"
            stacksLogged += 1
        }
        if abs(delta) > 0.5 { lastDelta = delta }
        emit(d, stack: addresses)
    }

    private func insetChanged(_ s: UIScrollView, old: UIEdgeInsets?, new: UIEdgeInsets?) {
        emit([
            "k": "ci", "f": frameIndex, "now": n(CACurrentMediaTime() - origin),
            "oldTop": n(old?.top ?? .nan), "oldBottom": n(old?.bottom ?? .nan),
            "top": n(new?.top ?? .nan), "bottom": n(new?.bottom ?? .nan),
            "oy": n(s.contentOffset.y),
        ], stack: stack())
    }

    fileprivate func adjustedInsetChanged(_ s: UIScrollView) {
        guard scroll == nil || s === scroll else { return }
        emit([
            "k": "aic", "f": frameIndex, "now": n(CACurrentMediaTime() - origin),
            "top": n(s.adjustedContentInset.top), "bottom": n(s.adjustedContentInset.bottom),
            "sat": n(s.safeAreaInsets.top), "sab": n(s.safeAreaInsets.bottom),
            "oy": n(s.contentOffset.y), "trk": s.isTracking,
        ], stack: stack())
    }

    /// A one-off record from elsewhere in the app, stamped with the frame.
    func note(_ record: [String: Any]) {
        var record = record
        record["f"] = frameIndex
        record["now"] = n(CACurrentMediaTime() - origin)
        emit(record)
    }

    fileprivate func touched(_ event: UIEvent) {
        guard event.type == .touches, let touches = event.allTouches else { return }
        for touch in touches {
            emit([
                "k": "t", "f": frameIndex, "now": n(CACurrentMediaTime() - origin),
                "ts": n(event.timestamp - origin), "y": n(touch.location(in: nil).y),
                "ph": touch.phase.rawValue,
            ])
        }
    }

    // MARK: Keyboard

    private func observeKeyboard() {
        let names: [Notification.Name] = [
            UIResponder.keyboardWillShowNotification, UIResponder.keyboardDidShowNotification,
            UIResponder.keyboardWillHideNotification, UIResponder.keyboardDidHideNotification,
            UIResponder.keyboardDidChangeFrameNotification,
        ]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                let what = note.name.rawValue
                MainActor.assumeIsolated { self?.keyboard(what, end: end) }
            }
        }
    }

    private func keyboard(_ what: String, end: CGRect?) {
        var d: [String: Any] = ["k": "kb", "f": frameIndex, "now": n(CACurrentMediaTime() - origin), "what": what]
        if let end {
            d["y"] = n(end.minY)
            d["h"] = n(end.height)
        }
        if let window = keyWindow,
           let field = all(UIView.self, in: window).first(where: { ($0 is UITextField || $0 is UITextView) && $0.isFirstResponder }) {
            let r = field.convert(field.bounds, to: nil)
            d["fy"] = n(r.minY)
            d["fh"] = n(r.height)
        }
        if let s = scroll {
            d["oy"] = n(s.contentOffset.y)
            d["aib"] = n(s.adjustedContentInset.bottom)
            d["sab"] = n(s.safeAreaInsets.bottom)
        }
        emit(d)
    }

    // MARK: Helpers

    /// UIKit's vertical scroll indicator, a private subview of the scroll view.
    private func verticalIndicator(of s: UIScrollView) -> UIView? {
        s.subviews.first { view in
            String(describing: type(of: view)).contains("ndicator") && view.bounds.height > view.bounds.width
        }
    }

    private var keyWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    private func all<T: UIView>(_ type: T.Type, in root: UIView) -> [T] {
        var found: [T] = []
        var pending: [UIView] = [root]
        while let view = pending.popLast() {
            if let match = view as? T { found.append(match) }
            pending.append(contentsOf: view.subviews.reversed())
        }
        return found
    }

    /// Where a point of a layer is on screen as rendered, from the
    /// presentation layers up to the window (transforms ignored).
    private func presentedY(of layer: CALayer, localY: CGFloat, root: CALayer) -> CGFloat {
        var y = localY
        var current: CALayer? = layer
        while let l = current, l !== root {
            let p = l.presentation() ?? l
            y = p.position.y - p.anchorPoint.y * p.bounds.height + (y - p.bounds.origin.y)
            current = l.superlayer
        }
        return y
    }

    private func stack() -> [UInt] {
        Thread.callStackReturnAddresses.dropFirst(2).prefix(48).map(\.uintValue)
    }

    private nonisolated static func symbolize(_ addresses: [UInt]) -> [String] {
        addresses.map { address in
            var info = Dl_info()
            guard let pointer = UnsafeRawPointer(bitPattern: address), dladdr(pointer, &info) != 0 else {
                return String(format: "0x%lx", address)
            }
            let image = info.dli_fname.map { (String(cString: $0) as NSString).lastPathComponent } ?? "?"
            let name = info.dli_sname.map { String(cString: $0) } ?? "?"
            let offset = info.dli_saddr.map { address &- UInt(bitPattern: $0) } ?? 0
            return "\(image) \(name) + \(offset)"
        }
    }

    private func n(_ value: CGFloat) -> Any {
        value.isFinite ? (Double(value) * 100).rounded() / 100 : NSNull()
    }

    private func n(_ value: Double) -> Any {
        value.isFinite ? (value * 10000).rounded() / 10000 : NSNull()
    }

    private func emit(_ record: [String: Any], stack: [UInt]? = nil) {
        guard let handle else { return }
        let box = RecordBox(record: record)
        writer.async {
            var record = box.record
            if let stack { record["st"] = Probe.symbolize(stack) }
            guard JSONSerialization.isValidJSONObject(record),
                  let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            else { return }
            handle.write(data)
            handle.write(Data([0x0A]))
        }
    }
}

/// Carries a record to the writer queue; it holds only numbers, strings,
/// booleans, arrays of them and NSNull.
private struct RecordBox: @unchecked Sendable {
    let record: [String: Any]
}

extension UIWindow {
    @objc dynamic func lab_sendEvent(_ event: UIEvent) {
        Probe.shared.touched(event)
        // After the exchange this calls UIKit's original.
        lab_sendEvent(event)
    }

    private static let labTouchSwizzle: Void = {
        guard let original = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.sendEvent(_:))),
              let replacement = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.lab_sendEvent(_:)))
        else { return }
        method_exchangeImplementations(original, replacement)
    }()

    static func installTouchSwizzle() {
        _ = labTouchSwizzle
    }
}

extension UIScrollView {
    @objc dynamic func lab_adjustedContentInsetDidChange() {
        // After the exchange this calls UIKit's original.
        lab_adjustedContentInsetDidChange()
        Probe.shared.adjustedInsetChanged(self)
    }

    private static let labSwizzle: Void = {
        guard let original = class_getInstanceMethod(UIScrollView.self, #selector(UIScrollView.adjustedContentInsetDidChange)),
              let replacement = class_getInstanceMethod(UIScrollView.self, #selector(UIScrollView.lab_adjustedContentInsetDidChange))
        else { return }
        method_exchangeImplementations(original, replacement)
    }()

    static func installProbeSwizzle() {
        _ = labSwizzle
    }
}

extension View {
    /// Lab only: the "ignore" variant's bar reaches into the home indicator's
    /// zone by ignoring it, rather than by a negative padding.
    @ViewBuilder func labIgnoreHomeIndicator(_ on: Bool) -> some View {
        if on { ignoresSafeArea(.container, edges: .bottom) } else { self }
    }

    /// Lab only: tells the probe where this copy of the bar is laid out, in
    /// the window, whenever that changes. Reads geometry, changes nothing.
    func labFrame(_ which: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
            MainActor.assumeIsolated {
                Probe.shared.note([
                    "k": "bar", "w": which,
                    "x": Double(r.minX), "y": Double(r.minY), "wd": Double(r.width), "h": Double(r.height),
                ])
            }
        }
    }
}
