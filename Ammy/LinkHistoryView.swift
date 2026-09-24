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
                    Section {
                        ForEach(entries) { entry in
                            LinkEventRow(entry: entry)
                        }
                    } header: {
                        // The filter is the section's header, not its first row.
                        // As a row with a clear background it owned the section's
                        // rounded top: the visible card then began at the second
                        // row, with square corners and a separator line along its
                        // top, under a gap the invisible row took up. The owner
                        // called it weird on 24 Sept 2026. A header sits above
                        // the card, so the card rounds its own corners, and the
                        // cell's corner mask, which flattened the picker when it
                        // was a zero-inset row, doesn't reach a header.
                        //
                        // Zero horizontal insets give it the card's full width.
                        // Only the horizontal ones: zeroing all four (build 109)
                        // also removed the system's gap between a header and its
                        // card, and the switch sat on the card's top edge. The
                        // per-edge form, iOS 26, leaves the system's own vertical
                        // spacing in place. The HIG's segmented-control page
                        // gives no placement for iOS.
                        Picker("Show", selection: $failuresOnly) {
                            Text("All").tag(false)
                            Text("Failures").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .listRowInsets(.horizontal, 0)
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
