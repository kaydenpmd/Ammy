import Foundation
import MediaPlayer
import UIKit

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var elapsed: TimeInterval

    /// Apple Music catalog ID. The relay uses this for an exact artwork lookup
    /// with no fuzzy matching. Local files report "0".
    var storeID: String

    /// The cover as it exists on the phone, already JPEG-encoded. This is the
    /// only artwork source that always works: the iTunes Store search index the
    /// relay falls back to does not contain every track on Apple Music, and
    /// smaller/independent releases are routinely missing from it.
    var artworkJPEG: Data?

    /// Playing from a live station, where there is no position to report.
    var live: Bool = false

    /// Identity for change detection — elapsed is excluded on purpose.
    var key: String { "\(title)|\(artist)|\(album)" }
}

@MainActor
final class NowPlayingMonitor: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var authorized = false

    /// The current track's cover as an image, for the Now Playing row — the
    /// same picture that was JPEG-encoded for the push, kept rather than
    /// decoded back out of the JPEG on every 5s refresh. Nil with no track or
    /// no cover.
    @Published private(set) var artworkImage: UIImage?

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var pollTimer: Timer?
    private var running = false

    // refresh() runs on every playback notification and every 5s poll.
    // Re-encoding a JPEG that often is pure waste, so keep the last one.
    private var artworkKey: String?
    private var artworkData: Data?
    private var artworkSource: UIImage?

    /// Idempotent. The view starts the monitor when it appears, and
    /// PresenceController.start() asks again for every session — including
    /// every Restart. Without this guard each of those added another pair of
    /// notification observers and another 5s timer on top of the last.
    func start() async {
        guard !running else { return }
        running = true

        let status: MPMediaLibraryAuthorizationStatus = await withCheckedContinuation { cont in
            MPMediaLibrary.requestAuthorization { cont.resume(returning: $0) }
        }
        authorized = (status == .authorized)
        guard authorized else { running = false; return }

        pollTimer?.invalidate()
        player.beginGeneratingPlaybackNotifications()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(refresh),
                       name: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player)
        nc.addObserver(self, selector: #selector(refresh),
                       name: .MPMusicPlayerControllerPlaybackStateDidChange, object: player)

        // Notifications are flaky for cloud/catalog tracks that aren't in the
        // local library, so poll as a safety net. 5s is a reasonable tradeoff.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    @objc func refresh() {
        isPlaying = (player.playbackState == .playing)

        guard let item = player.nowPlayingItem else {
            track = nil
            artworkImage = nil
            return
        }

        let title = item.title ?? "Unknown Track"
        let artist = item.artist ?? item.albumArtist ?? "Unknown Artist"
        let album = item.albumTitle ?? ""

        // A live station such as Apple Music 1 reports the song it is playing,
        // with that song's real length, but no position: currentPlaybackTime is
        // NaN (seen 23 Sept 2026 on Apple Music 1, "the cure", length 297 s).
        // Sent as a length with the position stuck at 0, every push says "0
        // seconds in", and the receiver's progress bar snaps back to the start
        // on each heartbeat. So a station reports no length at all, which every
        // receiver already reads as "no progress bar", and says it is live.
        let position = player.currentPlaybackTime
        let live = !position.isFinite

        let jpeg = artwork(for: item, key: "\(title)|\(artist)|\(album)")
        artworkImage = jpeg == nil ? nil : artworkSource

        track = Track(
            title: title,
            artist: artist,
            album: album,
            duration: live ? 0 : Self.seconds(item.playbackDuration),
            elapsed: Self.seconds(position),
            storeID: item.playbackStoreID,
            artworkJPEG: jpeg,
            live: live
        )
    }

    /// Cover art for the current item, encoded once per track.
    ///
    /// Artwork for a cloud track can be nil on the first read and populated a
    /// moment later, so a nil result is cached as "not yet" rather than "none":
    /// the next poll tries again.
    private func artwork(for item: MPMediaItem, key: String) -> Data? {
        if artworkKey == key, let cached = artworkData { return cached }

        guard let image = item.artwork?.image(at: CGSize(width: 512, height: 512)),
              let jpeg = image.jpegData(compressionQuality: 0.8)
        else { return nil }

        artworkKey = key
        artworkData = jpeg
        artworkSource = image
        return jpeg
    }

    /// Live read, not the snapshot stored on `track`. Immediately after a
    /// track change this can still report the previous song's position, which
    /// is why PresenceController re-sends a correction a few seconds later.
    var liveElapsed: TimeInterval {
        Self.seconds(player.currentPlaybackTime)
    }

    /// A time from MediaPlayer that is safe to keep: non-finite becomes 0.
    ///
    /// A live station such as Apple Music 1 has no length and no fixed
    /// position, and MediaPlayer reports both as NaN. Passed through, that
    /// crashed the app: JSONSerialization can't write NaN and raises an
    /// Objective-C exception rather than throwing, so the `try?` around it in
    /// PresenceRelay never gets a chance. NaN also never equals itself, so a
    /// station's Track would never have compared equal to its own last reading.
    /// 0 is what every receiver already reads as "no progress bar".
    private static func seconds(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? value : 0
    }

    deinit {
        player.endGeneratingPlaybackNotifications()
    }
}
