import SwiftUI

// The host app the UI tests need; the tests drive System Settings, not this.
@main
struct MacLabApp: App {
    var body: some Scene {
        WindowGroup { Text("Layout lab") }
    }
}
