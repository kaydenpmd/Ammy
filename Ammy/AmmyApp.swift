import SwiftUI

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
                // Label above a full-width field, rather than Mail's two-column
                // row. Both values here are long enough to overflow a shared
                // row, and LabeledContent's response to that is to stack them
                // anyway — so the layout would silently change shape depending
                // on how long someone's address happened to be. Doing it on
                // purpose keeps it fixed, and gives the value the whole width.
                //
                // Both rows get the same treatment even though "Optional" would
                // fit on one line: matching rows read as one thing, and the key
                // is as long as the URL in practice.
                //
                // The visible label is hidden from VoiceOver and applied to the
                // field instead, so it is announced once as a labelled control
                // rather than twice as loose text.
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("URL")
                            .accessibilityHidden(true)
                        TextField("Required", text: $controller.endpoint)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .accessibilityLabel("URL")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Key")
                            .accessibilityHidden(true)
                        SecureField("Optional", text: $controller.key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Key")
                    }
                } header: {
                    Text("Endpoint")
                } footer: {
                    Text("Ammy sends your now-playing details to this address. "
                         + "If you set a key, it's sent as a header.")
                }

                Section("Status") {
                    LabeledContent("Link", value: controller.linkStatus)
                    LabeledContent("Now Playing", value: controller.lastPushed)
                    LabeledContent("Media Access",
                                   value: controller.monitor.authorized ? "Granted" : "Not Granted")
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
                // A footer, not a Section holding a Text. Text placed in a
                // section becomes a row, and a row gets the grouped card's
                // background and insets — which makes an aside look like a
                // setting you failed to provide a control for. A footer sits
                // outside the card in the gutter and takes the footnote size
                // and secondary colour on its own, so none of that is set here.
                } footer: {
                    Text("Your PC must be awake with the Discord desktop app "
                         + "running. Presence clears automatically after 90 "
                         + "seconds of silence.")
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
    }

    @MainActor
    private func start() async {
        await controller.start()
        running = true
    }

    /// Ammy begins reporting as soon as it is launched, by any means — the
    /// icon, the app switcher, or a Shortcuts `Open App` action. That is the
    /// entire relaunch mechanism, and it is deliberately the whole of it: there
    /// is nothing to tell the app on the way in, so there is no deep link to
    /// get wrong, no scheme to register, and no second code path that only runs
    /// when an automation fires.
    ///
    /// Deliberately does not prompt. Something launching Ammy unattended must
    /// not meet a modal it cannot answer, and by the time autostart matters the
    /// stored address has already been resolved by an interactive start.
    @MainActor
    private func autoStartIfPossible() async {
        guard !didAutoStart, !running, canAutoStart else { return }
        didAutoStart = true
        await start()
    }
}
