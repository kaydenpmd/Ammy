import ImageIO
import os
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

    /// The app's name as the Home Screen shows it: "Ammy". Sent with every push
    /// beside `displayVersion`, so a receiver can say who is sending.
    var displayName: String {
        infoDictionary?["CFBundleDisplayName"] as? String
            ?? infoDictionary?["CFBundleName"] as? String
            ?? "Ammy"
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

/// One line of text that scrolls sideways when it doesn't fit, the way the
/// Lock Screen's player shows a long title, rather than wrapping or cutting
/// it off.
///
/// It rests at the start, scrolls left until a second copy has taken the
/// first one's place, and rests again, so the loop has no seam. The trailing
/// edge fades while the text overflows, and the leading edge fades only while
/// it moves, so a line at rest starts crisp. Text that fits never moves, and
/// with Reduce Motion on nothing moves: it truncates, as Apple's players do.
///
/// Position comes from the clock rather than from an animation, so a change
/// of `id` starts the line from rest, and nothing keeps running after it.
private struct MarqueeLine: View {
    let text: Text
    /// Restarts the loop from rest when it changes. The Now Playing row passes
    /// the song, so its title and artist lines restart together.
    let id: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var restingSince = Date()

    // GUESS: Apple publishes none of these. They're LNPopupController's, a
    // long-running open-source replica of Music's player (marqueeScrollDelay
    // 2 s, marqueeScrollRate 30 pt/s, fade length 10, trailing buffer 50),
    // researched 24 Sept 2026 — the closest thing to Music's own numbers
    // short of stepping through a screen recording frame by frame.
    private static let rest: TimeInterval = 2
    private static let pointsPerSecond: CGFloat = 30
    private static let gap: CGFloat = 50
    private static let fade: CGFloat = 10

    private var scrolls: Bool { !reduceMotion && textWidth > boxWidth + 0.5 }

    var body: some View {
        // The resting copy sizes the line: its full width, one line tall. It
        // is what shows when the text fits, and what truncates under Reduce
        // Motion.
        text
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(scrolls ? 0 : 1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .background(alignment: .leading) {
                text
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
            .overlay(alignment: .leading) {
                if scrolls {
                    // Paused in the background: the keepalive keeps this
                    // process running there, and nobody can see the line.
                    TimelineView(.animation(paused: scenePhase == .background)) { timeline in
                        let travel = textWidth + Self.gap
                        let x = offset(at: timeline.date, travel: travel)
                        HStack(spacing: Self.gap) {
                            text
                            text
                        }
                        .accessibilityHidden(true)
                        .fixedSize()
                        .offset(x: -x)
                        .frame(width: boxWidth, alignment: .leading)
                        .mask { edges(leading: min(1, min(x, travel - x) / Self.fade)) }
                    }
                }
            }
            .onChange(of: id) { restingSince = Date() }
            // Read once, as the text, however many copies are on screen.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    private func offset(at date: Date, travel: CGFloat) -> CGFloat {
        let moving = Double(travel / Self.pointsPerSecond)
        let t = date.timeIntervalSince(restingSince).truncatingRemainder(dividingBy: Self.rest + moving)
        return t < Self.rest ? 0 : CGFloat(t - Self.rest) * Self.pointsPerSecond
    }

    /// Opaque in the middle, fading at each end. `leading` is 0 at rest, so
    /// the first letter isn't faded until it starts to move.
    private func edges(leading: CGFloat) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(1 - leading), .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fade)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fade)
        }
    }
}

