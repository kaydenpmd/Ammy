// Lab only: wide-bar-lab, never merged. Where the bottom bar sits, picked at launch, so one build shows the bar as released beside Apple's wide bottom button placement (design library, apple/ios-bottom-bar-widths: 38 pt from each side and from the bottom, 52 pt tall).
//
//   -labSide N         the bar's distance from each side of the screen (21 as released)
//   -labBottom N       from the screen's bottom edge, with no keyboard (21 as released)
//   -labKeyboardGap N  above the keyboard's top edge (21 as released)
//   -labSize S         the buttons' control size: large (as released) or extraLarge
//   -labRunning YES    show a session without sending anything, so the bar says Stop

import SwiftUI

enum Lab {
    private static func number(_ key: String, _ released: CGFloat) -> CGFloat {
        UserDefaults.standard.object(forKey: key) == nil ? released : CGFloat(UserDefaults.standard.double(forKey: key))
    }

    static var side: CGFloat { number("labSide", 21) }
    static var bottom: CGFloat { number("labBottom", 21) }
    static var keyboardGap: CGFloat { number("labKeyboardGap", 21) }
    static var size: ControlSize { UserDefaults.standard.string(forKey: "labSize") == "extraLarge" ? .extraLarge : .large }

    /// Any lab argument at all: the tests drive this launch.
    static var active: Bool {
        ["labSide", "labBottom", "labKeyboardGap", "labSize", "labRunning"].contains { UserDefaults.standard.object(forKey: $0) != nil }
    }
}
