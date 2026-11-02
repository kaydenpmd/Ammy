import SwiftUI

// Minimal reproduction: a large title over a List, with a button in a bottom
// safeAreaBar.
//
// Drag the list up slowly from the top. With "Bar on List" on (the default),
// the large title snaps shut as the drag begins and the list jumps ahead of
// the finger: 52 pt in a single frame on iOS 26.5, about 34 pt over three
// frames on iOS 27.0. With it off, the same bar is attached to the
// NavigationStack instead, and the title collapses smoothly with the finger.
// (A bottom safeAreaInset on the List also collapses smoothly, but has no
// scroll edge effect.)

@main
struct ReproApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var barOnList = true

    var body: some View {
        if barOnList {
            NavigationStack {
                list
                    .safeAreaBar(edge: .bottom) { button }
            }
        } else {
            NavigationStack {
                list
            }
            .safeAreaBar(edge: .bottom) { button }
        }
    }

    private var list: some View {
        List {
            Section {
                Toggle("Bar on List", isOn: $barOnList)
            } footer: {
                Text("On: safeAreaBar on the List (the title jumps). "
                     + "Off: the same bar on the NavigationStack (smooth).")
            }
            ForEach(0..<6) { section in
                Section("Section \(section)") {
                    ForEach(0..<3) { row in
                        Text("Row \(row)")
                    }
                }
            }
        }
        .navigationTitle("Title")
    }

    private var button: some View {
        Button {
        } label: {
            Text("Button")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}
