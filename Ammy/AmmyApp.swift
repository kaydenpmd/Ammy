import ImageIO
import LNSystemMarqueeLabel
import os
import SwiftUI
import UIKit

extension Bundle {
    /// e.g. "1.0 (47)". The build number is the commit count CI built the IPA
    /// from, so this is the quickest way to tell whether the phone is actually
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

/// The Now Playing row's title and artist, scrolled by UIKit's own marquee:
/// the one built into UILabel, which Apple's apps use and which UIKit keeps
/// private. LNSystemMarqueeLabel (Léo Natan, MIT; ThirdPartyNotices.txt)
/// switches it on. LNPopupController, a long-running open-source replica of
/// Music's player, offers the same label as an option (its
/// LNPopupUseSystemMarqueeLabel setting) and uses it by default only on Mac
/// Catalyst, so this path has seen little use on iPhone. The owner asked for
/// it on 15 Oct 2026, after asking for the scroll to ease into a stop like
/// Music's: Apple publishes no timing for its marquee, so the only exact
/// match is the system's own.
///
/// Each line scrolls on its own; a new song restarts both from rest at once.
/// The package's `synchronizedLabels`, which would keep them in step, is left
/// off: in 0.1.2 its +load reads a C++ static before C++ static initializers
/// run (Apple's +load ordering), so the sync never switches on, and if it did
/// it could leave a long title paused beside a short artist that never
/// scrolls. Unsynced, UIKit's repeat count stays 0 (loop forever) and none of
/// the package's swizzled paths run.
///
/// Private API, so two guards. Ammy is sideloaded and could never pass App
/// Review anyway (CLAUDE.md, Distribution). And if an iOS release drops the
/// properties, `available` is false and the row uses MarqueeLine instead,
/// because LNSystemMarqueeLabel sets them by key and would crash without them.
private struct SystemMarqueeLines: UIViewRepresentable {
    let title: String
    let subtitle: String?
    let explicit: Bool
    /// Restarts both lines from rest when it changes.
    let song: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    /// Checked once. The names are UILabel's own (iOS 26 header dumps), plus
    /// the `label` the package's swizzle asks of UIKit's private marquee
    /// delegate whenever a scroll starts (a missing class means no swizzle).
    /// The log says which marquee is running, so a fallback isn't a silent one.
    static let available: Bool = {
        let label = ["marqueeEnabled", "setMarqueeEnabled:", "marqueeRunning", "setMarqueeRunning:"]
            .allSatisfy { UILabel.instancesRespond(to: NSSelectorFromString($0)) }
        let delegate = NSClassFromString("_UILabelMarqueeAnimationDelegate")?
            .instancesRespond(to: NSSelectorFromString("label")) ?? true
        let has = label && delegate
        Logger(subsystem: "com.local.ammy", category: "marquee").notice(
            "\(has ? "UIKit's marquee" : "UIKit's marquee is missing; using MarqueeLine", privacy: .public)")
        return has
    }()

    final class Lines: UIView {
        let title = LNSystemMarqueeLabel(frame: .zero)
        let subtitle = LNSystemMarqueeLabel(frame: .zero)
        /// What the labels were last given, so an update that changes nothing
        /// doesn't hand UIKit new text and restart the scroll.
        var shown: [AnyHashable] = []
        var song: String?
        /// The gap between the lines, as the VStack in MarqueeLine's layout.
        static let spacing: CGFloat = 2

        override init(frame: CGRect) {
            super.init(frame: frame)
            for label in [title, subtitle] {
                label.numberOfLines = 1
                // What shows when the line doesn't scroll: under Reduce Motion,
                // as Apple's players do.
                label.lineBreakMode = .byTruncatingTail
                // VoiceOver reads the SwiftUI label set in NowPlayingRow.lines.
                label.isAccessibilityElement = false
                addSubview(label)
            }
            accessibilityElementsHidden = true
        }

        required init?(coder: NSCoder) { nil }

        private func lineHeight(_ label: UILabel) -> CGFloat {
            ceil(label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)).height)
        }

        var contentHeight: CGFloat {
            subtitle.isHidden ? lineHeight(title) : lineHeight(title) + Self.spacing + lineHeight(subtitle)
        }

