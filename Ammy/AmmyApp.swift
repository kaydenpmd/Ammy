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
                Button {
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
                } label: {
                    // The style does not supply enough weight on its own.
                    // Measured at identical 26px cap height, in clean
                    // screenshots: this label's stroke-to-cap ratio was 0.154
                    // against 0.19 for Apple's own filled buttons in Health —
                    // regular against semibold. A photo of Setup Assistant's
                    // Continue button agrees but cannot prove it; at that
                    // resolution the stroke quantises to 2px or 3px and nothing
                    // between.
                    //
                    // Overriding a style's default is usually the wrong move
                    // (see the shape note below), but weight is not a platform
                    // default that should drift — a primary action reads as one
                    // or it doesn't, and glass is *lower* contrast than an
                    // opaque fill, so it wants more weight here, not less.
                    Text(running ? "Stop" : "Start")
                        .fontWeight(.semibold)
                }
                // Two styles, not one. Start is the prominent blue; Stop is
                // plain glass — the quiet half of the same pair, the way
                // .bordered relates to .borderedProminent. Once the app is
                // running its job is done, and the button stops being a call to
                // action and becomes a way to undo one.
                //
                // Glass rather than an opaque fill either way: the bar underneath
                // is already blurring whatever scrolls past it, and a solid
                // platter on a translucent bar reads as two unrelated surfaces
                // stacked.
                //
                // If this ever fails to compile with "cannot be resolved without
                // a contextual type", spell the style out as
                // GlassProminentButtonStyle() / GlassButtonStyle() — the
                // leading-dot form has a known inference quirk.
                //
                // .glassProminent carries the interactive layer itself —
                // verified on build 42, on device. Pressing it scales the glass,
                // shimmers across the surface and lights up at the touch point.
                // Nothing extra is needed, and in particular do NOT add
                // .glassEffect(.regular.interactive()) on top: that stacks a
                // second material on a style that already has one. Whether
                // .glass behaves identically is UNVERIFIED — it should, but only
                // the prominent one has actually been pressed.
                //
                // Worth recording because the public write-ups flatly contradict
                // each other on this, and an earlier attempt here rebuilt the
                // button by hand out of .plain plus an explicit glassEffect to
                // get a behaviour the style already had. One install answered
                // what an afternoon of reading could not.
                .glassButtonStyle(prominent: !running)
                // Capsule is left undeclared on purpose: it is the iOS 26
                // default for a text button and should keep tracking the
                // platform. Pinning .buttonBorderShape(.capsule) would freeze it
                // against a future OS that moves on.
                .controlSize(.large)
                // iOS 26's own way to say "fill the width", and independent of
                // the style above — any style with a platter stretches, glass
                // included. The pre-26 move was .frame(maxWidth: .infinity) on
                // the *label*, which worked only by accident of how these styles
                // measure themselves.
                .buttonSizing(.flexible)
                .disabled(!canAutoStart)
                // Vertical is the system default; horizontal is measured, and
                // deliberately NOT the same value.
                //
                // A floating element in iOS 26 does not sit on the content
                // margin — it sits further in, so it reads as hovering rather
                // than as part of the layout.
                //
                // 21pt is the documented frame inset, from two independent
                // reverse-engineerings that agree: Learn UI Design's iOS 26
                // pattern guide ("inset from the screen edges, 21pt on left,
                // right and bottom") and ryanashcraft/FabBar, a faithful
                // reimplementation of the iOS 26 tab bar ("apply 21pt padding on
                // all sides"). The oddness of the value is part of why it is
                // credible — nobody guesses 21.
                //
                // Measuring screenshots gave 24–28 instead, and that was not
                // wrong so much as measuring the wrong thing: a pixel count
                // finds where the glass's solid fill begins, while the frame
                // sits 3–7pt further out under the material's soft edge and
                // shadow — further in dark mode than light, which is exactly the
                // spread that could not be narrowed. Don't re-derive this from a
                // screenshot; a deliberately soft edge cannot yield it.
                //
                // There is no system constant exposed for this — bare .padding()
                // gives the CONTENT margin, not the floating one — which is why
                // this axis is a number and the vertical one is not.
                //
                // Vertical stays adaptive: on a Face ID phone the home indicator
                // already reserves ~34pt, but on a home-button phone that inset
                // is zero and the button would sit on the bezel — a bug that is
                // invisible on the devices most people test on.
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


private extension View {
    /// Chooses between the two glass button styles.
    ///
    /// This cannot be a ternary. `buttonStyle(_:)` takes a concrete type, and
    /// `.glass` and `.glassProminent` are different ones, so the two branches of
    /// a `?:` have nothing to unify to. A `@ViewBuilder` is the idiomatic way to
    /// pick a style at runtime.
    ///
    /// The cost is that the branches are separate view identities, so flipping
    /// between them re-creates the button rather than animating one into the
    /// other. For a start/stop toggle that is fine — but it is why the change
    /// may read as a hard cut rather than a crossfade.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.glass)
        }
    }
}
