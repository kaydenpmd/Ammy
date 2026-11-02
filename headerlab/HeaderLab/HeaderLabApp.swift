import SwiftUI

/// Only a host for the UI tests, which drive Apple's apps rather than this one.
@main
struct HeaderLabApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Header lab. The UI tests drive Apple's apps.")
                .padding()
        }
    }
}
