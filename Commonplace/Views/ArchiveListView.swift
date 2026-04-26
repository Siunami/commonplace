import SwiftUI

/// Document-style list of every captured material in the archive. The
/// All-view's only mode renders this — a flat column grouped by calendar
/// day and, within each day, by **activity chunks**: runs of consecutive
/// captures separated by gaps small enough to read as one work session.
/// Per-row timestamps disappear; the chunk header carries the time
/// context, so the eye gets one timestamp per session instead of one per
/// item — far less visual noise on long scrolls.
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

    /// Memoised day + chunk decomposition. The grouping pass is O(N)
    /// over the page; held in @State so it only re-runs when the
    /// highlight set actually changes — not on every scroll tick.
    @State private var days: [ActivityDay] = []
    /// Trigger set for `onApproachEnd` — last-5 ids of the current
    /// page. Memoised so it doesn't allocate a Set on every parent
    /// re-render (which fires on every scroll tick).
    @State private var triggerIds: Set<String> = []

    var body: some View {
        // `pinnedViews: [.sectionHeaders]` is the load-bearing modifier:
        // each chunk's header pins to the top of the scroll while its
        // section is on screen, then scrolls UP and is replaced by the
        // next section's header as the user crosses a chunk boundary.
        // No separate sticky overlay is needed — the sticky behaviour
        // IS the section header, so there's nothing to duplicate.
        LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
            ForEach(days) { day in
                ForEach(day.chunks) { chunk in
                    Section {
                        ForEach(chunk.highlights) { h in
                            MaterialListRow(
                                highlight: h,
                                noteCount: noteCounts[h.id] ?? 0,
                                notes: highlightNotes[h.id] ?? [],
                                onRemove: nil,
                                onOpen: { onSelect(h) },
                                maxPrimaryLines: 6,
                                showsTimestamp: false
                            )
                            .id(h.id)
                            .materialContextMenu(for: h)
                            // Cross-pane drag source. Drop targets:
                            // `WorkspaceCanvasView` (creates a placement)
                            // and `StackBody` (adds membership).
                            .draggable(CanvasDragItem(kind: .highlight, id: h.id))
                            .onAppear {
                                if triggerIds.contains(h.id) { onApproachEnd() }
                            }
                        }
                    } header: {
                        sectionHeader(day: day, chunk: chunk)
                    }
                }
            }
        }
        .scrollTargetLayout()
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .onAppear { recomputeGroups() }
        .onChange(of: highlights.map(\.id)) { _, _ in recomputeGroups() }
    }

    private func recomputeGroups() {
        days = ActivityGrouping.group(highlights)
        triggerIds = Set(highlights.suffix(5).map(\.id))
    }

    // MARK: - Section header

    /// Combined sticky header for one chunk. Day label sits on the left,
    /// chunk's time-range on the right. Pinned via `pinnedViews:
    /// [.sectionHeaders]`, so as the user scrolls the next chunk's
    /// header slides UP through the pinned position and naturally
    /// replaces the previous one — the new label literally scrolls on
    /// top of the old. No separate sticky overlay is involved, so no
    /// duplication between an inline header and a top-bar copy.
    ///
    /// Day labels repeat across consecutive chunks within the same day
    /// (each chunk's header carries the day too). That's deliberate:
    /// when the day changes mid-scroll, the new chunk's header brings
    /// the new day label with it, completing the cross-fade.
    private func sectionHeader(day: ActivityDay, chunk: ActivityChunk) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 8) {
                Text(day.label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(UITokens.sectionLabelTracking)
                    .foregroundStyle(.secondary)
                Text("\(day.totalCount) \(day.totalCount == 1 ? "capture" : "captures")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                Text(chunk.label)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("\(chunk.count) \(chunk.count == 1 ? "item" : "items")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Translucent material so the rows scrolling beneath are faintly
        // visible — emphasises that the bar is sitting OVER the content,
        // not statically inserted between rows.
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Grouping

/// One calendar day's worth of captures, broken into activity chunks.
struct ActivityDay: Identifiable {
    let id: UUID
    let date: Date
    let chunks: [ActivityChunk]
    let label: String
    var totalCount: Int { chunks.reduce(0) { $0 + $1.highlights.count } }
}

/// A run of consecutive captures whose inter-arrival gaps are all
/// shorter than the chunk-break threshold. Reads as one work session.
struct ActivityChunk: Identifiable {
    let id: UUID
    let highlights: [Highlight]
    let label: String
    var count: Int { highlights.count }
}

enum ActivityGrouping {
    /// Inter-arrival gap (seconds) at or above which two consecutive
    /// captures belong to different chunks. 30 minutes = "I stepped
    /// away long enough that this is a new session." Tunable.
    static let chunkBreakSeconds: TimeInterval = 30 * 60

    /// Group highlights (newest-first) into days, then activity chunks
    /// within each day. A new chunk starts whenever the gap between two
    /// consecutive items exceeds `chunkBreakSeconds`.
    static func group(_ highlights: [Highlight]) -> [ActivityDay] {
        guard !highlights.isEmpty else { return [] }

        let calendar = Calendar.current

        // Day buckets — preserve newest-first ordering.
        var dayBuckets: [(date: Date, items: [Highlight])] = []
        for h in highlights {
            let day = calendar.startOfDay(for: h.date)
            if let last = dayBuckets.last, last.date == day {
                dayBuckets[dayBuckets.count - 1].items.append(h)
            } else {
                dayBuckets.append((day, [h]))
            }
        }

        return dayBuckets.map { bucket in
            ActivityDay(
                id: UUID(),
                date: bucket.date,
                chunks: chunkize(bucket.items),
                label: dayLabel(for: bucket.date)
            )
        }
    }

    /// Slice a day's items (newest-first) into activity chunks. Walks
    /// adjacent pairs and breaks whenever `previous.timestamp -
    /// current.timestamp > chunkBreakSeconds`.
    private static func chunkize(_ items: [Highlight]) -> [ActivityChunk] {
        var chunks: [ActivityChunk] = []
        var current: [Highlight] = []
        var previous: Highlight?

        for h in items {
            if let p = previous {
                let gap = p.timestamp - h.timestamp
                if gap > chunkBreakSeconds, !current.isEmpty {
                    chunks.append(makeChunk(from: current))
                    current = []
                }
            }
            current.append(h)
            previous = h
        }
        if !current.isEmpty {
            chunks.append(makeChunk(from: current))
        }
        return chunks
    }

    private static func makeChunk(from items: [Highlight]) -> ActivityChunk {
        let label: String
        if items.count == 1 {
            label = ActivityGrouping.timeFormatter.string(from: items[0].date)
        } else {
            // Newest-first inside the chunk: items.first is end-time of
            // the session, items.last is start-time.
            let start = ActivityGrouping.timeFormatter.string(from: items.last!.date)
            let end = ActivityGrouping.timeFormatter.string(from: items.first!.date)
            label = "\(start) – \(end)"
        }
        return ActivityChunk(id: UUID(), highlights: items, label: label)
    }

    private static func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return ActivityGrouping.dayFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()
}