/// What's playing, as the first thing on the screen.
///
/// Shaped like the Apple Account row at the top of Settings — artwork, a bold
/// line, a secondary line — because that is the pattern iOS already uses for
/// the one thing a grouped list is about. A bigger card with a progress bar
/// was considered and passed over on 23 Sept 2026: inside a settings-style
/// list it reads like another app's UI, and Ammy sends playback rather than
/// controlling it. It replaced the Status section's "Now Playing" row and
/// keeps that row's rule: what the device says is playing right now, whether
/// or not a session is running, and "Not Playing" (Control Center's wording,
/// which replaced "Nothing Playing" on 23 Sept 2026) whenever Ammy would send
/// nothing.
///
/// On 24 Sept 2026 the owner had its proportions matched to the Lock Screen's
/// Now Playing card: 57 pt artwork, title and artist on one line each and the
/// same size, scrolling when too long, the artwork as far from the section's
/// top and bottom as from its leading edge, with a corner concentric with the
/// section's. Each number below says where it came from: the owner's
/// screenshots, Apple's documentation, or both.
private struct NowPlayingRow: View {
    @ObservedObject var monitor: NowPlayingMonitor
    @Environment(\.displayScale) private var displayScale

    /// The Lock Screen's Now Playing artwork, measured on the owner's iPhone SE
    /// screenshot on 24 Sept 2026 at 56.8 pt; the same method reads this row's
    /// old 60 pt artwork as 59.9. No documentation gives it: Apple's iOS 26 UI
    /// kit has no Lock Screen player (it has Control Center's, whose artwork
    /// is 52 pt).
    private static let side: CGFloat = 57

    /// An iOS 26 grouped section's corner radius. Measured, not documented:
    /// 26.35 pt on the owner's SE, and 26.3 and 26.4 pt on two sections of a
    /// 16 Pro Max, each by fitting Apple's continuous-corner curve. No API
    /// reports it, and a List cell doesn't offer its shape to
    /// ConcentricRectangle (Apple Developer Forums thread 798726), so it's
    /// written down here.
    private static let sectionCorner: CGFloat = 26

    /// The row's leading inset as the system laid it out, 16 pt on an SE and
    /// 20 on a Pro Max. No API reports it either, so it's measured: where the
    /// row's content starts, less where its cell starts. The top and bottom
    /// insets are set to match, so the artwork sits as far from the section's
    /// top and bottom as from its leading edge.
    @State private var inset: CGFloat = 16
    @State private var contentLeading: CGFloat?
    @State private var cellLeading: CGFloat?

    /// Concentric with the section: its radius less the distance between
    /// them, which is Apple's own definition ("the container shape's corner
    /// radius minus the distance between corners", ConcentricRectangle's
    /// Edge.Corner.Style docs). 10 pt on an SE, 6 on a Pro Max.
    ///
    /// Never below `minimumCorner`, the same guard Apple's
    /// `.concentric(minimum:)` offers, so a device with an unusually large
    /// inset gets a softer corner rather than a square one. GUESS: 6, the
    /// smallest value any iPhone measured so far produces, so no iPhone is
    /// affected by it.
    private var corner: CGFloat { max(Self.minimumCorner, Self.sectionCorner - inset) }
    private static let minimumCorner: CGFloat = 6

    /// The range a measured inset has to fall in to be believed. Anything
    /// outside it means the measurement went wrong, and the last good value
    /// (16 at first) stays. GUESS: iPhones measure 16 and 20; this leaves room
    /// for iPad and Display Zoom without letting a broken read through.
    private static let plausibleInset: ClosedRange<CGFloat> = 8...40

    /// The cover shrunk to exactly the pixels it's drawn at, and which cover
    /// it was made from, so a new track never shows the last one's.
    @State private var thumbnail: (source: ObjectIdentifier, image: UIImage)?