        var naturalWidth: CGFloat {
            let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            return ceil(max(title.sizeThatFits(unbounded).width, subtitle.isHidden ? 0 : subtitle.sizeThatFits(unbounded).width))
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let top = lineHeight(title)
            title.frame = CGRect(x: 0, y: 0, width: bounds.width, height: top)
            subtitle.frame = CGRect(x: 0, y: top + Self.spacing, width: bounds.width, height: lineHeight(subtitle))
        }
    }

    func makeUIView(context: Context) -> Lines {
        let view = Lines()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: Lines, context: Context) {
        // Fonts built for the environment's text size and Bold Text setting,
        // as SwiftUI's .font(.headline) would: Headline and Body, both 17 pt at
        // the default size, the pair the Lock Screen's player measures
        // (NowPlayingRow.lines).
        let weight: UILegibilityWeight = switch legibilityWeight {
        case .some(.bold): .bold
        case .some(.regular): .regular
        default: .unspecified
        }
        let category = UIContentSizeCategory(dynamicTypeSize)
        let traits = UITraitCollection { traits in
            traits.preferredContentSizeCategory = category
            traits.legibilityWeight = weight
        }
        let titleFont = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traits)
        let bodyFont = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)

        let shown: [AnyHashable] = [title, subtitle ?? "", subtitle == nil, explicit, titleFont, bodyFont]
        if view.shown != shown {
            view.shown = shown
            view.title.attributedText = Self.titleText(title, explicit: explicit, font: titleFont)
            view.subtitle.attributedText = NSAttributedString(
                string: subtitle ?? "",
                attributes: [.font: bodyFont, .foregroundColor: UIColor.secondaryLabel])
            view.subtitle.isHidden = subtitle == nil
            view.invalidateIntrinsicContentSize()
            view.setNeedsLayout()
        }

        // A new song starts both lines from rest, together.
        if view.song != song {
            view.song = song
            view.title.reset()
            view.subtitle.reset()
        }
        // Stopped in the background, where the keepalive keeps this process
        // running and nobody can see the row; off under Reduce Motion.
        let running = !reduceMotion && scenePhase != .background
        for label in [view.title, view.subtitle] {
            label.isMarqueeScrollEnabled = !reduceMotion
            label.isRunning = running
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Lines, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.naturalWidth, height: uiView.contentHeight)
    }

    /// The title, then for an explicit track Music's E after a space, in the
    /// title's own colour and at small symbol scale, which is what makes it
    /// cap height like the Lock Screen's (see NowPlayingRow.lines). UIKit
    /// places a symbol image in a text attachment on the text's baseline and
    /// draws a template symbol in the text's colour.
    static func titleText(_ title: String, explicit: Bool, font: UIFont) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
        let text = NSMutableAttributedString(string: title, attributes: attributes)
        if explicit, let badge = UIImage(
            systemName: "e.square.fill",
            withConfiguration: UIImage.SymbolConfiguration(font: font, scale: .small)) {
            text.append(NSAttributedString(string: " ", attributes: attributes))
            let attachment = NSMutableAttributedString(attachment: NSTextAttachment(image: badge))
            attachment.addAttributes(attributes, range: NSRange(location: 0, length: attachment.length))
            text.append(attachment)
        }
        return text
    }
}

/// One line of text that scrolls sideways when it doesn't fit, the way the
/// Lock Screen's player shows a long title, rather than wrapping or cutting
/// it off. Since 15 Oct 2026 it is the fallback for an iOS without UIKit's
/// own marquee (SystemMarqueeLines); on iOS 26 and 27 that one runs instead.
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
/// screenshots, Apple's documentation, or both. Since 29 Oct 2026 the spacing
/// is the system's: the row sets none of its gaps, so the top and bottom are
/// the list's own row padding and the gap to the text is SwiftUI's standard
/// spacing, and the corner stays as concentric with the
/// section as those gaps allow, the one part of the Lock Screen's spacing the
/// row keeps. The 57 pt artwork and the 17 pt lines are still the Lock
/// Screen's.
private struct NowPlayingRow: View {
    @ObservedObject var monitor: NowPlayingMonitor
    /// TEMPORARY, 29 Oct 2026: the Lock Screen player's spacing instead of
    /// the list's own, for the owner to compare (ContentView's
    /// lockScreenSpacing).
    let lockScreenSpacing: Bool
    @Environment(\.displayScale) private var displayScale

    /// The Lock Screen's Now Playing artwork, which is a constant there too:
    /// Apple's player sets its frame to a literal 57 x 57 pt
    /// (-[MRULockscreenView layoutSubviews] in MediaControls.framework, as
    /// decompiled from iOS 17.6.1, with the same structure in 18.2 and 26.1),
    /// reading neither text size, screen width nor device. The owner's SE
    /// screenshots agree: 56.8 pt on 24 Sept 2026, and 57.0 on iOS 27.2 at both
    /// the smallest and the largest standard text size. Apple documents none
    /// of it; re-measure after a major iOS release.
    private static let side: CGFloat = 57

    /// An iOS 26 grouped section's corner radius. Measured, not documented:
    /// 26.35 pt on the owner's SE, and 26.3 and 26.4 pt on two sections of a
    /// 16 Pro Max, each by fitting Apple's continuous-corner curve. No API
    /// reports it, and a List cell doesn't offer its shape to
    /// ConcentricRectangle (Apple Developer Forums thread 798726), so it's
    /// written down here.
    private static let sectionCorner: CGFloat = 26

