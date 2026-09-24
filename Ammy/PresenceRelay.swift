import Foundation

/// A failure as the person meets it.
///
/// `summary` is the short label History lists it under. `explanation` is what
/// the popup and the notification say: what probably went wrong, and what to
/// check. Both used to be the one short label, and on 24 Sept 2026 the owner
/// pointed out what that costs — "all i see is 'secure connection failed.'"
/// That was accurate, and no help to someone whose receiver had become
/// unreachable behind a tunnel whose public edge still took the connection.
struct FailureNotice: Equatable {
    let summary: String
    let explanation: String
}

/// What became of a push.
///
/// Replaces a bare `Bool`, which flattened a rejected key, a wrong path, a
/// sleeping PC and a dropped wi-fi handover into one bit and left the app
/// unable to say anything more useful than that it hadn't worked.
enum PushOutcome {
    case delivered

    /// The far end answered and refused. `fromRelay` distinguishes an answer
    /// from the relay itself from one produced by something in front of it:
    /// Tailscale Funnel returns its own 404 when the hostname resolves but
    /// nothing is served on that port, which is the same status the relay
    /// sends for a wrong path. The relay stamps every response with
    /// `X-Ammy-Relay`; nothing else does.
    case refused(status: Int, fromRelay: Bool)

    /// No answer at all.
    case unreachable(URLError.Code)

    var delivered: Bool {
        if case .delivered = self { return true }
        return false
    }

    /// Title of every failure the person is told about, popup and
    /// notification alike. It used to be "Ammy Stopped", which named the same
    /// event less precisely: every one of these is the connection failing, and
    /// "stopped" read like the app itself had died — which is a different
    /// event, with its own notice ("Ammy isn't running").
    static let failureTitle = "Connection Failed"

    var notice: FailureNotice {
        FailureNotice(summary: summary, explanation: explanation)
    }

    /// Short enough for a History row, specific enough to tell failures
    /// apart. Title case, like the rest of that list.
    var summary: String {
        switch self {
        case .delivered:
            return "Connected"

        case .refused(status: 401, fromRelay: _), .refused(status: 403, fromRelay: _):
            return "Key Rejected"
        case .refused(status: 404, fromRelay: true):
            return "Wrong Path"
        case .refused(status: 404, fromRelay: false):
            return "Nothing at That Address"
        // Only a 5xx carrying X-Ammy-Relay is known to be the receiver's own.
        // Without it, the answer could come from something in front — Funnel
        // answers 502 when the PC is up but nothing is listening — or from a
        // receiver that simply doesn't send the header, which is any receiver
        // but relay.py and Issun. It can't say which, so it doesn't guess.
        // "Receiver", not "Relay": the text a person reads stays
        // receiver-agnostic (CLAUDE.md, "What Ammy is").
        case .refused(status: let status, fromRelay: true) where (500..<600).contains(status):
            return "Receiver Error \(status)"
        case .refused(status: let status, fromRelay: false) where (500..<600).contains(status):
            return "Server Error \(status)"
        case .refused(status: let status, fromRelay: _):
            return "Refused (\(status))"

        case .unreachable(.notConnectedToInternet):
            return "No Internet"
        case .unreachable(.dataNotAllowed):
            return "Cellular Data Off"
        case .unreachable(.timedOut):
            return "Timed Out"
        case .unreachable(.cannotFindHost), .unreachable(.dnsLookupFailed):
            return "Address Not Found"
        case .unreachable(.cannotConnectToHost):
            return "Connection Refused"
        case .unreachable(.networkConnectionLost):
            return "Connection Lost"
        // Was "Secure Connection Failed", which read like a certificate fault.
        // It almost never is one: see the explanation below.
        case .unreachable(.secureConnectionFailed):
            return "Connection Cut Off"
        case .unreachable(.serverCertificateUntrusted),
             .unreachable(.serverCertificateHasBadDate),
             .unreachable(.serverCertificateNotYetValid),
             .unreachable(.serverCertificateHasUnknownRoot):
            return "Certificate Not Trusted"
        case .unreachable(.cannotDecodeRawData):
            return "Couldn't Send"
        case .unreachable:
            return "Connection Failed"
        }
    }

