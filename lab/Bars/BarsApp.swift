import SwiftUI

// pip-lab only, never merged: one kind of bottom bar per launch, picked by
// `-variant`, to see which ones the Picture in Picture window keeps clear of.
//   none         a large-title list with nothing at the bottom
//   tabbar       the same list in a TabView: the system tab bar
//   accessory    the TabView with a bottom accessory, as Music's mini player
//   toolbar      the list with a bottom toolbar (UIToolbar underneath)
//   safeareabar  the list with a full-width glass button in a safeAreaBar on
//                the stack, as Ammy's bar is

@main
struct BarsApp: App {
    var body: some Scene {
        WindowGroup { Root(variant: UserDefaults.standard.string(forKey: "variant") ?? "none") }
    }
}

struct Rows: View {
    var body: some View {
        List {
            Section {
                ForEach(1...30, id: \.self) { Text("Row \($0)") }
            }
        }
        .navigationTitle("Bars")
    }
}

struct Tabs: View {
    var body: some View {
        TabView {
            Tab("One", systemImage: "music.note") { NavigationStack { Rows() } }
            Tab("Two", systemImage: "square.stack") { NavigationStack { Rows() } }
            Tab("Three", systemImage: "magnifyingglass") { NavigationStack { Rows() } }
        }
    }
}

struct Root: View {
    let variant: String

    var body: some View {
        switch variant {
        case "tabbar":
            Tabs()
        case "accessory":
            Tabs()
                .tabViewBottomAccessory {
                    Text("Accessory")
                }
        case "toolbar":
            NavigationStack {
                Rows()
                    .toolbar {
                        ToolbarItem(placement: .bottomBar) {
                            Button("Start") {}
                        }
                    }
            }
        case "safeareabar":
            NavigationStack { Rows() }
                .safeAreaBar(edge: .bottom) {
                    Button {} label: {
                        Text("Start").fontWeight(.medium)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .buttonSizing(.flexible)
                    .padding(.top, 16)
                    .padding(.horizontal, 21)
                }
        default:
            NavigationStack { Rows() }
        }
    }
}