    /// How far the artwork sits from its cell's leading and top edges, as the
    /// system laid it out. No API reports either, so both are measured: the
    /// side as the artwork's leading edge less the cell's, the top as half the
    /// cell's height beyond the artwork, which the row centres, because a
    /// height doesn't move when the list scrolls. The side is the list's
    /// leading margin: 20 pt on a Pro Max in September 2026, not rechecked
    /// since, and on the owner's SE 16 pt in a 26 Sept screenshot (iOS 27.0,
    /// the owner thinks) but 20 on iOS 27.2, when the whole list moved 4 pt in.
    /// The top is the list's own row padding: 15 pt on the owner's SE on 27.2
    /// (build 134's 35 less its 20), as Settings' Apple Account row measures
    /// against 20 from the side.
    ///
    /// The row sets none of these gaps, nor the one to the text, since 29 Oct
    /// 2026: the owner chose iOS 27.2's spacing over even gaps ("wanna match
    /// here for better or worse"), so whatever a later iOS does to the list's
    /// own spacing it also does here. The starting values are guesses,
    /// replaced as soon as the row is measured: 16 was the SE's side before
    /// 27.2, and 15 its top on 27.2.
    @State private var sideInset: CGFloat = 16
    @State private var topInset: CGFloat = 15
    @State private var artworkX: CGFloat?
    @State private var cellX: CGFloat?
    @State private var cellHeight: CGFloat?

    /// The Lock Screen player's own spacing, for the temporary comparison.
    /// -[MRULockscreenViewController viewDidLoad] sets the player's content
    /// insets to 14 pt on every side, and -[MRULockscreenView layoutSubviews]
    /// puts the artwork at their top-left and starts the text 57 + 12 pt in
    /// (MediaControls.framework, decompiled from iOS 17.6.1). 14 pt is also
    /// the HIG's documented Lock Screen margin for Live Activities.
    private static let lockScreenInset: CGFloat = 14
    private static let lockScreenGap: CGFloat = 12

    /// The list's own insets around the row, padding aside: where it put the
    /// row less where the cell starts, and half the cell's height beyond the
    /// row. The Lock Screen spacing pads by the difference from these. The
    /// side can't move with that padding: the list puts the row at its own
    /// inset, however wide the row is. The top could: the padding changes the
    /// row's height at once and the cell's only when the list resizes it, so a
    /// reading taken in between would feed its own error back into the
    /// padding. So the top is read only with the switch off, and a launch with
    /// it on starts from 15, the owner's SE on 27.2.
    @State private var listSide: CGFloat = 16
    @State private var listTop: CGFloat = 15
    @State private var rowX: CGFloat?
    @State private var rowHeight: CGFloat?

    /// As concentric with the section as the gaps allow. With equal gaps that
    /// is the section's radius less the gap, Apple's own definition ("the
    /// container shape's corner radius minus the distance between corners",
    /// ConcentricRectangle's Edge.Corner.Style docs). With unequal gaps no
    /// radius is exactly concentric, so this takes the one whose centre lands
    /// nearest the section corner's: the radius less the average of the two
    /// gaps. With the SE's 15 pt top and 20 pt side on 27.2, 26 - 17.5 = 8.5 pt.
    ///
    /// Never below `minimumCorner`, the same guard Apple's
    /// `.concentric(minimum:)` offers, so a device with unusually large gaps
    /// gets a softer corner rather than a square one. GUESS: 6, the smallest
    /// value any iPhone measured so far has produced.
    private var corner: CGFloat {
        max(Self.minimumCorner, Self.sectionCorner - (sideInset + topInset) / 2)
    }
    private static let minimumCorner: CGFloat = 6

    /// The ranges a measured gap has to fall in to be believed. Anything
    /// outside means the measurement went wrong, and the last good value
    /// stays. GUESS: iPhones measure 16 or 20 at the side and about 15 at the
    /// top; these leave room for iPad, Display Zoom and large text without
    /// letting a broken read through.
    private static let plausibleSide: ClosedRange<CGFloat> = 8...40
    private static let plausibleTop: ClosedRange<CGFloat> = 4...60

    /// The cover shrunk to exactly the pixels it's drawn at, and which cover
    /// it was made from, so a new track never shows the last one's.
    @State private var thumbnail: (source: ObjectIdentifier, image: UIImage)?

