import Foundation

/// Something that happened to the link, kept so it can be read later.
enum LinkEventKind: String, Codable {
    /// The session ended and will not come back on its own.
    case failed
    /// An established session lost the path and started reconnecting.
    case interrupted
    /// ...and got it back.
    case recovered

    var symbol: String {
        switch self {
        case .failed:      return "exclamationmark.triangle.fill"
        case .interrupted: return "arrow.clockwise"
        case .recovered:   return "checkmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .failed:      return "Failed"
        case .interrupted: return "Interrupted"
        case .recovered:   return "Recovered"
        }
    }
}

/// One entry.
///
/// `summary` is the same phrase the status row showed — `PushOutcome.summary`,
/// or one of the refusals caught before a request is made. Storing the phrase
/// rather than a code means the history, the row and the notification can
/// never describe the same event three different ways.
struct LinkEvent: Codable, Identifiable {
    let id: UUID
    let at: Date
    let kind: LinkEventKind
    let summary: String

    init(kind: LinkEventKind, summary: String, at: Date = Date()) {
        self.id = UUID()
        self.at = at
        self.kind = kind
        self.summary = summary
    }
}

/// A short, persistent record of what has happened to the link.
///
/// Persistent because of what it is for. The events worth reading are the ones
/// nobody was present for — the session that dropped at 3am while the phone
/// was in a pocket — and iOS may well kill the app before anyone opens it
/// again. A log that only lived in memory would reliably lose exactly the
/// entries it exists to keep.
@MainActor
final class EventLog: ObservableObject {

    /// More than anyone scrolls, and still small enough that writing the whole
    /// thing on every append costs nothing worth measuring. Interruptions are
    /// far more frequent than failures, so this fills faster than an
    /// errors-only log would — which is the trade for having one timeline.
    private static let limit = 100
    private static let key = "link_events"

    /// Newest first, so the view needs no sorting and the entry that matters
    /// is the one already on screen.
    @Published private(set) var entries: [LinkEvent] = []

    var failures: [LinkEvent] { entries.filter { $0.kind == .failed } }

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode([LinkEvent].self, from: data)
        else { return }
        entries = saved
    }

    func record(_ kind: LinkEventKind, summary: String) {
        entries.insert(LinkEvent(kind: kind, summary: summary), at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    /// Written on every change rather than at some tidy exit point, because
    /// there may not be one — see the note above about being killed.
    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
