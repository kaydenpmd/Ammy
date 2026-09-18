import SwiftUI

/// What has happened to the link, newest first.
///
/// One timeline rather than two screens. A disconnect that healed and a
/// session that ended are the same question — what happened to my connection,
/// and when — and the answer reads better interleaved than split in half,
/// because the useful thing is usually whether one lines up with the other.
/// Interruptions are much the more frequent, so the filter exists to stop them
/// burying the events that actually needed a person.
struct LinkHistoryView: View {
    @EnvironmentObject private var controller: PresenceController
    @State private var failuresOnly = false

    private var entries: [LinkEvent] {
        failuresOnly ? controller.events.failures : controller.events.entries
    }

    var body: some View {
        Group {
            if controller.events.entries.isEmpty {
                ContentUnavailableView(
                    "Nothing Yet",
                    systemImage: "checkmark.circle",
                    description: Text("Disconnects and failures will be listed here.")
                )
            } else {
                List {
                    // Clear background so the segmented control isn't sitting
                    // in a second card of its own, but the default row insets
                    // stay — stripping them to zero ran the picker's own
                    // rectangular frame flush into the section's rounded top
                    // corner, flattening it. The corner is the section's to
                    // round; a row's content shouldn't be touching it.
                    Picker("Show", selection: $failuresOnly) {
                        Text("All").tag(false)
                        Text("Failures").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)

                    ForEach(entries) { entry in
                        LinkEventRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !controller.events.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) {
                        controller.events.clear()
                    }
                }
            }
        }
    }
}

private struct LinkEventRow: View {
    let entry: LinkEvent

    private var tint: Color {
        switch entry.kind {
        case .failed:      return .red
        case .interrupted: return .secondary
        case .recovered:   return .green
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.kind.symbol)
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.summary)
                // Absolute rather than relative: "2 hours ago" reads well for
                // the newest entry and badly for every other one, and the
                // question here is usually whether something lines up with
                // something else that happened.
                Text(entry.at.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
