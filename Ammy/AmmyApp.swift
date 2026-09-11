import SwiftUI
import UIKit

extension Bundle {
    /// e.g. "1.0 (47)". The build number is the CI run that produced the IPA,
    /// so this is the quickest way to tell whether the phone is actually
    /// running the build you just pushed — the artifact is named to match.
    var displayVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// What the app should do once it has started, based on how it was launched.
enum BounceTarget {
    case stay        // opened by tapping the icon — the person wants the UI
    case music       // reopen Apple Music
    case home        // drop to the Home Screen

    init(url: URL) {
        // ammy://music  → host is "music"
        switch url.host?.lowercased() {
        case "music": self = .music
        case "background", "home": self = .home
        default: self = .stay
        }
    }
}

@main
struct AmmyApp: App {
    @StateObject private var controller = PresenceController()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(controller)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var controller: PresenceController
    @State private var running = false
    @State private var bounce: BounceTarget = .stay
    @State private var didAutoStart = false

    /// Set to the address Ammy *would* use when the typed one has no scheme.
    /// Non-nil puts the confirmation in front of the person rather than editing
    /// their text behind their back.
    @State private var schemeToConfirm: String?

    /// A key is optional — Ammy will happily post to something that doesn't ask
    /// for one — so only the address is required before starting.
    private var canAutoStart: Bool {
        !controller.endpoint.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // "Endpoint", not "Relay": a relay forwards what it receives,
                // and nothing here requires that. Ammy posts JSON to an address;
                // whether that address passes it on, renders it, or files it
                // away is none of the app's business. The same reasoning keeps
                // the relay's /now-playing path out of the placeholder — that is
                // one receiver's convention, not a rule of the app.
                //
                // Labels persist where placeholders vanish, so the row names
                // live on the left and the value column carries only whether the
                // field must be filled in.
                Section {
                    LabeledContent("URL") {
                        TextField("Required", text: $controller.endpoint)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    LabeledContent("Key") {
                        SecureField("Optional", text: $controller.key)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Endpoint")
                } footer: {
                    Text("Ammy sends your now-playing details to this address. "
                         + "If you set a key, it's sent as a header.")
                }

                Section("Status") {
                    LabeledContent("Link", value: controller.linkStatus)
                    LabeledContent("Now playing", value: controller.lastPushed)
                    LabeledContent("Media access",
                                   value: controller.monitor.authorized ? "Granted" : "Not granted")
                    LabeledContent("Version", value: Bundle.main.displayVersion)
                }

                Section {
                    Button(running ? "Stop" : "Start") {
                        if running {
                            Task {
                                await controller.stop()
                                didAutoStart = true   // don't immediately restart
                                running = false
                            }
                            return
                        }

                        // Only ever asked once per address: start() writes the
                        // resolved URL back, so the stored value has a scheme
                        // from then on and this never fires again for it.
                        if PresenceRelay.needsScheme(controller.endpoint),
                           let resolved = PresenceRelay.normalised(controller.endpoint) {
                            schemeToConfirm = resolved.absoluteString
                        } else {
                            Task { await start() }
                        }
                    }
                    .disabled(!canAutoStart)
                }

                Section("Shortcuts") {
                    Text("ammy://music")
                        .font(.system(.footnote, design: .monospaced))
                    Text("Starts, then reopens Apple Music.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("ammy://background")
                        .font(.system(.footnote, design: .monospaced))
                    Text("Starts, then returns to the Home Screen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section {
                    Text("Your PC must be awake with the Discord desktop app running. "
                         + "Presence clears automatically after 90 seconds of silence.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ammy")
            .alert("Add https://?", isPresented: Binding(
                get: { schemeToConfirm != nil },
                set: { if !$0 { schemeToConfirm = nil } }
            ), presenting: schemeToConfirm) { resolved in
                Button("Use https://") {
                    controller.endpoint = resolved
                    schemeToConfirm = nil
                    Task { await start() }
                }
                // "Ignore", not "Cancel": in iOS, Cancel usually means discard
                // what you did, which here reads as though it might throw away
                // the address just typed. This only declines the suggestion.
                //
                // The .cancel *role* stays regardless of the label — it sets the
                // button's placement and weight, answers the Escape key on a
                // hardware keyboard, and marks this as the dismissive action for
                // accessibility. (It does not add a swipe or tap-outside gesture:
                // alerts are strictly modal. That is sheets.)
                Button("Ignore", role: .cancel) { schemeToConfirm = nil }
            } message: { resolved in
                Text("Ammy will send to \(resolved). Almost every endpoint needs "
                     + "https, and iOS blocks plain http.")
            }
        }
        .task {
            await autoStartIfPossible()
        }
        .onOpenURL { url in
            bounce = BounceTarget(url: url)
            Task {
                // The URL can arrive either before or after .task runs, so
                // handle both orderings.
                if running {
                    await performBounce(justStarted: false)
                } else {
                    await autoStartIfPossible()
                }
            }
        }
    }

    @MainActor
    private func start() async {
        await controller.start()
        running = true
        await performBounce(justStarted: true)
    }

    @MainActor
    private func autoStartIfPossible() async {
        // Deliberately does not prompt. An automation launching Ammy must not
        // meet a modal it cannot answer, and by the time autostart matters the
        // stored address has already been resolved by an interactive start.
        guard !didAutoStart, !running, canAutoStart else { return }
        didAutoStart = true
        await start()
    }

    @MainActor
    private func performBounce(justStarted: Bool) async {
        guard case let target = bounce, target != .stay else { return }

        // Only wait when we've just started: the audio session needs a moment
        // to establish, and leaving too early can get the app suspended before
        // KeepAlive holds it. If it was already running there's nothing to wait
        // for, so bounce immediately and keep the interruption as short as
        // possible — this is the common case for a scheduled automation.
        if justStarted {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }

        switch target {
        case .music:
            if let url = URL(string: "music://") {
                await UIApplication.shared.open(url)
            }
        case .home:
            // Private API — equivalent to pressing Home. Fine for a sideloaded
            // build, may stop working on a future iOS. Failure is harmless:
            // the app simply stays in the foreground.
            UIApplication.shared.perform(Selector(("suspend")))
        case .stay:
            break
        }

        bounce = .stay
    }
}

extension BounceTarget: Equatable {}
