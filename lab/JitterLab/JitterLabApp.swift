import SwiftUI
import UIKit

/// Ammy's main screen, with the bottom bar swapped for one variant at a time.
/// The variant comes from the `-variant` launch argument, the content from
/// `-content` ("ammy", the default, or "long"), and the probe log goes to
/// `LAB_OUT/LAB_TAG.jsonl` when both are set in the environment.
@main
struct JitterLabApp: App {
    init() {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["LAB_OUT"], let tag = env["LAB_TAG"] {
            Probe.shared.start(directory: dir, tag: tag)
        }
    }

    var body: some Scene {
        WindowGroup {
            LabRoot()
        }
    }
}

enum Lab {
    static var variant: String { UserDefaults.standard.string(forKey: "variant") ?? "ammy" }
    static var content: String { UserDefaults.standard.string(forKey: "content") ?? "ammy" }
}

struct LabRoot: View {
    private let variant = Lab.variant
    @State private var bottomSafeArea: CGFloat = 0
    @State private var barHeight: CGFloat = 0

    var body: some View {
        Group {
            switch variant {
            case "stackMargins":
                // The bar on the stack (UIKit's eager inset path survives),
                // with the scroll room it no longer passes down given back
                // as content margins.
                NavigationStack {
                    LabForm(variant: variant)
                        .navigationTitle("Ammy")
                        .contentMargins(.bottom, barHeight, for: .scrollContent)
                        .contentMargins(.bottom, barHeight, for: .scrollIndicators)
                }
                .safeAreaBar(edge: .bottom) {
                    AmmyBar(bottomSafeArea: bottomSafeArea)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                }
            case "onStack":
                NavigationStack {
                    LabForm(variant: variant).navigationTitle("Ammy")
                }
                .safeAreaBar(edge: .bottom) { AmmyBar(bottomSafeArea: bottomSafeArea) }
            case "insetOnStack":
                NavigationStack {
                    LabForm(variant: variant).navigationTitle("Ammy")
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { AmmyBar(bottomSafeArea: bottomSafeArea) }
            default:
                NavigationStack {
                    BarHost(variant: variant, bottomSafeArea: bottomSafeArea)
                }
            }
        }
        // As Ammy measures it: outside the bar, so it reads what the window
        // reserves (0 on a home-button phone).
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomSafeArea = $0 }
    }
}

/// The Form with its title, and the variant's bottom content.
struct BarHost: View {
    let variant: String
    let bottomSafeArea: CGFloat

    var body: some View {
        let titled = LabForm(variant: variant).navigationTitle("Ammy")
        switch variant {
        case "none":
            titled
        case "inset":
            titled.safeAreaInset(edge: .bottom, spacing: 0) { AmmyBar(bottomSafeArea: bottomSafeArea) }
        case "build39":
            titled.safeAreaInset(edge: .bottom, spacing: 0) { Build39Bar() }
        case "tall":
            titled.safeAreaBar(edge: .bottom) { AmmyBar(bottomSafeArea: bottomSafeArea, top: 72) }
        case "thin":
            titled.safeAreaBar(edge: .bottom) { Color.clear.frame(height: 1) }
        case "zero":
            titled.safeAreaBar(edge: .bottom) { Color.clear.frame(height: 0) }
        case "clear87":
            titled.safeAreaBar(edge: .bottom) { Color.clear.frame(height: 87) }
        case "toolbar":
            titled.toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                    } label: {
                        Text("Start")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
        case "toolbarPlain":
            titled.toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("Start") {}
                }
            }
        case "toolbarFlexA":
            titled.toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                    } label: {
                        Text("Start")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonSizing(.flexible)
                    .controlSize(.large)
                }
            }
        case "toolbarFlexB":
            titled.toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                    } label: {
                        Text("Start")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonSizing(.flexible)
                    .controlSize(.large)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        case "insetEdge":
            // safeAreaInset keeps UIKit's eager inset path; UIKit's own
            // interaction for custom bars asks for the edge effect behind it.
            titled.safeAreaInset(edge: .bottom, spacing: 0) {
                AmmyBar(bottomSafeArea: bottomSafeArea)
                    .background { ScrollEdgeAnchor(edge: .bottom) }
            }
        case "insetEdgeOver":
            titled.safeAreaInset(edge: .bottom, spacing: 0) {
                AmmyBar(bottomSafeArea: bottomSafeArea)
                    .overlay { ScrollEdgeAnchor(edge: .bottom).allowsHitTesting(false) }
            }
        case "margins":
            titled
                .contentMargins(.bottom, 87, for: .scrollContent)
                .overlay(alignment: .bottom) { AmmyBar(bottomSafeArea: bottomSafeArea) }
        case "padding":
            titled
                .safeAreaPadding(.bottom, 87)
                .overlay(alignment: .bottom) {
                    AmmyBar(bottomSafeArea: bottomSafeArea)
                        .ignoresSafeArea(.container, edges: .bottom)
                }
        case "hard":
            titled
                .scrollEdgeEffectStyle(.hard, for: .bottom)
                .safeAreaBar(edge: .bottom) { AmmyBar(bottomSafeArea: bottomSafeArea) }
        case "noEffect":
            titled
                .scrollEdgeEffectHidden(true, for: .bottom)
                .safeAreaBar(edge: .bottom) { AmmyBar(bottomSafeArea: bottomSafeArea) }
        default:
            // "ammy", "list" and "scroll": Ammy's own bar.
            titled.safeAreaBar(edge: .bottom) { AmmyBar(bottomSafeArea: bottomSafeArea) }
        }
    }
}