    /// What went wrong in words someone can act on: the likely cause, then
    /// what to check. Shown under the popup's title and in the notification,
    /// each of which adds how to try again, since that differs between them.
    ///
    /// "The receiver" throughout, never a product: Ammy posts to an address
    /// and doesn't know what answers it (CLAUDE.md, "What Ammy is").
    var explanation: String {
        switch self {
        case .delivered:
            return "Connected."

        // A 401 is also what a receiver with no key of its own set answers
        // (Issun refuses everything then), and an empty Key sends no header at
        // all — so this names all three rather than blaming Ammy's copy.
        case .refused(status: 401, fromRelay: _), .refused(status: 403, fromRelay: _):
            return "The receiver refused Ammy's key, or wanted one and didn't get it. Check that the Key here matches the one set on the receiver."
        case .refused(status: 404, fromRelay: true):
            return "The receiver is running, but not at that path. Check the end of the URL."
        // Tailscale Funnel's own 404 when nothing is served behind the name,
        // or a receiver that doesn't identify itself saying the path is wrong.
        // The words fit both, since Ammy can't tell them apart.
        case .refused(status: 404, fromRelay: false):
            return "The address answered, but nothing there took the update. Check the URL, including the end of it, and that the receiver is running."
        case .refused(status: let status, fromRelay: true) where (500..<600).contains(status):
            return "The receiver ran into a problem of its own (error \(status)). Its log should say what."
        case .refused(status: let status, fromRelay: false) where (500..<600).contains(status):
            return "The address answered with an error (\(status)). If a tunnel or proxy forwards to the receiver, the receiver may have stopped or the device it runs on may be asleep. Otherwise the receiver's log should say why."
        case .refused(status: let status, fromRelay: _):
            return "The receiver refused the update (error \(status))."

        // iOS reports cellular data switched off for Ammy alone under this
        // code too, not under dataNotAllowed (Apple DTS, developer forums
        // threads 685814 and 81350), so both causes are named.
        case .unreachable(.notConnectedToInternet):
            return "This device isn't online, or Ammy isn't allowed to use cellular data. Join Wi-Fi, or turn on cellular data for Ammy in Settings › Cellular."
        // Roaming, or cellular data off for the whole device.
        case .unreachable(.dataNotAllowed):
            return "Cellular data isn't available right now, for example because Data Roaming is off. Join Wi-Fi, or check Settings › Cellular."
        case .unreachable(.timedOut):
            return "The receiver didn't answer in time. The device it runs on may be off, asleep or offline."
        // Also the last word after twenty minutes of retrying an address that
        // was working, where a typo can't be the reason.
        case .unreachable(.cannotFindHost), .unreachable(.dnsLookupFailed):
            return "Ammy couldn't look up that address. If it has never worked, check the URL for typos. If it was working, the address may no longer be published, or this network may be having trouble."
        case .unreachable(.cannotConnectToHost):
            return "The device at that address turned the connection away. The receiver may not be running."
        case .unreachable(.networkConnectionLost):
            return "The connection dropped partway through, which often happens when switching between Wi-Fi and cellular."
        // Measured 24 Sept 2026: with Funnel's route to the PC broken, Funnel's
        // public edge accepted the connection and dropped it mid-handshake —
        // five US cities saw exactly this — and iOS files that under
        // secureConnectionFailed. So the likely story is an unreachable
        // receiver, not a certificate.
        case .unreachable(.secureConnectionFailed):
            return "The connection was cut off before it could be secured. That usually means the receiver can't be reached right now: the device it runs on may be offline, or whatever forwards to it may be down."
        case .unreachable(.serverCertificateUntrusted),
             .unreachable(.serverCertificateHasBadDate),
             .unreachable(.serverCertificateNotYetValid),
             .unreachable(.serverCertificateHasUnknownRoot):
            return "The address's security certificate isn't valid, so Ammy won't send to it. Check the URL, and that this device's date and time are right."
        // PresenceRelay.push() returns this when the body won't encode, which
        // is Ammy's fault and not the network's.
        case .unreachable(.cannotDecodeRawData):
            return "Ammy couldn't turn this song's details into a message, which is a bug in Ammy. Playing a different song should get past it."
        case .unreachable(let code):
            return "Ammy couldn't reach the receiver (error \(code.rawValue))."
        }
    }
}

