import SwiftUI

// bar-width-lab only, never merged. One kind of bottom element per launch (`-variant`), built only from SwiftUI's standard parts, over a flat mid-grey so the glass's outline shows in light and dark: where does iOS put each, and how wide is it? The UI tests photograph each variant and Apple's own apps on several screen sizes.
//
//   tab5           a TabView with five tabs (Phone, Music)
//   tab4search     four tabs and a search tab (the Apple Store app)
//   tab3           three tabs (Translate)
//   tab2           two tabs
//   accessory      five tabs and a tabViewBottomAccessory (Music's mini player)
//   toolbar2       a bottom toolbar with a button at each end (Weather)
//   toolbar1       a bottom toolbar with one text button
//   toolbarsearch  a bottom toolbar holding the search field (Settings)

@main
struct WidthsApp: App {
    var body: some Scene {
        WindowGroup { Variant() }
    }
}

private let grey = Color(white: 0.5)

private struct Page: View {
    let title: String
    var body: some View {
        grey.ignoresSafeArea()
            .overlay(Text(title).font(.largeTitle.bold()).foregroundStyle(.white))
    }
}

struct Variant: View {
    @State private var query = ""
    private var name: String { UserDefaults.standard.string(forKey: "variant") ?? "tab5" }

    var body: some View {
        switch name {
        case "tab4search":
            TabView {
                Tab("Home", systemImage: "house.fill") { Page(title: "tab4search") }
                Tab("New", systemImage: "square.grid.2x2.fill") { Page(title: "New") }
                Tab("Radio", systemImage: "dot.radiowaves.left.and.right") { Page(title: "Radio") }
                Tab("Library", systemImage: "music.note.list") { Page(title: "Library") }
                Tab(role: .search) { Page(title: "Search") }
            }
        case "tab3":
            TabView {
                Tab("Translate", systemImage: "translate") { Page(title: "tab3") }
                Tab("Camera", systemImage: "camera.fill") { Page(title: "Camera") }
                Tab("Conversation", systemImage: "person.2.fill") { Page(title: "Conversation") }
            }
        case "tab2":
            TabView {
                Tab("Home", systemImage: "house.fill") { Page(title: "tab2") }
                Tab("Library", systemImage: "music.note.list") { Page(title: "Library") }
            }
        case "accessory":
            TabView {
                Tab("Home", systemImage: "house.fill") { Page(title: "accessory") }
                Tab("New", systemImage: "square.grid.2x2.fill") { Page(title: "New") }
                Tab("Radio", systemImage: "dot.radiowaves.left.and.right") { Page(title: "Radio") }
                Tab("Library", systemImage: "music.note.list") { Page(title: "Library") }
                Tab("Search", systemImage: "magnifyingglass") { Page(title: "Search") }
            }
            .tabViewBottomAccessory {
                HStack {
                    RoundedRectangle(cornerRadius: 6).fill(.secondary).frame(width: 32, height: 32)
                    Text("Now Playing")
                    Spacer()
                    Image(systemName: "play.fill")
                    Image(systemName: "forward.fill")
                }
                .padding(.horizontal)
            }
        case "toolbar2":
            NavigationStack {
                Page(title: "toolbar2")
                    .toolbar {
                        ToolbarItem(placement: .bottomBar) {
                            Button("Map", systemImage: "map") {}
                        }
                        ToolbarSpacer(.flexible, placement: .bottomBar)
                        ToolbarItem(placement: .bottomBar) {
                            Button("List", systemImage: "list.bullet") {}
                        }
                    }
            }
        case "toolbar1":
            NavigationStack {
                Page(title: "toolbar1")
                    .toolbar {
                        ToolbarItem(placement: .bottomBar) {
                            Button("Start") {}
                        }
                    }
            }
        case "toolbarsearch":
            NavigationStack {
                Page(title: "toolbarsearch")
                    .searchable(text: $query)
                    .toolbar {
                        DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    }
            }
        default:
            TabView {
                Tab("Home", systemImage: "house.fill") { Page(title: "tab5") }
                Tab("New", systemImage: "square.grid.2x2.fill") { Page(title: "New") }
                Tab("Radio", systemImage: "dot.radiowaves.left.and.right") { Page(title: "Radio") }
                Tab("Library", systemImage: "music.note.list") { Page(title: "Library") }
                Tab("Search", systemImage: "magnifyingglass") { Page(title: "Search") }
            }
        }
    }
}