    var body: some View {
        HStack(spacing: 14) {
            // The artwork, or the empty square, rounded and edged at its own
            // size, then centred in the square it's given, so a cover that
            // isn't square keeps its whole picture and its own rounded
            // corners.
            artwork
                .frame(width: Self.side, height: Self.side)
                .accessibilityHidden(true)

            // The text always has the room of a title line and an artist line.
            // A lone "Not Playing" is centred vertically in that room, the way
            // Control Center centres it where the song and artist would be, and
            // the row keeps its height when music starts or stops.
            ZStack(alignment: .leading) {
                lines(title: "Title", subtitle: "Artist", explicit: false, song: "")
                    .hidden()
                    .accessibilityHidden(true)
                lines(title: title, subtitle: subtitle, explicit: explicit, song: song)
            }
        }
        .accessibilityElement(children: .combine)
        // listRowInsets(_:_:) with edges is iOS 26: only the vertical insets
        // change, and the leading one stays the system's, lined up with the
        // section header and every other row.
        .listRowInsets(.vertical, inset)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: {
            contentLeading = $0
            measureInset()
        }
        // The system's own cell colour, supplied here only so the cell's edge
        // can be measured; this row isn't tappable, so there's no pressed
        // state to lose.
        .listRowBackground(
            Color(uiColor: .secondarySystemGroupedBackground)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: {
                    cellLeading = $0
                    measureInset()
                }
        )
        .task(id: ArtworkKey(source: monitor.artworkImage.map(ObjectIdentifier.init), scale: displayScale)) {
            makeThumbnail()
        }
    }

    private func measureInset() {
        guard let contentLeading, let cellLeading else { return }
        let measured = contentLeading - cellLeading
        if Self.plausibleInset.contains(measured), abs(measured - inset) > 0.25 {
            inset = measured
        }
    }

    private struct ArtworkKey: Hashable {
        let source: ObjectIdentifier?
        let scale: CGFloat
    }

    private static let log = Logger(subsystem: "com.local.ammy", category: "artwork")

    private func makeThumbnail() {
        guard let source = monitor.artworkImage, let jpeg = monitor.track?.artworkJPEG else {
            thumbnail = nil
            return
        }
        if let image = Self.downsample(jpeg, toPixels: Self.side * displayScale, scale: displayScale) {
            thumbnail = (ObjectIdentifier(source), image)
        } else {
            thumbnail = nil
            Self.log.error("couldn't downsample the cover; drawing the full-size one instead")
        }
    }

