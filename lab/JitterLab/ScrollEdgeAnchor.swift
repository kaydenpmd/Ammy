import SwiftUI
import UIKit

/// UIKit's interaction for custom bars that overlay a scroll view's edge
/// (UIScrollEdgeElementContainerInteraction, iOS 26), pointed at the scroll
/// view the bar sits over. SwiftUI doesn't hand out a Form's scroll view, so
/// it's found as the largest scroll view under the same ancestor.
struct ScrollEdgeAnchor: UIViewRepresentable {
    let edge: UIRectEdge

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.edge = edge
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.edge = edge
        view.attach()
    }

    final class AnchorView: UIView {
        var edge: UIRectEdge = .bottom
        private let interaction = UIScrollEdgeElementContainerInteraction()
        private var added = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            fatalError("not used")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if interaction.scrollView == nil { attach() }
        }

        func attach() {
            guard window != nil else { return }
            if !added {
                addInteraction(interaction)
                added = true
            }
            interaction.edge = edge
            if interaction.scrollView == nil, let scroll = nearestScrollView() {
                interaction.scrollView = scroll
                Probe.shared.note([
                    "k": "anchor", "found": String(describing: type(of: scroll)),
                    "frame": "\(frame)",
                ])
            }
        }

        private func nearestScrollView() -> UIScrollView? {
            var ancestor = superview
            while let current = ancestor {
                let found = scrollViews(in: current).filter { !$0.isDescendant(of: self) }
                if let best = found.max(by: { $0.bounds.height < $1.bounds.height }), best.bounds.height > 200 {
                    return best
                }
                ancestor = current.superview
            }
            return nil
        }

        private func scrollViews(in root: UIView) -> [UIScrollView] {
            var found: [UIScrollView] = []
            var pending = [root]
            while let view = pending.popLast() {
                if let scroll = view as? UIScrollView, !(scroll is UITextView) {
                    found.append(scroll)
                }
                pending.append(contentsOf: view.subviews)
            }
            return found
        }
    }
}
