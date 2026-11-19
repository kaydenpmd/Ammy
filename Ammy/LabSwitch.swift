// Lab only: wide-bar-check, never merged. The bar's placement is the branch's own (the wide-bar branch's constants); this only lets the UI tests show a session without sending anything.
//
//   -labRunning YES|NO   show a session (Stop) or none (Start); either way nothing starts by itself

import Foundation

enum Lab {
    /// The tests drive this launch.
    static var active: Bool { UserDefaults.standard.object(forKey: "labRunning") != nil }
}