    /// Apple's documented way to shrink an image for display, from WWDC 2018
    /// session 219, "Image and Graphics Best Practices": decode it straight to
    /// the pixel size it's drawn at with ImageIO, rather than handing a large
    /// image to a view to shrink as it draws. The options are the session's
    /// own. Asked of this row's old path, Core Animation shrinks a 512 px cover
    /// to 114 px on an SE with its default linear filter, which samples a few
    /// source pixels per output pixel — the grainy look. Whether the Lock
    /// Screen does it this way is not documented; it's what Apple tells apps
    /// to do.
    private static func downsample(_ data: Data, toPixels pixels: CGFloat, scale: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image, scale: scale, orientation: .up)
    }

    /// `song` restarts both lines' scrolling together, so a new track by the
    /// same artist doesn't leave the artist line mid-scroll beside a title
    /// that has started again from rest.
    private func lines(title: String, subtitle: String?, explicit: Bool, song: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // An explicit track gets Music's E after a space, in the title's
            // own colour, the way the Lock Screen's player shows it. Small
            // symbol scale is what makes it sit like theirs.
            //   Measured, the owner's Lock Screen and Control Center
            //   screenshots, 24 Sept 2026: their E is exactly cap height, top
            //   on the cap line and bottom on the baseline. Build 101's, at
            //   the default medium scale, was 1.29x cap height and overhung
            //   both.
            //   Documented, HIG "SF Symbols": "Each symbol is also available
            //   in three scales: small, medium (the default), and large. The
            //   scales are defined relative to the cap height of the San
            //   Francisco system font." Its figure shows the small scale
            //   touching both the cap line and the baseline, and medium
            //   extending slightly past each.
            //   Not documented: whether imageScale reaches a symbol embedded
            //   in Text. Its doc says only "images within the view". If the
            //   E still overhangs on a device, that's the answer.
            MarqueeLine(
                text: (explicit ? Text("\(title) \(Image(systemName: "e.square.fill"))") : Text(title))
                    .font(.headline),
                id: song)
                .imageScale(.small)
            // The same size as the title, lighter and secondary. Measured: the
            // Lock Screen draws both lines at 17 pt (cap height 12 pt on each)
            // and Control Center both at about 14, the hierarchy carried by
            // weight and colour rather than size. Documented, HIG
            // "Typography": Headline is 17 pt Semibold and Body 17 pt Regular
            // at the default Dynamic Type size, the same pair.
            if let subtitle {
                MarqueeLine(
                    text: Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary),
                    id: song)
            }
        }
    }

    @ViewBuilder private var artwork: some View {
        if playing, let image = monitor.artworkImage {
            // The downsampled copy when it belongs to this cover, drawn at its
            // own size; the full one only until that's ready, or if it failed.
            let current = thumbnail.flatMap { $0.source == ObjectIdentifier(image) ? $0.image : nil }
            // Fitted, not cropped: a cover that isn't square shows all of
            // itself, centred in the square. Measured on the owner's Lock
            // Screen, 24 Sept 2026: a portrait cover drawn 49 x 57 pt, full
            // height, centred, rounded at its own corners, nothing behind it.
            Image(uiImage: current ?? image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                // One physical pixel in the system separator colour, so a cover
                // the colour of the row still has an edge. GUESS: Apple doesn't
                // document the stroke Music draws on artwork; this is iOS's
                // documented hairline, the one between list rows, applied to it.
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color(uiColor: .separator), lineWidth: 1 / displayScale)
                }
        } else {
            // Nothing playing: a plain grey square, no symbol, as the owner
            // asked on 24 Sept 2026. It's distinct from the cell on its own,
            // so it needs no hairline.
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Self.emptyFill)
        }
    }

    /// The empty square's colour: the system's own, not a value copied in.
    ///
    /// Apple names no colour for it. Measured, Apple's iPhone User Guide
    /// ("Use and customize Control Center", iOS 26): Control Center shows Not
    /// Playing as an empty rounded square with no symbol, in the same
    /// translucent glass as the AirPlay button's platter, a vibrant material
    /// fill that can't be drawn on an opaque list cell. Apple's iOS 26 UI kit
    /// has no empty state to read, and the Lock Screen shows no player at all.
    /// Documented, UIColor: tertiarySystemFill is for "large shapes, such as
    /// input fields, search bars, or buttons", and like Control Center's it
    /// lets the background show through. The owner chose it on 24 Sept 2026.
    private static let emptyFill = Color(uiColor: .tertiarySystemFill)

    /// Something Ammy would send right now.
    private var playing: Bool {
        monitor.authorized && monitor.isPlaying && monitor.track != nil
    }

    private var title: String {
        // The access prompt at the top says why; this row only says what it sees.
        guard monitor.authorized else { return "Not Available" }
        // Control Center's words for the same moment.
        guard playing, let track = monitor.track else { return "Not Playing" }
        return track.title
    }

    private var subtitle: String? {
        playing ? monitor.track?.artist : nil
    }

    /// Which track the lines are showing, so both restart together on a new one.
    private var song: String {
        playing ? monitor.track?.key ?? "" : ""
    }

    private var explicit: Bool {
        playing && monitor.track?.explicit == true
    }
}

