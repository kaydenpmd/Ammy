import SwiftUI
import UIKit

// pip-lab only, never merged: one kind of bottom bar per launch, picked by
// `-variant`, to see which ones the Picture in Picture window keeps clear of.
// Run 44280673989 found PiP rests 10 pt above a tab bar, the tab view's
// bottom accessory and a bottom toolbar, and ignores a safeAreaBar. The
// variants after the first five ask why.
//   none           a large-title list with nothing at the bottom
//   tabbar         the same list in a TabView: the system tab bar
//   accessory      the TabView with a bottom accessory, as Music's mini player
//   toolbar        the list with a bottom toolbar (UIToolbar underneath)
//   safeareabar    a full-width glass button in a safeAreaBar on the stack,
//                  as Ammy's bar is
//   addlsafe       no bar: the window's root view controller given 80 pt of
//                  additional bottom safe area, as a UIKit bar would add
//   tabbar-hidden  the TabView with its tab bar hidden
//   toolbar-hidden bottom toolbar items with the toolbar hidden
//   toolbar-wide   the button as Ammy draws it, full width, in a bottom toolbar
//   safeareainset  the button in a safeAreaInset instead of a safeAreaBar
//   uikit-edge     UIKit: the button in a plain view at the bottom with a
//                  UIScrollEdgeElementContainerInteraction for the table
//   uikit-toolbar  UIKit: a navigation controller's toolbar holding the button
//                  as a full-width custom view

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

struct Tabs<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        TabView {
            Tab("One", systemImage: "music.note") { NavigationStack { content() } }
            Tab("Two", systemImage: "square.stack") { NavigationStack { content() } }
            Tab("Three", systemImage: "magnifyingglass") { NavigationStack { content() } }
        }
    }
}

/// Ammy's button: Start, full width, prominent glass, large.
struct StartButton: View {
    var body: some View {
        Button {} label: {
            Text("Start").fontWeight(.medium)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .buttonSizing(.flexible)
    }
}

/// Gives the window's root view controller extra bottom safe area once it's
/// in a window.
struct RootInset: UIViewRepresentable {
    let bottom: CGFloat
    func makeUIView(context: Context) -> InsetView { InsetView(bottom: bottom) }
    func updateUIView(_ view: InsetView, context: Context) {}

    final class InsetView: UIView {
        let bottom: CGFloat
        init(bottom: CGFloat) {
            self.bottom = bottom
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("not used") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let root = window?.rootViewController else { return }
            root.additionalSafeAreaInsets.bottom = bottom
            print("[bars] root \(type(of: root)) additionalSafeAreaInsets.bottom = \(bottom)")
        }
    }
}

struct Root: View {
    let variant: String

    var body: some View {
        switch variant {
        case "tabbar":
            Tabs { Rows() }
        case "accessory":
            Tabs { Rows() }
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
                    StartButton()
                        .padding(.top, 16)
                        .padding(.horizontal, 21)
                }
        case "addlsafe":
            NavigationStack { Rows() }
                .background(RootInset(bottom: 80).frame(width: 0, height: 0))
        case "tabbar-hidden":
            Tabs { Rows().toolbar(.hidden, for: .tabBar) }
        case "toolbar-hidden":
            NavigationStack {
                Rows()
                    .toolbar {
                        ToolbarItem(placement: .bottomBar) {
                            Button("Start") {}
                        }
                    }
                    .toolbar(.hidden, for: .bottomBar)
            }
        case "toolbar-wide":
            NavigationStack {
                Rows()
                    .toolbar {
                        ToolbarItem(placement: .bottomBar) {
                            StartButton()
                        }
                    }
            }
        case "safeareainset":
            NavigationStack { Rows() }
                .safeAreaInset(edge: .bottom) {
                    StartButton()
                        .padding(.top, 16)
                        .padding(.horizontal, 21)
                }
        case "uikit-edge":
            UIKitScreen(kind: .edge).ignoresSafeArea()
        case "uikit-toolbar":
            UIKitScreen(kind: .toolbar).ignoresSafeArea()
        default:
            NavigationStack { Rows() }
        }
    }
}

// MARK: The UIKit variants

struct UIKitScreen: UIViewControllerRepresentable {
    enum Kind { case edge, toolbar }
    let kind: Kind

    func makeUIViewController(context: Context) -> UIViewController {
        let list = ListController(kind: kind)
        let nav = UINavigationController(rootViewController: list)
        nav.navigationBar.prefersLargeTitles = true
        if kind == .toolbar {
            nav.setToolbarHidden(false, animated: false)
        }
        return nav
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

final class ListController: UITableViewController {
    let kind: UIKitScreen.Kind
    private let bar = UIView()

    init(kind: UIKitScreen.Kind) {
        self.kind = kind
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func makeButton() -> UIButton {
        var config = UIButton.Configuration.prominentGlass()
        config.title = "Start"
        config.buttonSize = .large
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bars"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        switch kind {
        case .toolbar:
            let button = makeButton()
            button.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width - 42).isActive = true
            let item = UIBarButtonItem(customView: button)
            item.hidesSharedBackground = true
            toolbarItems = [item]
        case .edge:
            // The bar goes on the navigation controller's view, over the
            // table, once there is one (viewDidAppear).
            break
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard kind == .edge, bar.superview == nil, let host = navigationController?.view else { return }
        bar.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(bar)
        let button = makeButton()
        bar.addSubview(button)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 21),
            button.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -21),
            button.topAnchor.constraint(equalTo: bar.topAnchor, constant: 16),
            button.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.scrollView = tableView
        interaction.edge = .bottom
        bar.addInteraction(interaction)
        host.layoutIfNeeded()
        tableView.contentInset.bottom = bar.bounds.height
        print("[bars] edge bar \(bar.frame)")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 30 }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = "Row \(indexPath.row + 1)"
        cell.contentConfiguration = content
        return cell
    }
}