/// Ships now-playing state to the desktop relay. Replaces the old Gateway
/// client — the phone no longer talks to Discord at all.
actor PresenceRelay {

    /// Set by the relay on every response. Its presence is the only reliable
    /// way to tell the relay's own reply from one made on its behalf.
    private static let relayHeader = "X-Ammy-Relay"
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
        // outcome here: "Connection Failed" is a state this app is built to
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
    func push(track: Track?, playing: Bool, diag: PushDiagnostics? = nil) async -> PushOutcome {
        // The relay stamps this onto every uptime entry. Whether the app
        // survives backgrounding is decided by code in *this* build, so the
        // build number is the axis worth attributing gaps to — without it the
        // log can't tell a regression from ordinary noise.
        var body: [String: Any] = [
            "playing": playing && track != nil,
            "app_version": Bundle.main.displayVersion,
            // Who is sending, beside which build: a receiver can then show
            // "Ammy 1.0 (97)" rather than a bare number. A fact about this app,
            // not about any receiver, so it keeps Ammy receiver-agnostic.
            "app_name": Bundle.main.displayName,

            // Lets the relay tell a late-arriving push from a newer one. Each
            // push is its own independent Task with no ordering guarantee
            // against the others, so the farewell from stop() (playing:
            // false) can land after an in-flight now-playing push that was
            // already sent, and relay.py used to just apply whatever arrived
            // last. Milliseconds since epoch rather than an incrementing
            // counter: a counter resets to 0 on every relaunch, and the relay
            // would then reject every push from the new process as "older"
            // than whatever high number the last one reached. A wall clock
            // only needs the device clock not to run backwards, which a
            // counter can't promise across a cold start.
            "seq": Int(Date().timeIntervalSince1970 * 1000),
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
            // Only present for a live station, whose duration is sent as 0:
            // lets a receiver tell "live" from "length unknown" if it cares.
            if track.live {
                body["live"] = true
            }
            // Only present when the device says so, the same way. A false from
            // MediaPlayer can mean "no rating" as easily as "clean", so sending
            // it would be a claim the phone can't make; left out, a receiver
            // that can look the track up is free to find out for itself.
            if track.explicit {
                body["explicit"] = true
            }

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
        // isValidJSONObject first, because data(withJSONObject:) doesn't throw
        // on a NaN or infinite number: it raises an Objective-C exception that
        // `try?` can't catch, and the app dies. Live stations used to reach it
        // that way (see NowPlayingMonitor.seconds). A body that can't be encoded
        // fails the push like any other, instead of ending the process.
        guard JSONSerialization.isValidJSONObject(body),
              let json = try? JSONSerialization.data(withJSONObject: body)
        else {
            return .unreachable(.cannotDecodeRawData)
        }
        req.httpBody = json

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: req)
        } catch let error as URLError {
            return .unreachable(error.code)
        } catch {
            return .unreachable(.unknown)
        }

        guard let http = response as? HTTPURLResponse else {
            return .unreachable(.badServerResponse)
        }

        guard (200..<300).contains(http.statusCode) else {
            return .refused(
                status: http.statusCode,
                fromRelay: http.value(forHTTPHeaderField: Self.relayHeader) != nil
            )
        }

        if let delivered = artworkAttachedFor {
            artworkSentFor = delivered
        }
        return .delivered
    }
}