/// Ammy's sections at Ammy's sizes, as a Form (or a List, or a plain
/// ScrollView for the "scroll" variant).
struct LabForm: View {
    let variant: String
    @State private var url = ""
    @State private var key = ""

    private var long: Bool { Lab.content == "long" }

    var body: some View {
        switch variant {
        case "scroll":
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(0..<(long ? 14 : 5), id: \.self) { i in
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            .frame(height: i == 0 ? 85 : 110)
                    }
                }
                .padding(.horizontal, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        case "list":
            List { sections }
                .listStyle(.insetGrouped)
        default:
            Form { sections }
        }
    }

    @ViewBuilder private var sections: some View {
        Section("Now Playing") {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 57, height: 57)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not Playing").font(.headline)
                    Text("Artist").font(.body).hidden()
                }
            }
            .padding(.horizontal, -6)
            .padding(.vertical, -1)
        }

        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                TextField("Required", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Key")
                SecureField("Optional", text: $key)
            }
        } header: {
            Text("Endpoint")
        } footer: {
            Text("Ammy sends your now-playing details to this address. "
                 + "If you set a key, it's sent as a header.")
        }

        Section("Status") {
            LabeledContent("Endpoint", value: "Disconnected")
            LabeledContent("Version", value: variant)
        }

        Section {
            NavigationLink("History") {
                Text("History")
            }
        }

        if long {
            ForEach(0..<10, id: \.self) { i in
                Section("Extra \(i)") {
                    Text("Row A")
                    Text("Row B")
                }
            }
        }
    }
}

/// Ammy's bar as it is today (build 145): one glass prominent button in a
/// GlassEffectContainer, 16 pt above, 21 pt from the screen's bottom edge and
/// sides.
struct AmmyBar: View {
    var bottomSafeArea: CGFloat
    var top: CGFloat = 16
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                } label: {
                    Text("Start")
                        .fontWeight(.medium)
                        .contentTransition(.opacity)
                }
                .buttonStyle(.glassProminent)
                .glassEffectID("primary", in: glass)
                .controlSize(.large)
                .buttonSizing(.flexible)
            }
        }
        .padding(.top, top)
        .padding(.bottom, 21 - bottomSafeArea)
        .padding(.horizontal, 21)
    }
}

/// Build 39's bar (d6516a6), the first build with the jitter: safeAreaInset,
/// a divider, a bordered prominent button and the bar material.
struct Build39Bar: View {
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Button("Start") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.vertical, 12)
        }
        .background(.bar)
    }
}