/// Asks for Media & Apple Music access, at the top of the screen, for as long
/// as Ammy doesn't have it. It replaced the Status section's "Media Access"
/// row on 24 Sept 2026: a row reading "Not Granted" stated the problem one
/// section down, and offered no way to fix it. With access granted this isn't
/// shown at all.
///
/// "Media & Apple Music" is the permission's name in Settings, so the words
/// match what the person will look for there.
private struct MediaAccessPrompt: View {
    @ObservedObject var monitor: NowPlayingMonitor
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Allow Access to Media & Apple Music")
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            switch monitor.access {
            // Never asked: the system's own question is the right one to show.
            case .notDetermined:
                Button("Allow Access") {
                    Task { await monitor.start() }
                }
            // Refused: iOS won't ask twice, so the only way is Settings.
            case .denied:
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            // Restricted (Screen Time or a profile) has nothing to offer here,
            // and neither does a status added after this was written.
            default:
                EmptyView()
            }
        }
    }

    private var detail: String {
        switch monitor.access {
        case .restricted:
            return "Access is restricted on this device, so Ammy can't see what's playing."
        default:
            return "Ammy needs it to see what's playing."
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var controller: PresenceController
    @Environment(\.scenePhase) private var scenePhase
    /// The person pressed Stop, so coming back to the app must not undo that.
    /// Cleared by the next Start. Nothing else sets it — a session that ended
    /// by failure is exactly the one reopening the app should restart.
    @State private var stoppedByUser = false

    /// Set to the address Ammy *would* use when the typed one has no scheme.
    /// Non-nil puts the confirmation in front of the person rather than editing
    /// their text behind their back.
    @State private var schemeToConfirm: String?

    /// Ties the glass surfaces together so they morph into one another rather
    /// than fading. See the bar below for what the two IDs mean.
    @Namespace private var glass

    /// What the window already reserves at the bottom edge — 34pt for a home
    /// indicator, 0 on a home-button phone. Measured from outside the bottom
    /// bar, because the bar extends the safe area it sits in and so cannot
    /// measure it from within itself. See the padding at the foot of the bar.
    @State private var bottomSafeArea: CGFloat = 0

    /// SwiftUI's own `.padding()` amount, spelled out because the bar subtracts
    /// from it rather than simply applying it.
    private static let barGap: CGFloat = 16

    /// Total distance from the button's bottom edge to the true screen edge on
    /// a Face ID phone — not the full 34pt home-indicator inset. The 17 Sept
    /// fix (`max(0, barGap - bottomSafeArea)`) correctly stops adding *extra*
    /// padding on top of the inset, but that still leaves the button sitting
    /// at the full 34pt, and on-screen that reads as too high. Measured
    /// pixel-for-pixel against Shortcuts' own floating tab bar (Library/
    /// Automation/Gallery) on an iPhone 16 Pro Max screenshot 18 Sept: its
    /// pill sits 21.3pt above the true edge, not 34pt — system bars intrude
    /// into part of the reserved zone rather than stopping at its top. This
    /// constant pins the button there regardless of `bottomSafeArea`, since
    /// `bottomSafeArea + (edgeGap - bottomSafeArea) == edgeGap` always — no
    /// clamp needed, unlike the old formula.
    ///
    /// **Not yet touched on a real device** — screenshot measurement only.
    /// Check this on both a Face ID phone and the SE before trusting it; it
    /// may need tuning either direction once someone actually looks at it.
    private static let edgeGap: CGFloat = 21

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
                if !controller.monitor.authorized {
                    MediaAccessPrompt(monitor: controller.monitor)
                }

                Section("Now Playing") {
                    NowPlayingRow(monitor: controller.monitor)
                }

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
                    LabeledContent("Version", value: Bundle.main.displayVersion)
                }

                // Unlabeled on purpose: it is a way out of this screen rather
                // than another fact about the current one, so a header would
                // group it with things it has nothing to do with.
                Section {
                    NavigationLink("History") {
                        LinkHistoryView()
                    }
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
                // The gap above the button is a constant. The gap below it
                // targets `edgeGap` from the true screen edge regardless of
                // device — see the doc comment on `edgeGap` for why 34pt (the
                // raw home-indicator inset, and what the first fix here
                // produced) still read as too high. This subtracts whatever
                // `bottomSafeArea` already provides, going negative on a Face
                // ID phone to pull the button into part of the reserved zone;
                // no clamp needed, since the two `bottomSafeArea` terms cancel
                // and the total is pinned at `edgeGap` no matter what it reads.
                .padding(.top, Self.barGap)
                .padding(.bottom, Self.edgeGap - bottomSafeArea)
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
        // Attached to the NavigationStack, deliberately outside the bottom bar:
        // `safeAreaBar` extends the safe area of whatever it modifies, so a
        // reading taken inside the bar's own content is measuring the bar. The
        // stack sits outside that and reports what the window reserves.
        //
        // onGeometryChange rather than a one-shot read of the key window, since
        // iPad rotates and Split View resizes; and rather than a GeometryReader,
        // which would take over the layout of everything inside it.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.bottom
        } action: { bottomSafeArea = $0 }
        .task {
            // The monitor reads the device, not the relay, so it runs whether
            // or not a session does. That is what lets Now Playing and the
            // access prompt say something true before anything has started.
            controller.appDidBecomeActive()
            await controller.monitor.start()
            await autoStartIfPossible()
        }
        // .task covers a cold launch; this covers coming back from the
        // background, which is the more common way of arriving at a notice
        // that has already fired. onChange never sees the initial value, so
        // both are needed.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                controller.appDidBecomeActive()
                // Coming back from Settings with access newly granted: the
                // monitor only asks again while it isn't running, so this
                // costs nothing once access is in hand. The autostart below
                // may ask at the same moment; it waits for this answer rather
                // than seeing none.
                Task { await controller.monitor.start() }
                // A session that failed leaves the process alive but idle —
                // iOS suspends it rather than killing it — so a cold-launch-only
                // autostart never ran again, and opening Ammy after (say) the PC
                // slept for half an hour silently did nothing.
                Task { await autoStartIfPossible() }
            } else if phase == .background {
                // .background, not .inactive. Inactive also fires for Control
                // Centre, a pulled-down notification shade and an incoming
                // call banner — none of which means the alert has been
                // abandoned, and converting on those would snatch it away
                // while the person was still going to read it.
                controller.appDidEnterBackground()
            }
        }
        // Opening ammy://notify says this launch is about to be switched away
        // from, so any failure should arrive as a notification. Nothing else:
        // the app opens exactly as it would have otherwise.
        .onOpenURL { url in
            if url.host()?.lowercased() == "notify" || url.path().lowercased() == "/notify" {
                controller.suppressNextPopup()
            }
        }
        .alert(PushOutcome.failureTitle, isPresented: Binding(
            get: { controller.pendingFailure != nil },
            set: { if !$0 { controller.dismissFailure() } }
        )) {
            Button("OK") { controller.dismissFailure() }
        } message: {
            // The alert appears with the session already ended, so the way back
            // is usually the Start button beneath it. Usually: a trip through
            // Control Center or a call banner comes back through .active, which
            // autostarts while the alert is still up. It says whichever is true
            // when it is read.
            Text(controller.pendingFailure.map {
                $0.explanation + (controller.isRunning ? " Ammy is trying again." : " Press Start to try again.")
            } ?? "")
        }
    }

    @MainActor
    private func start() async {
        stoppedByUser = false
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
            stoppedByUser = true   // coming back to the app must not restart it
        }
    }

    /// Ammy begins reporting whenever it comes to the front without a session
    /// running — launched cold, or brought back after one ended in failure —
    /// by any means: the icon, the app switcher, or a Shortcuts `Open App`
    /// action. That is the entire relaunch mechanism, and it is deliberately
    /// the whole of it: there is nothing to tell the app on the way in, so
    /// there is no deep link to get wrong, no scheme to register, and no second
    /// code path that only runs when an automation fires. The one exception is
    /// a session the person stopped themselves.
    ///
    /// Deliberately does not prompt. Something launching Ammy unattended must
    /// not meet a modal it cannot answer, and by the time autostart matters the
    /// stored address has already been resolved by an interactive start.
    @MainActor
    private func autoStartIfPossible() async {
        guard !stoppedByUser, !controller.isRunning, canAutoStart else { return }
        await controller.start()
    }
}
