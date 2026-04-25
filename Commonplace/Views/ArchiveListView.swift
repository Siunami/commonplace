import SwiftUI

/// Document-style list of every captured material in the archive. The
/// All-view's list mode renders this — a flat column of `MaterialListRow`s
/// in capture order (newest first, courtesy of the DB's `timestamp DESC`).
/// No date headers, no burst clusters, no "add to stack" pills per group:
/// the row's small `timeAgo` footer is the only temporal cue, mirroring
/// how an unnamed-stack list reads, so the All view is just "everything,
/// not yet sorted" as one document.
struct ArchiveListView: View {
    let highlights: [Highlight]
    let highlightNotes: [String: [HighlightNote]]
    let noteCounts: [String: Int]
    let onSelect: (Highlight) -> Void
    /// Fired as the user approaches the bottom so the host can paginate.
    /// `LazyVStack` reports `contentSize` based only on rendered rows, so
    /// the ScrollView-level geometry observer that drives the masonry's
    /// pagination never reliably fires here — the row-appearance hook is
    /// the dependable trigger.
    var onApproachEnd: () -> Void = {}

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(Array(highlights.enumerated()), id: \.element.id) { index, h in
                MaterialListRow(
                    highlight: h,
                    noteCount: noteCounts[h.id] ?? 0,
                    notes: highlightNotes[h.id] ?? [],
                    onRemove: nil,
                    onOpen: { onSelect(h) }
                )
                .id(h.id)
                .materialContextMenu(for: h)
                .onAppear {
                    if index >= highlights.count - 5 {
                        onApproachEnd()
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }
}
