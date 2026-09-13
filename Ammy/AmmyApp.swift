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
    @Environment(\.scenePhase) private var scenePhase
    @State private var didAutoStart = false

    /// Set to the address Ammy *would* use when the typed one has no scheme.
    /// Non-nil puts the confirmation in front of the person rather than editing
    /// their text behind their back.
    @State private var schemeToConfirm: String?

    /// Ties the glass surfaces together so they morph into one another rather
    /// than fading. See the bar below for what the two IDs mean.
    @Namespace private var glass

    /// The fields have drifted from what is actually being sent, and there is a
    /// session for that to matter to. Both halves are the controller's to know
    /// now; the view only decides that the bar cares about the pair.
    private var isEdited: Bool { controller.isRunning && controller.configChanged }

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
                // GUESS: spacing 4 between a field's label and its value. No
                // source; it was picked to look right when these rows were
                // stacked and has never been checked against anything.
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
                    // A spinner rather than a word until the first push comes
                    // back, because until then there is no answer to show —
                    // only the wait for one.
                    LabeledContent("Endpoint") {
                        if controller.resolving {
                            ProgressView()
                        } else {
                            Text(controller.linkStatus)
                        }
                    }
                    .animation(.default, value: controller.resolving)
                    LabeledContent("Now Playing", value: controller.nowPlaying)
                    LabeledContent("Media Access",
                                   value: controller.monitor.authorized ? "Granted" : "Not Granted")
                    LabeledContent("Version", value: Bundle.main.displayVersion)
                }

            }
            .navigationTitle("Ammy")
            // safeAreaBar, not safeAreaInset. Both reserve the space — which
            // is what keeps the last row scrollable clear of the button
            // instead of permanently buried, as an overlay would — but the bar
            // also applies the scroll edge effect, so content blurs out as it
            // passes underneath. That is the whole reason no background is set
            // here: a hard fill would be doing badly what the system already
            // does properly, and it is what made the first attempt look stuck
            // on rather than floating.
            //
            // Start/Stop lives here because it is the only control on this
            // screen anyone touches twice, and the only one that used to
            // scroll out of reach. The Form is what you set up once; this is
            // what you actually do.
            .safeAreaBar(edge: .bottom) {
                // Three states, two slots.
                //
                //   idle              [ Start ]                 prominent
                //   running           [ Stop ]                  glass
                //   running + edited  [ Stop ][ Restart ]       glass + prominent
                //
                // IDs are assigned by ROLE, not by button, and that is the whole
                // trick. glassEffectID is a separate identity from SwiftUI's
                // own, so the material follows the slot even when the view
                // inside it is torn down and rebuilt — which is exactly the
                // limitation that made a plain style swap read as a hard cut.
                //
                // "primary" is Start and Restart: pressing Stop while split
                // therefore grows Restart out to full width and relabels it,
                // rather than replacing it. "secondary" is Stop alone, so it
                // melts into the primary as that expands past it.
                //
                // The one transition this cannot also smooth is Start -> Stop,
                // since those are different roles occupying the same space. They
                // cross-fade in place, which is acceptable because the label is
                // changing anyway. Trying to give Start the same ID as Stop
                // would fix that one and break the split, which matters more.
                // GUESS: 8 — the container's spacing is the *blend threshold*,
                // how close two glass surfaces must be before they merge into
                // one another. That governs behaviour mid-transition, so it
                // cannot be measured from a screenshot. Matched to the layout
                // gap below because the published examples set the two equal;
                // that is convention, not evidence. Tune by watching the split.
                GlassEffectContainer(spacing: 8) {
                    // Measured: Apple leaves 8pt between the Music/News tab bar
                    // and its detached search button — glass ends at x=566, next
                    // glass begins at x=584 in a 2x screenshot.
                    HStack(spacing: 8) {
                        if controller.isRunning {
                            Button {
                                stopSession()
                            } label: {
                                Text("Stop")
                                    .fontWeight(.medium)
                            }
                            .buttonStyle(.glass)
                            .glassEffectID("secondary", in: glass)
                            .controlSize(.large)
                            .buttonSizing(.flexible)
                        }

                        if !controller.isRunning || isEdited {
                            Button {
                                if controller.isRunning {
                                    // Restart: drop the old session first so the
                                    // new endpoint is what actually gets used.
                                    Task {
                                        await controller.stop()
                                        beginOrConfirm()
                                    }
                                } else {
                                    beginOrConfirm()
                                }
                            } label: {
                                Text(controller.isRunning ? "Restart" : "Start")
                                    .fontWeight(.medium)
                                    // The glass morphs; the word does not. Label
                                    // changes never interpolate, so this fades
                                    // the text while the pill flows underneath.
                                    .contentTransition(.opacity)
                            }
                            .buttonStyle(.glassProminent)
                            .glassEffectID("primary", in: glass)
                            .controlSize(.large)
                            .buttonSizing(.flexible)
                            .disabled(!canAutoStart)
                        }
                    }
                }
                // .animation(value:) rather than withAnimation, because one of
                // the triggers is a TextField binding writing straight to the
                // controller — there is no call site here to wrap.
                // 0.4s measured off Music's tab bar collapsing into its search
                // field — 24 frames at 60fps. That transition is far larger than
                // this one (five elements to two, with the widths changing
                // completely), so treat it as an upper bound rather than a
                // target; if this reads slow, shorten it.
                // Duration measured; bounce is not.
                // GUESS: bounce 0.15 — the reference settles too smoothly to read
                // overshoot off three-frame samples, so this is picked to be
                // slightly springy without wobbling. Raise it for more rubber.
                .animation(.spring(duration: 0.4, bounce: 0.15), value: controller.isRunning)
                .animation(.spring(duration: 0.4, bounce: 0.15), value: isEdited)
                .padding(.vertical)
                .padding(.horizontal, 21)
            }
            .alert("Use HTTPS?", isPresented: Binding(
                get: { schemeToConfirm != nil },
                set: { if !$0 { schemeToConfirm = nil } }
            ), presenting: schemeToConfirm) { resolved in
                Button("Use HTTPS") {
                    controller.endpoint = resolved
                    schemeToConfirm = nil
                    Task { await start() }
                }
                // Not dead code on a device with no keyboard. This is what marks
                // the preferred action, and on iOS 26 the preferred action in an
                // alert renders as a filled button rather than plain blue text.
                // Without it the system emphasises the .cancel button instead,
                // which is backwards here: declining the suggestion would be the
                // one that looks like the thing to press.
                //
                // ButtonRole.confirm does NOT do this — it exists in iOS 26 but
                // does not produce the filled treatment.
                .keyboardShortcut(.defaultAction)
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
                // HTTPS and HTTP are capitalised as prose; the scheme inside
                // the URL stays lowercase, because that is part of the address
                // rather than a word in a sentence.
                Text("Ammy will send to \(resolved). Almost every endpoint needs "
                     + "HTTPS, and iOS blocks plain HTTP.")
            }
        }
        .task {
            // The monitor reads the device, not the relay, so it runs whether
            // or not a session does. That is what lets Now Playing and Media
            // Access say something true before anything has been started.
            controller.appDidBecomeActive()
            await controller.monitor.start()
            await autoStartIfPossible()
        }
        // .task covers a cold launch; this covers coming back from the
        // background, which is the more common way of arriving at a notice
        // that has already fired. onChange never sees the initial value, so
        // both are needed.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.appDidBecomeActive() }
        }
    }

    @MainActor
    private func start() async {
        await controller.start()
    }

    /// The scheme check, then start. Shared by Start and Restart so a bare host
    /// typed during a restart gets the same confirmation it would on first run.
    @MainActor
    private func beginOrConfirm() {
        if PresenceRelay.needsScheme(controller.endpoint),
           let resolved = PresenceRelay.normalised(controller.endpoint) {
            schemeToConfirm = resolved.absoluteString
        } else {
            Task { await start() }
        }
    }

    @MainActor
    private func stopSession() {
        Task {
            await controller.stop()
            didAutoStart = true   // don't immediately restart
        }
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
        guard !didAutoStart, !controller.isRunning, canAutoStart else { return }
        didAutoStart = true
        await start()
    }
}
