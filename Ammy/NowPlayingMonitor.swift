import Foundation
import MediaPlayer
import os
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

    /// The cover, already JPEG-encoded: iOS's own artwork when it provides
    /// one, otherwise the catalog's, fetched by store ID (see
    /// NowPlayingMonitor.fetchFromCatalog), and nil while neither has one. It
    /// goes to the receiver too, so a receiver doesn't depend on the iTunes
    /// search index, which misses many smaller and independent releases.
    var artworkJPEG: Data?

    /// Playing from a live station, where there is no position to report.
    var live: Bool = false

    /// Marked explicit, the "E" Music shows beside the title. MediaPlayer's
    /// answer is a plain Bool, so false covers both a clean track and one it
    /// has no rating for — which is why PresenceRelay sends only a true.
    var explicit: Bool = false

    /// Identity for change detection — elapsed is excluded on purpose.
    var key: String { "\(title)|\(artist)|\(album)" }
}

@MainActor
final class NowPlayingMonitor: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    /// Starts as whatever iOS already has on record, read synchronously, so a
    /// launch with access granted never draws a frame that says otherwise.
    /// Starting at false made the access prompt at the top of the screen
    /// appear and vanish on every launch.
    @Published private(set) var authorized = MPMediaLibrary.authorizationStatus() == .authorized

    /// Where Media & Apple Music access stands, which decides what the access
    /// prompt at the top of the screen offers: the system's own question while
    /// it hasn't been asked, Settings once it has been refused, and nothing it
    /// can offer when Screen Time restricts it.
    @Published private(set) var access = MPMediaLibrary.authorizationStatus()

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

    /// A start that is waiting on the permission answer, which a second caller
    /// joins rather than skips.
    private var starting: Task<Void, Never>?

    /// Idempotent. The view starts the monitor when it appears and again on
    /// coming to the front, the access prompt starts it, and
    /// PresenceController.start() asks again for every session — including
    /// every Restart. Without the guard each of those added another pair of
    /// notification observers and another 5s timer on top of the last.
    ///
    /// A caller that arrives while another is still waiting for the permission
    /// answer waits for that same answer. It used to return at once, with
    /// `authorized` not yet set, and PresenceController took that as no access
    /// and quietly dropped the session it was starting.
    func start() async {
        if let starting {
            await starting.value
            return
        }
        guard !running else { return }
        let begin = Task { await self.begin() }
        starting = begin
        await begin.value
        starting = nil
    }

    private func begin() async {
        running = true

        let status: MPMediaLibraryAuthorizationStatus = await withCheckedContinuation { cont in
            MPMediaLibrary.requestAuthorization { cont.resume(returning: $0) }
        }
        access = status
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
            live: live,
            explicit: item.isExplicitItem
        )
    }

    /// Cover art for the current item, encoded once per track.
    ///
    /// Artwork for a cloud track can be nil on the first read and populated a
    /// moment later, so a nil result is cached as "not yet" rather than "none":
    /// the next poll tries again.
    private func artwork(for item: MPMediaItem, key: String) -> Data? {
        if artworkKey == key, let cached = artworkData { return cached }

        // iOS's own copy first: the size wanted, then whatever size the
        // artwork says it has, in case nothing it holds is as large as 512.
        if let art = item.artwork,
           let image = art.image(at: CGSize(width: 512, height: 512)) ?? art.image(at: art.bounds.size),
           let jpeg = image.jpegData(compressionQuality: 0.8) {
            remember(key: key, jpeg: jpeg, image: image)
            return jpeg
        }

        fetchFromCatalog(storeID: item.playbackStoreID, key: key)
        return nil
    }

    private func remember(key: String, jpeg: Data, image: UIImage) {
        artworkKey = key
        artworkData = jpeg
        artworkSource = image
    }

    // MARK: - The catalog, when iOS has no cover

    private static let log = Logger(subsystem: "com.local.ammy", category: "artwork")

    /// The track whose cover is being fetched from the catalog.
    private var catalogFetching: String?
    /// The last track the catalog couldn't cover. A final answer (not in the
    /// catalog, or no cover there) isn't asked again for that track; a failed
    /// request is, after `catalogRetry`.
    private var catalogFailed: (key: String, at: Date, final: Bool)?
    private static let catalogRetry: TimeInterval = 60

    /// Asks Apple's public catalog for the cover, by the song's store ID.
    ///
    /// iOS sometimes has no cover to give for a song streamed from Apple
    /// Music: the artwork object exists, but `image(at:)` returns nil,
    /// "especially when loading an artwork for the first time" (Apple
    /// Developer Forums thread 743898, several developers, no Apple reply or
    /// fix). Seen on 24 Sept 2026: "Handle (feat. Don Toliver)" showed an
    /// empty square in Ammy while the Lock Screen, which gets its cover
    /// another way, showed it, and other songs from the same album were fine.
    ///
    /// iTunes Lookup by store ID, as relay.py and Issun ask it for Discord's
    /// cover: an exact lookup, never a search by name, so it can't pick the
    /// wrong cover. No entitlement is needed. Local files have no store ID and
    /// nothing to look up.
    private func fetchFromCatalog(storeID: String, key: String) {
        let id = storeID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, id != "0", id != "-1", catalogFetching != key else { return }
        if let failed = catalogFailed, failed.key == key,
           failed.final || Date().timeIntervalSince(failed.at) < Self.catalogRetry {
            return
        }

        catalogFetching = key
        Self.log.notice("iOS has no cover for store id \(id, privacy: .public); asking the catalog")
        Task {
            let result = await Self.catalogCover(storeID: id)
            if catalogFetching == key { catalogFetching = nil }
            if case .failure(let failure) = result {
                Self.log.error("catalog cover for store id \(id, privacy: .public) failed: \(failure.description, privacy: .public)")
            }
            // A skip while this was in flight: the answer belongs to the song
            // before, so it goes nowhere, and it leaves the current song's
            // bookkeeping alone.
            guard track?.key == key else { return }
            switch result {
            case .success(let cover):
                catalogFailed = nil
                remember(key: key, jpeg: cover.jpeg, image: cover.image)
                refresh()
            case .failure(let failure):
                catalogFailed = (key, Date(), failure.final)
            }
        }
    }

    private struct CatalogFailure: Error, CustomStringConvertible {
        let description: String
        /// The catalog answered and the answer was no, so asking again for the
        /// same song won't change it.
        let final: Bool
    }

    private static func catalogCover(storeID: String) async -> Result<(jpeg: Data, image: UIImage), CatalogFailure> {
        // The device's region first, since an ID from one country's catalog
        // may not resolve in the lookup's default, the US. Then without a
        // country, the form relay.py and Issun use: the region is only a
        // stand-in for the Apple Music storefront, and the API refuses some
        // region codes outright (400 for "zz", checked 24 Sept 2026).
        var countries: [String?] = [nil]
        if let region = Locale.current.region?.identifier.lowercased() {
            countries.insert(region, at: 0)
        }
        var failure = CatalogFailure(description: "no lookup was made", final: false)
        for country in countries {
            switch await coverURL(storeID: storeID, country: country) {
            case .success(let url):
                return await download(url)
            case .failure(let why):
                failure = why
            }
        }
        return .failure(failure)
    }

    private static func coverURL(storeID: String, country: String?) async -> Result<URL, CatalogFailure> {
        var lookup = URLComponents(string: "https://itunes.apple.com/lookup")!
        lookup.queryItems = [
            URLQueryItem(name: "id", value: storeID),
            URLQueryItem(name: "entity", value: "song"),
        ]
        if let country {
            lookup.queryItems?.append(URLQueryItem(name: "country", value: country))
        }
        guard let url = lookup.url else {
            return .failure(.init(description: "couldn't build the lookup URL", final: true))
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                return .failure(.init(description: "lookup answered \(status)", final: (400..<500).contains(status)))
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (json["results"] as? [[String: Any]])?.first
            else { return .failure(.init(description: "not in the catalog", final: true)) }
            // Apple serves any size from the same path, as Issun relies on too.
            guard let small = first["artworkUrl100"] as? String, !small.isEmpty,
                  let cover = URL(string: small.replacingOccurrences(of: "100x100bb", with: "512x512bb"))
            else { return .failure(.init(description: "in the catalog, with no cover", final: true)) }
            return .success(cover)
        } catch {
            return .failure(.init(description: error.localizedDescription, final: false))
        }
    }

    private static func download(_ url: URL) async -> Result<(jpeg: Data, image: UIImage), CatalogFailure> {
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                return .failure(.init(description: "the cover answered \(status)", final: (400..<500).contains(status)))
            }
            guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.8) else {
                return .failure(.init(description: "the cover wasn't an image", final: true))
            }
            return .success((jpeg, image))
        } catch {
            return .failure(.init(description: error.localizedDescription, final: false))
        }
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
