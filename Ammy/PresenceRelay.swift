import Foundation

/// Ships now-playing state to the desktop relay. Replaces the old Gateway
/// client — the phone no longer talks to Discord at all.
actor PresenceRelay {
    private let endpoint: URL
    private let key: String
    private let session: URLSession

    /// Track whose cover the relay has already been given. The JPEG is ~80 KB
    /// and the heartbeat fires every 30 seconds, so sending it every time would
    /// be about 10 MB an hour for one unchanging image. The relay stores it on
    /// disk under a hash of the track and reuses it, so once is enough.
    private var artworkSentFor: String?

    /// The address Ammy will actually send to, or nil if the text can't be one.
    ///
    /// The scheme is the app's business, not the person's — there is exactly one
    /// valid answer, so requiring them to type it only creates a way to get it
    /// wrong. But *silently* rewriting what someone typed is its own problem, so
    /// this is exposed rather than buried in the initialiser: the UI asks before
    /// adding anything, and stores the result, so the change is visible once and
    /// never repeated.
    static func normalised(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate),
              url.scheme == "https",
              url.host?.isEmpty == false
        else { return nil }

        return url
    }

    /// True when `raw` would have a scheme added to it.
    static func needsScheme(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("://")
    }

    init?(endpoint: String, key: String) {
        guard let url = Self.normalised(endpoint) else { return nil }
        self.endpoint = url
        self.key = key

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10

        // Waiting for connectivity is the wrong trade for a heartbeat. While a
        // request waits, timeoutIntervalForRequest does not apply to it and the
        // only ceiling is timeoutIntervalForResource, which defaults to seven
        // days — so a push aimed at a sleeping relay simply never returns, and
        // everything that awaits one stops with it. Failing is the better
        // outcome here: "Endpoint Unreachable" is a state this app is built to
        // show, and the next heartbeat is thirty seconds away regardless.
        config.waitsForConnectivity = false

        // A ceiling on the whole request, whatever the reason it is slow.
        // GUESS: 20 — chosen to sit under the 30s heartbeat so requests can't
        // pile up on each other, while leaving room for the ~107 KB an artwork
        // push carries. Not from documentation.
        config.timeoutIntervalForResource = 20

        self.session = URLSession(configuration: config)
    }

    @discardableResult
    func push(track: Track?, playing: Bool, diag: PushDiagnostics? = nil) async -> Bool {
        // The relay stamps this onto every uptime entry. Whether the app
        // survives backgrounding is decided by code in *this* build, so the
        // build number is the axis worth attributing gaps to — without it the
        // log can't tell a regression from ordinary noise.
        var body: [String: Any] = [
            "playing": playing && track != nil,
            "app_version": Bundle.main.displayVersion,
        ]

        // The app cannot report its own death, so every push carries a snapshot
        // of its condition and the relay keeps the most recent one. When the
        // pushes stop, that snapshot is the only account of what was happening
        // beforehand — see PushDiagnostics here and note_silence() in relay.py.
        if let diag {
            body["diag"] = diag.dictionary
        }

        // Set only when this push actually carries the cover, so a failed
        // request doesn't mark it delivered.
        var artworkAttachedFor: String?

        if let track, playing {
            body["title"] = track.title
            body["artist"] = track.artist
            body["album"] = track.album
            body["duration"] = track.duration
            body["elapsed"] = track.elapsed

            // "0" is what local files report; the relay ignores it anyway, but
            // there's no point sending a value that can't resolve.
            if !track.storeID.isEmpty && track.storeID != "0" {
                body["store_id"] = track.storeID
            }

            if artworkSentFor != track.key, let jpeg = track.artworkJPEG {
                body["artwork_b64"] = jpeg.base64EncodedString()
                artworkAttachedFor = track.key
            }
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Absent rather than empty when unset: "no key configured" is a clearer
        // signal to a receiver than a header with nothing after it.
        if !key.isEmpty {
            req.setValue(key, forHTTPHeaderField: "X-Relay-Key")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (_, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse
        else { return false }

        let ok = (200..<300).contains(http.statusCode)
        if ok, let delivered = artworkAttachedFor {
            artworkSentFor = delivered
        }
        return ok
    }
}
