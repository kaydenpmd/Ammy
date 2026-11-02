import ObjectiveC
import QuartzCore
import UIKit

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
        emit([
            "k": "start", "tag": tag, "wall": Date().timeIntervalSince1970,
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
            d["trk"] = s.isTracking
            d["drg"] = s.isDragging
            d["dec"] = s.isDecelerating
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
        if (reversal || unattended) && stacksLogged < 600 {
            d["st"] = stack()
            d["why"] = reversal ? "reversal" : "unattended"
            stacksLogged += 1
        }
        if abs(delta) > 0.5 { lastDelta = delta }
        emit(d)
    }

    private func insetChanged(_ s: UIScrollView, old: UIEdgeInsets?, new: UIEdgeInsets?) {
        emit([
            "k": "ci", "f": frameIndex, "now": n(CACurrentMediaTime() - origin),
            "oldTop": n(old?.top ?? .nan), "oldBottom": n(old?.bottom ?? .nan),
            "top": n(new?.top ?? .nan), "bottom": n(new?.bottom ?? .nan),
            "oy": n(s.contentOffset.y), "st": stack(),
        ])
    }

    fileprivate func adjustedInsetChanged(_ s: UIScrollView) {
        guard scroll == nil || s === scroll else { return }
        emit([
            "k": "aic", "f": frameIndex, "now": n(CACurrentMediaTime() - origin),
            "top": n(s.adjustedContentInset.top), "bottom": n(s.adjustedContentInset.bottom),
            "sat": n(s.safeAreaInsets.top), "sab": n(s.safeAreaInsets.bottom),
            "oy": n(s.contentOffset.y), "trk": s.isTracking, "st": stack(),
        ])
    }

    // MARK: Helpers

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

    private func stack() -> [String] {
        Thread.callStackSymbols.dropFirst(2).prefix(48).map { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4 else { return line }
            return String(parts[1]) + " " + parts[3...].joined(separator: " ")
        }
    }

    private func n(_ value: CGFloat) -> Any {
        value.isFinite ? (Double(value) * 100).rounded() / 100 : NSNull()
    }

    private func n(_ value: Double) -> Any {
        value.isFinite ? (value * 10000).rounded() / 10000 : NSNull()
    }

    private func emit(_ record: [String: Any]) {
        guard let handle, JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        else { return }
        handle.write(data)
        handle.write(Data([0x0A]))
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