    var body: some View {
        // No spacing given, except under the temporary lockScreenSpacing (the
        // Lock Screen's 12 pt, lockScreenGap): SwiftUI's standard gap between
        // the artwork and the text rather than a number of Ammy's own.
        // Settings' Apple Account row measures about 9 pt there; this row
        // isn't measured yet.
        HStack(spacing: lockScreenSpacing ? Self.lockScreenGap : nil) {
            // The artwork, or the empty square, rounded and edged at its own
            // size, then centred in the square it's given, so a cover that
            // isn't square keeps its whole picture and its own rounded
            // corners.
            artwork
                .frame(width: Self.side, height: Self.side)
                .accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: {
                    artworkX = $0
                    measureInsets()
                }

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
        // The Lock Screen's 14 pt is the list's own inset moved by the
        // difference: padding that's negative where the list's is wider. The
        // trailing side takes the leading side's difference, the list's margins
        // being the same on both sides.
        .padding(.horizontal, lockScreenSpacing ? Self.lockScreenInset - listSide : 0)
        .padding(.vertical, lockScreenSpacing ? Self.lockScreenInset - listTop : 0)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: {
            rowX = $0
            measureInsets()
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            rowHeight = $0
            measureInsets()
        }
        .accessibilityElement(children: .combine)
        // No listRowInsets here. Build 134 asked for zero on the vertical edges
        // and added 20 pt of padding, and the owner's SE on iOS 27.2 showed
        // 35 pt above and below the artwork: the list's own 15 plus the 20, so
        // the zero never took effect.
        // The system's own cell colour, supplied here only so the cell can be
        // measured; this row isn't tappable, so there's no pressed state to
        // lose.
        .listRowBackground(
            Color(uiColor: .secondarySystemGroupedBackground)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: {
                    cellX = $0
                    measureInsets()
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    cellHeight = $0
                    measureInsets()
                }
        )
        .task(id: ArtworkKey(source: monitor.artworkImage.map(ObjectIdentifier.init), scale: displayScale)) {
            makeThumbnail()
        }
    }

    private func measureInsets() {
        guard let cellX, let cellHeight else { return }
        if let artworkX {
            let leading = artworkX - cellX
            if Self.plausibleSide.contains(leading), abs(leading - sideInset) > 0.25 {
                sideInset = leading
            }
        }
        let top = (cellHeight - Self.side) / 2
        if Self.plausibleTop.contains(top), abs(top - topInset) > 0.25 {
            topInset = top
        }
        if let rowX {
            let leading = rowX - cellX
            if Self.plausibleSide.contains(leading), abs(leading - listSide) > 0.25 {
                listSide = leading
            }
        }
        if !lockScreenSpacing, let rowHeight {
            let top = (cellHeight - rowHeight) / 2
            if Self.plausibleTop.contains(top), abs(top - listTop) > 0.25 {
                listTop = top
            }
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
    ///
    /// UIKit's own marquee where the system has it (SystemMarqueeLines), and
    /// the hand-made one below where it doesn't. The notes below hold for
    /// both: SystemMarqueeLines builds the same fonts, colours and E.
    @ViewBuilder
    private func lines(title: String, subtitle: String?, explicit: Bool, song: String) -> some View {
        if SystemMarqueeLines.available {
            // Spoken as the hand-made lines were: the title as Text, E and all,
            // then the artist, one element, which the row's .combine joins.
            let titleText = explicit ? Text("\(title) \(Image(systemName: "e.square.fill"))") : Text(title)
            SystemMarqueeLines(title: title, subtitle: subtitle, explicit: explicit, song: song)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(subtitle.map { titleText + Text(", \($0)") } ?? titleText)
        } else {
            fallbackLines(title: title, subtitle: subtitle, explicit: explicit, song: song)
        }
    }

    private func fallbackLines(title: String, subtitle: String?, explicit: Bool, song: String) -> some View {
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

    /// TEMPORARY, 29 Oct 2026: lets the owner compare the Now Playing row's
    /// spacing on the device, the Lock Screen player's or the list's own.
    /// Once one is chosen, remove the switch and its section, and in
    /// NowPlayingRow the lockScreenSpacing parameter, lockScreenInset and
    /// lockScreenGap, listSide/listTop/rowX/rowHeight, the two paddings, the
    /// two onGeometryChange modifiers after them, and their part of
    /// measureInsets(). If the Lock Screen's spacing wins, keep those and drop
    /// only the switch.
    @AppStorage("lockScreenSpacing") private var lockScreenSpacing = false

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
                    NowPlayingRow(monitor: controller.monitor, lockScreenSpacing: lockScreenSpacing)
                }

                // TEMPORARY: see lockScreenSpacing.
                Section {
                    Toggle("Lock Screen Spacing", isOn: $lockScreenSpacing)
                } footer: {
                    Text("Temporary. Spaces Now Playing like the Lock Screen's player instead of with the list's own spacing.")
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
