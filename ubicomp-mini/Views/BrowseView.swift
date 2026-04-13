import SwiftUI
import AVKit
import Combine
import UniformTypeIdentifiers
import PDFKit
import Quartz
import QuickLookThumbnailing

// MARK: - Shared design tokens

enum UITokens {
    static let tagFont: Font = .system(size: 11, weight: .medium)
    static let tagHPad: CGFloat = 8
    static let tagVPad: CGFloat = 3
    static let sectionLabelFont: Font = .system(size: 10, weight: .semibold)
    static let sectionLabelTracking: CGFloat = 0.8
    static let sectionSpacing: CGFloat = 20
    static let chipFill = Color.primary.opacity(0.06)
    static let chipBorder = Color.primary.opacity(0.1)
    static let linkColor = Color.primary.opacity(0.78)
    static let linkHoverColor = Color.primary
}

struct ChipBackground: ViewModifier {
    var dashed: Bool = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, UITokens.tagHPad)
            .padding(.vertical, UITokens.tagVPad)
            .background(Capsule().fill(dashed ? Color.clear : UITokens.chipFill))
            .overlay(
                Capsule().strokeBorder(
                    UITokens.chipBorder,
                    style: StrokeStyle(lineWidth: 0.5, dash: dashed ? [2, 2] : [])
                )
            )
    }
}

extension View {
    func chipBackground(dashed: Bool = false) -> some View {
        modifier(ChipBackground(dashed: dashed))
    }
}

struct TagChip: View {
    let name: String
    var onRemove: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(UITokens.tagFont)
                .foregroundStyle(onTap != nil && isHovered ? Color.accentColor : .secondary)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .chipBackground()
        .contentShape(Capsule())
        .onTapGesture {
            onTap?()
        }
        .onHover { hovering in
            guard onTap != nil else { return }
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(UITokens.sectionLabelFont)
            .tracking(UITokens.sectionLabelTracking)
            .foregroundStyle(.tertiary)
    }
}

struct FlatTag: View {
    let name: String
    var onRemove: (() -> Void)?
    var onTap: (() -> Void)?
    @State private var isHovered = false

    private var labelColor: Color {
        if onTap != nil && isHovered { return Color.accentColor }
        return isHovered ? Color.primary.opacity(0.85) : Color.primary.opacity(0.55)
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("#\(name)")
                .font(.system(size: 12))
                .foregroundStyle(labelColor)
            if isHovered, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
            guard onTap != nil else { return }
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

struct InlineLink: View {
    let text: String
    let url: String
    var onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                Text(text)
                    .underline(isHovered, color: UITokens.linkHoverColor)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(isHovered ? UITokens.linkHoverColor : UITokens.linkColor)
        }
        .buttonStyle(.plain)
        .help(url)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

struct OCRTextBlock: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SectionLabel(text: "Extracted text")
                Spacer()
                Button(action: { withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() } }) {
                    HStack(spacing: 3) {
                        Text(expanded ? "Show less" : "Show more")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(expanded ? nil : 3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

struct NoteRow: View {
    let note: HighlightNote
    var onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.body)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(CardMetadata.timeAgo(from: note.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                // Accent bar as an overlay so it hugs the text block exactly —
                // putting it as an HStack sibling let SwiftUI add slack.
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.orange.opacity(0.85))
                    .frame(width: 2.5)
            }

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.primary.opacity(0.05)))
                    .opacity(isHovered ? 1 : 0)
            }
            .buttonStyle(.plain)
            .help("Delete note")
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

struct BrowseView: View {

    // MARK: - State

    @State private var isActive = false
    @State private var searchText = ""
    @State private var selectedHighlight: Highlight?
    @State private var highlights: [Highlight] = []
    @State private var highlightsOffset = 0
    @State private var noteCounts: [String: Int] = [:]
    @State private var highlightTags: [String: [Tag]] = [:]
    @State private var selectedFilter: CaptureFilter = .all
    @State private var selectedApp: String? = nil
    @State private var selectedTagIds: Set<String> = []
    @State private var appFacets: [AppFacet] = []
    @State private var allTags: [Tag] = []
    @State private var tagCounts: [String: Int] = [:]
    // Scroll position managed by SwiftUI's default behavior
    @State private var typeCounts: [String: Int] = [:]
    @State private var isDropTargeted = false
    @State private var pinnedOrigin: PinnedOrigin? = nil
    @State private var showSettings = false
    private let pageSize = 200

    // MARK: - Pinned origin (navigation breadcrumb)

    struct PinnedOrigin: Equatable {
        let highlight: Highlight
        let targetTagId: String

        static func == (lhs: PinnedOrigin, rhs: PinnedOrigin) -> Bool {
            lhs.highlight.id == rhs.highlight.id && lhs.targetTagId == rhs.targetTagId
        }
    }

    private func navigateToTag(from origin: Highlight, tag: Tag) {
        // Dismiss detail view (if currently open).
        selectedHighlight = nil
        // Remember where we came from so we can pin it.
        pinnedOrigin = PinnedOrigin(highlight: origin, targetTagId: tag.id)
        // Switch the sidebar filter to this single tag (mutually exclusive
        // with type/app per the single-select sidebar logic).
        selectedTagIds = [tag.id]
        selectedFilter = .all
        selectedApp = nil
        searchText = ""
        // Reload captures so the filtered view is fresh.
        loadCaptures(reset: true)
    }

    @ViewBuilder
    private func pinnedOriginRow(_ pinned: PinnedOrigin) -> some View {
        let tagName = allTags.first(where: { $0.id == pinned.targetTagId })?.name ?? "collection"
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    Text("From this capture → #\(tagName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                MasonryCard(
                    highlight: pinned.highlight,
                    noteCount: noteCounts[pinned.highlight.id] ?? 0,
                    cardTags: highlightTags[pinned.highlight.id] ?? [],
                    onTagTap: { tag in
                        navigateToTag(from: pinned.highlight, tag: tag)
                    }
                )
                .frame(width: 240)
                .onTapGesture { selectedHighlight = pinned.highlight }
            }

            Spacer()

            Button(action: { pinnedOrigin = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Unpin")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color.accentColor.opacity(0.04))
    }

    // MARK: - Computed

    private var filteredHighlights: [Highlight] {
        var result = highlights
        if let type = selectedFilter.highlightType {
            result = result.filter { $0.highlightType == type }
        }
        if let app = selectedApp {
            result = result.filter { $0.sourceApp == app }
        }
        if !selectedTagIds.isEmpty {
            result = result.filter { h in
                guard let tags = highlightTags[h.id] else { return false }
                return tags.contains { selectedTagIds.contains($0.id) }
            }
        }
        // Exclude the pinned-origin highlight from the in-flow list so it only
        // shows once (as the pinned card above the masonry).
        if let pinned = pinnedOrigin {
            result = result.filter { $0.id != pinned.highlight.id }
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            CaptureFilterSidebar(
                appFacets: appFacets,
                allTags: allTags,
                tagCounts: tagCounts,
                typeCounts: typeCounts,
                selectedApp: $selectedApp,
                selectedFilter: $selectedFilter,
                selectedTagIds: $selectedTagIds,
                searchText: $searchText,
                showSettings: $showSettings,
                onSearch: { performSearch() }
            )
            .onChange(of: selectedApp) { _, _ in
                guard isActive else { return }
                pinnedOrigin = nil
                loadCaptures(reset: true)
            }
            .onChange(of: selectedFilter) { _, _ in
                guard isActive else { return }
                pinnedOrigin = nil
                loadCaptures(reset: true)
            }
            .onChange(of: selectedTagIds) { _, newValue in
                // Clear the pin whenever the tag filter is changed through any
                // path other than navigateToTag() — in navigateToTag the new
                // Set always matches the pin's target id so this is a no-op.
                if let pinned = pinnedOrigin, newValue != Set([pinned.targetTagId]) {
                    pinnedOrigin = nil
                }
            }
            .onChange(of: searchText) { _, newValue in
                guard isActive else { return }
                if newValue.isEmpty { loadCaptures(reset: true) }
            }

            Divider()

            if showSettings {
                ScrollView {
                    SettingsView()
                        .frame(maxWidth: 500)
                        .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {

            VStack(spacing: 0) {
                // Breadcrumb: pinned origin from a tag navigation
                if let pinned = pinnedOrigin {
                    pinnedOriginRow(pinned)
                    Divider()
                }

                if filteredHighlights.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "tray")
                            .font(.system(size: 36))
                            .foregroundStyle(.quaternary)
                        Text("No captures yet")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        VStack(spacing: 4) {
                            Text("Cmd+Shift+3 — screenshot")
                            Text("Cmd+Shift+4 — region capture")
                            Text("Cmd+Shift+5 — screen recording")
                            Text("Copy text anywhere — auto-captured")
                            Text("Drop files here to import")
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        MasonryLayout(minColumnWidth: 260, spacing: 12) {
                            ForEach(filteredHighlights) { highlight in
                                MasonryCard(
                                    highlight: highlight,
                                    noteCount: noteCounts[highlight.id] ?? 0,
                                    cardTags: highlightTags[highlight.id] ?? [],
                                    onTagTap: { tag in
                                        navigateToTag(from: highlight, tag: tag)
                                    }
                                )
                                .id(highlight.id)
                                .onTapGesture { selectedHighlight = highlight }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)

                        if highlightsOffset > 0 && highlightsOffset % pageSize == 0 {
                            Button(action: { loadCaptures(reset: false) }) {
                                Text("Load more")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // scrollPosition removed — round-robin layout is deterministic
                }

                Divider()
                HStack {
                    Text("\(filteredHighlights.count) captures")
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL, .item], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                        .background(Color.accentColor.opacity(0.08))
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.down.on.square")
                                    .font(.system(size: 36, weight: .regular))
                                    .foregroundStyle(Color.accentColor)
                                Text("Drop to add to captures")
                                    .font(.headline)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }

            } // end else (showSettings)
        }
        .onAppear {
            isActive = true
            loadCaptures(reset: true)
            refreshSidebarData()
        }
        .onDisappear { isActive = false }
        .onReceive(NotificationCenter.default.publisher(for: BrowseWindowController.windowDidShowNotification)) { _ in
            isActive = true
            loadCaptures(reset: true)
            refreshSidebarData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .highlightDidSave).throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)) { _ in
            guard isActive else { return }
            loadCaptures(reset: true)
            refreshSidebarData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .highlightDataDidChange).receive(on: DispatchQueue.main)) { notification in
            guard isActive else { return }
            let userInfo = notification.userInfo ?? [:]
            let hid = userInfo["highlightId"] as? String
            let change = userInfo["change"] as? String ?? ""

            // Targeted refresh for the affected highlight's cached state.
            if let hid {
                switch change {
                case "tags":
                    highlightTags[hid] = DatabaseManager.shared.tagsForHighlight(id: hid)
                case "notes":
                    let counts = DatabaseManager.shared.noteCountsForHighlights(ids: [hid])
                    noteCounts[hid] = counts[hid] ?? 0
                    // The userNote strip on the masonry card reads from highlight.userNote,
                    // which changes when a note is added/removed — refetch that row too.
                    if let updated = DatabaseManager.shared.highlight(byId: hid),
                       let idx = highlights.firstIndex(where: { $0.id == hid }) {
                        highlights[idx] = updated
                    }
                case "userNote":
                    if let updated = DatabaseManager.shared.highlight(byId: hid),
                       let idx = highlights.firstIndex(where: { $0.id == hid }) {
                        highlights[idx] = updated
                    }
                default:
                    break
                }
            }

            // Sidebar counts + allTags always refresh — both are cheap indexed scans.
            refreshSidebarData()

            // If the user is actively filtering by a tag AND a tag-level change
            // happened, re-run the query so items drop in/out of the filtered set.
            if change == "tags" && !selectedTagIds.isEmpty {
                loadCaptures(reset: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: BrowseWindowController.showSettingsNotification)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: BrowseWindowController.showHighlightDetailNotification)) { notification in
            guard let highlightId = notification.userInfo?["highlightId"] as? String,
                  let highlight = DatabaseManager.shared.highlight(byId: highlightId) else { return }
            // Reset sidebar to "All" so the item is visible in the background list
            // once the detail overlay is dismissed.
            selectedFilter = .all
            selectedApp = nil
            selectedTagIds = []
            searchText = ""
            isActive = true
            loadCaptures(reset: true)
            selectedHighlight = highlight
        }
        .overlay {
            if let highlight = selectedHighlight {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { selectedHighlight = nil }

                    CardDetailView(
                        highlight: highlight,
                        onDismiss: { selectedHighlight = nil },
                        onTagNavigation: { origin, tag in
                            navigateToTag(from: origin, tag: tag)
                        }
                    )
                        .frame(maxWidth: 700, maxHeight: .infinity)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 5)
                        .padding(40)
                }
                .transition(.opacity)
                .onExitCommand { selectedHighlight = nil }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedHighlight != nil)
    }

    // MARK: - Data Loading

    private func loadCaptures(reset: Bool) {
        guard isActive else { return }
        if reset { highlightsOffset = 0; highlights = [] }

        let batch: [Highlight]
        if !searchText.isEmpty {
            batch = DatabaseManager.shared.searchAll(query: searchText)
            highlights = batch
            highlightsOffset = batch.count
        } else if selectedFilter.isAnnotatedFilter {
            batch = DatabaseManager.shared.annotatedHighlightsPaginated(
                offset: highlightsOffset, limit: pageSize
            )
            highlights.append(contentsOf: batch)
            highlightsOffset += batch.count
        } else if let app = selectedApp {
            batch = DatabaseManager.shared.highlightsForApp(
                sourceApp: app, offset: highlightsOffset, limit: pageSize
            )
            highlights.append(contentsOf: batch)
            highlightsOffset += batch.count
        } else {
            batch = DatabaseManager.shared.allHighlightsPaginated(
                offset: highlightsOffset, limit: pageSize
            )
            highlights.append(contentsOf: batch)
            highlightsOffset += batch.count
        }

        let newCounts = DatabaseManager.shared.noteCountsForHighlights(ids: batch.map(\.id))
        noteCounts.merge(newCounts) { _, new in new }
        let newTags = DatabaseManager.shared.tagsForHighlights(ids: batch.map(\.id))
        highlightTags.merge(newTags) { _, new in new }

        if reset {
            appFacets = DatabaseManager.shared.appFacets().map {
                AppFacet(appName: $0.appName, bundleId: $0.bundleId, count: $0.count)
            }
        }
    }

    private func performSearch() {
        guard isActive, !searchText.isEmpty else { return }
        loadCaptures(reset: true)
    }

    private func refreshSidebarData() {
        let db = DatabaseManager.shared
        db.pruneEmptyTags()
        allTags = db.allTags()
        tagCounts = db.tagHighlightCounts()
        var counts = db.typeCounts()
        counts["_annotated"] = db.annotatedHighlightCount()
        typeCounts = counts
    }

    // MARK: - Drag & Drop Import

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        for provider in providers {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, error in
                if let error {
                    CaptureLog.warning("Drop import: loadFileRepresentation failed: \(error.localizedDescription)")
                    return
                }
                guard let url else { return }

                // The URL in this callback is deleted once the callback returns,
                // so we copy to a temp location we own before the async import.
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("drop-import-\(UUID().uuidString)", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                } catch {
                    CaptureLog.warning("Drop import: temp dir failed: \(error.localizedDescription)")
                    return
                }
                let tempURL = tempDir.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                } catch {
                    CaptureLog.warning("Drop import: temp copy failed for \(url.lastPathComponent): \(error.localizedDescription)")
                    return
                }

                Task {
                    await FileMonitor.shared.importFile(from: tempURL)
                    try? FileManager.default.removeItem(at: tempDir)
                }
            }
        }
        return true
    }
}

// MARK: - Masonry Layout

private struct MasonryLayout: Layout {
    let minColumnWidth: CGFloat
    let spacing: CGFloat

    private func columnCount(for width: CGFloat) -> Int {
        guard width.isFinite, width > 0, minColumnWidth > 0 else { return 2 }
        let maxCols = Int((width + spacing) / (minColumnWidth + spacing))
        return min(5, max(1, maxCols))
    }

    private func columnWidth(for totalWidth: CGFloat, columns: Int) -> CGFloat {
        let gaps = CGFloat(columns - 1) * spacing
        return max(0, (totalWidth - gaps) / CGFloat(columns))
    }

    struct CacheData {
        var heights: [CGFloat] = []
        var cachedColumns: Int = 0
    }

    func makeCache(subviews: Subviews) -> CacheData { CacheData() }

    private func ensureCache(subviews: Subviews, columns: Int, colWidth: CGFloat, cache: inout CacheData) {
        guard cache.cachedColumns != columns || cache.heights.count != subviews.count else { return }
        cache.heights = subviews.map {
            $0.sizeThatFits(.init(width: colWidth, height: nil)).height
        }
        cache.cachedColumns = columns
    }

    /// Shortest-column-first with deterministic tie-breaking (leftmost column wins).
    /// This balances column heights evenly while being consistent across relayouts.
    private func layout(columns: Int, colWidth: CGFloat, heights: [CGFloat]) -> (colHeights: [CGFloat], assignments: [(col: Int, y: CGFloat)]) {
        var colHeights = Array(repeating: CGFloat(0), count: columns)
        var assignments: [(col: Int, y: CGFloat)] = []
        assignments.reserveCapacity(heights.count)

        for h in heights {
            // Pick the shortest column; on ties, pick the leftmost (lowest index)
            var shortestCol = 0
            var shortestH = colHeights[0]
            for c in 1..<columns {
                if colHeights[c] < shortestH {
                    shortestH = colHeights[c]
                    shortestCol = c
                }
            }
            if colHeights[shortestCol] > 0 { colHeights[shortestCol] += spacing }
            let y = colHeights[shortestCol]
            assignments.append((col: shortestCol, y: y))
            colHeights[shortestCol] += h
        }
        return (colHeights, assignments)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) -> CGSize {
        let width = proposal.width ?? 300
        let columns = columnCount(for: width)
        let colWidth = columnWidth(for: width, columns: columns)
        ensureCache(subviews: subviews, columns: columns, colWidth: colWidth, cache: &cache)

        let (colHeights, _) = layout(columns: columns, colWidth: colWidth, heights: cache.heights)
        return CGSize(width: width, height: colHeights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        let columns = columnCount(for: bounds.width)
        let colWidth = columnWidth(for: bounds.width, columns: columns)
        ensureCache(subviews: subviews, columns: columns, colWidth: colWidth, cache: &cache)

        let (_, assignments) = layout(columns: columns, colWidth: colWidth, heights: cache.heights)
        for (i, subview) in subviews.enumerated() {
            let a = assignments[i]
            let x = bounds.minX + CGFloat(a.col) * (colWidth + spacing)
            let y = bounds.minY + a.y
            subview.place(at: CGPoint(x: x, y: y), proposal: .init(width: colWidth, height: cache.heights[i]))
        }
    }
}

// MARK: - Masonry Card

private struct MasonryCard: View {
    let highlight: Highlight
    var noteCount: Int = 0
    var cardTags: [Tag] = []
    var onTagTap: ((Tag) -> Void)? = nil
    @State private var isHovered = false
    // Context menu tags loaded on demand (not per-card)
    // Tag add/remove refreshes auto-propagate via .highlightDataDidChange
    // posted by DatabaseManager — no local callback needed.

    private var hasAnnotation: Bool {
        if let note = highlight.userNote, !note.isEmpty { return true }
        return false
    }

    private var hasSourceUrl: Bool {
        guard let url = highlight.sourceUrl, !url.isEmpty else { return false }
        return URL(string: url) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            cardContent

            if hasAnnotation {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.orange.opacity(0.85))
                        .frame(width: 2.5)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(highlight.userNote ?? "")
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(6)

                        if noteCount > 1 {
                            Text("+\(noteCount - 1) more")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !cardTags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(cardTags.prefix(3)) { tag in
                        TagChip(name: tag.name, onTap: onTagTap.map { handler in
                            { handler(tag) }
                        })
                    }
                    if cardTags.count > 3 {
                        Text("+\(cardTags.count - 3)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(Color(.windowBackgroundColor))
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
        .overlay(alignment: .topTrailing) {
            if hasSourceUrl && isHovered {
                Button(action: {
                    if let url = highlight.sourceUrl, let parsed = URL(string: url) {
                        NSWorkspace.shared.open(parsed)
                    }
                }) {
                    Image(systemName: "arrow.up.forward.square.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Menu("Collection") {
                ForEach(DatabaseManager.shared.allTags()) { tag in
                    let isApplied = cardTags.contains(where: { $0.id == tag.id })
                    Button(action: {
                        if isApplied {
                            DatabaseManager.shared.removeTag(tag.id, fromHighlight: highlight.id)
                        } else {
                            DatabaseManager.shared.addTag(tag.id, toHighlight: highlight.id)
                        }
                        // DatabaseManager posts .highlightDataDidChange — no local refresh needed.
                    }) {
                        HStack {
                            Text(tag.name)
                            if isApplied {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                if !false {
                    Divider()
                }
                Button("New Tag...") {
                    // Opens detail view where user can add tags
                }
            }
        }
        // Tags loaded lazily on first context menu open, not per-card onAppear
    }

    @ViewBuilder
    private var cardContent: some View {
        switch highlight.highlightType {
        case "screenshot":
            ScreenshotCard(highlight: highlight)
        case "recording":
            RecordingCard(highlight: highlight)
        case "highlight":
            HighlightCard(highlight: highlight)
        case "note":
            NoteCard(highlight: highlight)
        case "file":
            FileCard(highlight: highlight)
        default:
            if MasonryCard.isURLCopy(highlight) {
                LinkCard(highlight: highlight)
            } else {
                TextCard(highlight: highlight)
            }
        }
    }

    static func isURLCopy(_ h: Highlight) -> Bool {
        if h.contentType == "url" { return true }
        let trimmed = h.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else { return false }
        // Ensure the whole thing is a URL, not a paragraph containing one.
        return !trimmed.contains(" ") && !trimmed.contains("\n")
    }
}

// MARK: - Screenshot Card

private struct ScreenshotCard: View {
    let highlight: Highlight
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(.quaternary.opacity(0.3))
                    .frame(height: 120)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
            }

            Text(CardMetadata.timeAgo(from: highlight.date))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .task {
            if image == nil {
                let path = highlight.contentText
                image = await Task.detached {
                    NSImage(contentsOfFile: path)
                }.value
            }
        }
    }
}

// MARK: - Recording Card

private struct RecordingCard: View {
    let highlight: Highlight
    @State private var thumbnail: NSImage?
    @State private var recording: RecordingRecord?
    @State private var isPlaying = false

    private var videoURL: URL {
        if let recording {
            return URL(fileURLWithPath: recording.filePath)
        }
        return URL(fileURLWithPath: highlight.contentText)
    }

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: videoURL.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if isPlaying, fileExists {
                    // Inline video player
                    InlineVideoPlayer(url: videoURL)
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(minHeight: 140)
                } else if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 220)
                        .clipped()

                    // Play button overlay
                    Circle()
                        .fill(.black.opacity(0.5))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.white)
                                .font(.system(size: 18))
                                .offset(x: 2)
                        }
                        .onTapGesture { isPlaying = true }
                } else {
                    Rectangle()
                        .fill(.quaternary.opacity(0.3))
                        .frame(height: 120)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "video.fill")
                                    .font(.title2)
                                    .foregroundStyle(.tertiary)
                                if let recording {
                                    Text(recording.formattedDuration)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .onTapGesture { isPlaying = true }
                }

                // Duration badge (bottom-right, not during playback)
                if !isPlaying, let recording {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(recording.formattedDuration)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(6)
                        }
                    }
                }
            }

            EmptyView() // metadata moved to detail view
        }
        .contextMenu {
            Button("Play in QuickTime") {
                openFile(highlight.contentText)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: highlight.contentText)])
            }
        }
        .task {
            // Resolve RecordingRecord: prefer FK, fall back to path lookup.
            var rec: RecordingRecord?
            if let recordingId = highlight.recordingId {
                rec = DatabaseManager.shared.recording(byId: recordingId)
            }
            if rec == nil {
                rec = DatabaseManager.shared.recordingByPath(highlight.contentText)
            }
            guard let rec else { return }
            self.recording = rec

            if thumbnail == nil {
                let path = rec.thumbnailPath
                thumbnail = await Task.detached {
                    NSImage(contentsOfFile: path)
                }.value
            }
            // Fallback: extract a frame directly from the video file.
            if thumbnail == nil {
                thumbnail = await LiveThumbnail.generate(for: URL(fileURLWithPath: rec.filePath))
            }
        }
    }
}

// MARK: - Live Thumbnail Fallback

/// Generates a preview image on demand for videos and PDFs when the cached
/// `thumbnailPath` is missing or the file at that path cannot be loaded.
/// Used by RecordingCard and FileCard so the masonry always shows a real
/// preview instead of an icon placeholder.
private enum LiveThumbnail {
    static func generate(for fileURL: URL) async -> NSImage? {
        let ext = fileURL.pathExtension.lowercased()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        if ext == "pdf" {
            return await Task.detached(priority: .utility) {
                guard let doc = PDFDocument(url: fileURL),
                      let page = doc.page(at: 0) else { return nil }
                let pageRect = page.bounds(for: .mediaBox)
                let scale: CGFloat = 600.0 / max(pageRect.width, 1)
                let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
                return page.thumbnail(of: size, for: .mediaBox)
            }.value
        }

        let videoExts: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
        if videoExts.contains(ext) {
            let asset = AVAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)
            // Prefer ~1s in — first frame is often black/partial on many codecs.
            for seconds in [1.0, 0.5, 0.0] {
                do {
                    let (cgImage, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
                    return NSImage(cgImage: cgImage, size: .zero)
                } catch {
                    continue
                }
            }
            return nil
        }

        // Generic fallback: let QuickLook extract a cover/preview for any other
        // file type it understands — including EPUBs, Keynote, iBooks, etc.
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: 600, height: 600),
            scale: 2.0,
            representationTypes: .thumbnail
        )
        do {
            let thumbnail = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return NSImage(cgImage: thumbnail.cgImage, size: .zero)
        } catch {
            return nil
        }
    }
}

// MARK: - Inline Video Player

private struct InlineVideoPlayer: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        context.coordinator.player = player
        context.coordinator.playerView = playerView
        player.play()
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    class Coordinator {
        var player: AVPlayer?
        var playerView: AVPlayerView?

        func tearDown() {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            if let pv = playerView, pv.window != nil, !pv.isHidden {
                pv.player = nil
            }
            playerView = nil
            player = nil
        }

        deinit {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }
    }
}

// MARK: - Text Card

private struct TextCard: View {
    let highlight: Highlight

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.15))
                .frame(width: 2.5)

            VStack(alignment: .leading, spacing: 6) {
                Text(highlight.contentText)
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(12)
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Highlight Card

private struct HighlightCard: View {
    let highlight: Highlight

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.orange)
                .frame(width: 2.5)

            Text(highlight.contentText)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(12)
                .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Note Card

private struct NoteCard: View {
    let highlight: Highlight

    var body: some View {
        Text(highlight.contentText)
            .font(.callout)
            .foregroundStyle(.primary.opacity(0.9))
            .lineLimit(12)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - File Card

private struct FileCard: View {
    let highlight: Highlight
    @State private var thumbnail: NSImage?
    @State private var fileRecord: FileRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let thumbnail {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 220)
                        .clipped()

                    if let pages = fileRecord?.pageCount, pages > 0 {
                        Text("\(pages) pg")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }
            } else {
                // Finder-style file icon from the system
                Rectangle()
                    .fill(.quaternary.opacity(0.15))
                    .frame(height: 100)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(nsImage: systemFileIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 48)
                            if let ext = fileRecord?.fileExtension, !ext.isEmpty {
                                Text(ext.uppercased())
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
            }

            HStack {
                Text(fileRecord?.fileName ?? URL(fileURLWithPath: highlight.contentText).lastPathComponent)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer()
                Text(CardMetadata.timeAgo(from: highlight.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .contextMenu {
            Button("Open") {
                openFile(highlight.contentText)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: highlight.contentText)])
            }
        }
        .task {
            // Resolve the FileRecord: prefer foreign key, but fall back to
            // a path lookup if the highlight was inserted before the FK fix.
            var rec: FileRecord?
            if let fId = highlight.fileId {
                rec = DatabaseManager.shared.fileRecord(byId: fId)
            }
            if rec == nil {
                rec = DatabaseManager.shared.fileRecordByPath(highlight.contentText)
            }
            guard let rec else { return }
            self.fileRecord = rec

            if let thumbPath = rec.thumbnailPath {
                thumbnail = await Task.detached {
                    NSImage(contentsOfFile: thumbPath)
                }.value
            }
            // Always try a live preview for videos/PDFs when the cached
            // thumbnail is missing or failed to load.
            if thumbnail == nil {
                thumbnail = await LiveThumbnail.generate(for: URL(fileURLWithPath: rec.filePath))
            }
        }
    }

    private var systemFileIcon: NSImage {
        let path = highlight.contentText
        if FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        // File might have been deleted — use UTI-based icon
        if let ext = fileRecord?.fileExtension,
           let utType = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: utType)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
}

// MARK: - Link Card

private struct LinkCard: View {
    let highlight: Highlight
    @State private var preview: LinkPreview?
    @State private var heroImage: NSImage?
    @State private var faviconImage: NSImage?
    @State private var didLoad = false

    private var urlString: String {
        highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayHost: String {
        preview?.siteName
            ?? URL(string: urlString)?.host?.replacingOccurrences(of: "www.", with: "")
            ?? urlString
    }

    private var displayTitle: String {
        if let title = preview?.title, !title.isEmpty { return title }
        return urlString
    }

    private func openURL() {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: openURL) {
                VStack(alignment: .leading, spacing: 0) {
                    if let heroImage {
                        Image(nsImage: heroImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 180)
                            .clipped()
                    } else if !didLoad {
                        Rectangle()
                            .fill(.quaternary.opacity(0.15))
                            .frame(height: 100)
                            .overlay {
                                ProgressView()
                                    .controlSize(.small)
                            }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if let faviconImage {
                                Image(nsImage: faviconImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "link")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 14, height: 14)
                            }
                            Text(displayHost)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }

                        Text(displayTitle)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 4) {
                            if let app = highlight.sourceApp {
                                Text(app)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(CardMetadata.timeAgo(from: highlight.date))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button("Open in Browser", action: openURL)
            Button("Copy URL") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(urlString, forType: .string)
            }
        }
        .task {
            let fetched = await LinkPreviewStore.shared.preview(for: urlString)
            self.preview = fetched
            self.didLoad = true
            if let path = fetched?.imagePath {
                self.heroImage = await Task.detached { NSImage(contentsOfFile: path) }.value
            }
            if let path = fetched?.faviconPath {
                self.faviconImage = await Task.detached { NSImage(contentsOfFile: path) }.value
            }
        }
    }
}

// MARK: - Detail Link Preview (full-size, shown inside CardDetailView)

private struct DetailLinkPreview: View {
    let urlString: String
    @State private var preview: LinkPreview?
    @State private var heroImage: NSImage?
    @State private var faviconImage: NSImage?
    @State private var didLoad = false
    @State private var isHovered = false

    private var displayHost: String {
        preview?.siteName
            ?? URL(string: urlString)?.host?.replacingOccurrences(of: "www.", with: "")
            ?? urlString
    }

    private var displayTitle: String {
        if let title = preview?.title, !title.isEmpty { return title }
        return urlString
    }

    var body: some View {
        Button(action: openInBrowser) {
            VStack(alignment: .leading, spacing: 14) {
                if let heroImage {
                    Image(nsImage: heroImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if !didLoad {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary.opacity(0.15))
                        .frame(height: 200)
                        .overlay { ProgressView() }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if let faviconImage {
                            Image(nsImage: faviconImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "link")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(width: 14, height: 14)
                        }
                        Text(displayHost)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isHovered ? .primary : .tertiary)
                    }

                    Text(displayTitle)
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.primary.opacity(0.04) : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.18 : 0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(urlString)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .task {
            let fetched = await LinkPreviewStore.shared.preview(for: urlString)
            self.preview = fetched
            self.didLoad = true
            if let path = fetched?.imagePath {
                self.heroImage = await Task.detached { NSImage(contentsOfFile: path) }.value
            }
            if let path = fetched?.faviconPath {
                self.faviconImage = await Task.detached { NSImage(contentsOfFile: path) }.value
            }
        }
    }

    private func openInBrowser() {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Embedded Link Preview (compact row, shown near the bottom of detail view)

private struct EmbeddedLinkPreview: View {
    let urlString: String
    @State private var preview: LinkPreview?
    @State private var heroImage: NSImage?
    @State private var faviconImage: NSImage?
    @State private var didLoad = false

    private var displayHost: String {
        preview?.siteName
            ?? URL(string: urlString)?.host?.replacingOccurrences(of: "www.", with: "")
            ?? urlString
    }

    private var displayTitle: String {
        if let title = preview?.title, !title.isEmpty { return title }
        return urlString
    }

    var body: some View {
        // Hide the section entirely if the fetch failed and there's nothing
        // meaningful to show — don't pollute the detail view with error rows.
        if didLoad && preview?.fetchError != nil && heroImage == nil && preview?.title == nil {
            EmptyView()
        } else {
            Button(action: openInBrowser) {
                HStack(alignment: .top, spacing: 10) {
                    if let heroImage {
                        Image(nsImage: heroImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 60)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else if !didLoad {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary.opacity(0.2))
                            .frame(width: 80, height: 60)
                            .overlay { ProgressView().controlSize(.small) }
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary.opacity(0.15))
                            .frame(width: 80, height: 60)
                            .overlay {
                                Image(systemName: "link")
                                    .foregroundStyle(.tertiary)
                            }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            if let faviconImage {
                                Image(nsImage: faviconImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 12, height: 12)
                            }
                            Text(displayHost)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(displayTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .task {
                let fetched = await LinkPreviewStore.shared.preview(for: urlString)
                self.preview = fetched
                self.didLoad = true
                if let path = fetched?.imagePath {
                    self.heroImage = await Task.detached { NSImage(contentsOfFile: path) }.value
                }
                if let path = fetched?.faviconPath {
                    self.faviconImage = await Task.detached { NSImage(contentsOfFile: path) }.value
                }
            }
        }
    }

    private func openInBrowser() {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Card Metadata

// MARK: - Instant Tooltip Button

private struct InstantTooltipButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isHovered ? Color.primary : Color.primary.opacity(0.4))
        }
        .buttonStyle(.plain)
        .help(label)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

// MARK: - PDF Preview

private struct PDFPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.document = PDFDocument(url: url)
        pdfView.backgroundColor = NSColor.textBackgroundColor
        // PDFView has no useful intrinsic content size — force a sensible
        // default so SwiftUI gives it real vertical space inside a ScrollView.
        pdfView.setContentHuggingPriority(.defaultLow, for: .vertical)
        pdfView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pdfView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        pdfView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}

// MARK: - EPUB Preview (wraps macOS QLPreviewView — renders the full book)

/// Wraps `QLPreviewView` so SwiftUI can embed it. `QLPreviewView` is the same
/// NSView macOS uses for inline Quick Look previews and renders EPUBs as a
/// full paginated reader. It also handles many other formats, so we can reuse
/// it as a generic fallback for file types that don't have a dedicated branch.
private struct QuickLookPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.previewItem = url as QLPreviewItem
        // Fill whatever space the parent SwiftUI frame gives us — QLPreviewView
        // has no meaningful intrinsic content size.
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if let current = nsView.previewItem as? URL, current == url { return }
        nsView.previewItem = url as QLPreviewItem
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) {
        nsView.close()
    }
}

// MARK: - File Open Helper

/// Opens a file, using Preview for PDFs instead of the system default.
private func openFile(_ path: String) {
    let url = URL(fileURLWithPath: path)
    if url.pathExtension.lowercased() == "pdf",
       let previewURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
        NSWorkspace.shared.open([url], withApplicationAt: previewURL, configuration: NSWorkspace.OpenConfiguration())
    } else {
        NSWorkspace.shared.open(url)
    }
}

enum CardMetadata {
    static func domain(from urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty,
              let url = URL(string: urlString),
              let host = url.host else { return nil }
        // Strip "www." prefix for cleaner display
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func shortURL(from urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty,
              let url = URL(string: urlString),
              let host = url.host else { return nil }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path == "/" ? "" : url.path
        let full = domain + path
        return full.count > 60 ? String(full.prefix(57)) + "..." : full
    }

    static func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<60:     return "just now"
        case ..<3600:
            let m = seconds / 60
            return "\(m) min ago"
        case ..<86400:
            let h = seconds / 3600
            return "\(h) hr\(h == 1 ? "" : "s") ago"
        case ..<172800: return "yesterday"
        default:
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: date)
        }
    }
}

private struct CardMetadataFooter: View {
    let highlight: Highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let wt = highlight.windowTitle, !wt.isEmpty {
                Text(wt.count > 50 ? String(wt.prefix(47)) + "..." : wt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                if let app = highlight.sourceApp {
                    Text(app)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let shortURL = CardMetadata.shortURL(from: highlight.sourceUrl) {
                    Text(shortURL)
                        .font(.caption2)
                        .foregroundStyle(.blue.opacity(0.7))
                        .lineLimit(1)
                        .onTapGesture {
                            if let url = URL(string: highlight.sourceUrl ?? "") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                }
                if let ct = highlight.contentType, ct != "prose" {
                    Text(ct)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(Capsule())
                }
                Spacer()
                Text(CardMetadata.timeAgo(from: highlight.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Card Detail View (Sheet)

private struct CardDetailView: View {
    let highlight: Highlight
    var onDismiss: (() -> Void)?
    var onTagNavigation: ((Highlight, Tag) -> Void)?
    @State private var image: NSImage?
    @State private var notes: [HighlightNote] = []
    @State private var newNoteText = ""
    @State private var tags: [Tag] = []
    @State private var confirmationText: String?
    @State private var showCollectionPicker = false
    @State private var collectionInput = ""
    @State private var allCollections: [Tag] = []

    private var isScreenshot: Bool { highlight.highlightType == "screenshot" }
    private var isRecording: Bool { highlight.highlightType == "recording" }
    private var isFile: Bool { highlight.highlightType == "file" }

    private func showConfirmation(_ text: String) {
        withAnimation(.easeInOut(duration: 0.15)) { confirmationText = text }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.3)) { confirmationText = nil }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: UITokens.sectionSpacing) {
                    // Content preview
                    if isScreenshot {
                        if let image {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    } else if isRecording {
                        recordingDetailContent
                    } else if isFile {
                        fileDetailContent
                    } else if MasonryCard.isURLCopy(highlight) {
                        if highlight.fileId != nil {
                            downloadedFileLinkContent
                        } else {
                            linkDetailContent
                        }
                    } else {
                        // Copied text — styled as a clipping
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 5) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 10))
                                Text("Copied text")
                                    .font(.system(size: 11, weight: .medium))
                                if let app = highlight.sourceApp {
                                    Text("from \(app)")
                                        .font(.system(size: 11))
                                }
                            }
                            .foregroundStyle(.tertiary)

                            HStack(alignment: .top, spacing: 12) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.primary.opacity(0.12))
                                    .frame(width: 2.5)

                                Text(highlight.contentText)
                                    .font(.system(.body))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    notesTimeline

                    // OCR text — collapsed metadata, full-width
                    if isScreenshot, let screenshotId = highlight.screenshotId,
                       let screenshot = DatabaseManager.shared.screenshot(byId: screenshotId),
                       let ocrText = screenshot.ocrText, !ocrText.isEmpty {
                        OCRTextBlock(text: ocrText)
                    }

                    // Auxiliary preview for URLs embedded inside text copies.
                    if !MasonryCard.isURLCopy(highlight),
                       !isFile, !isScreenshot, !isRecording,
                       let embeddedURL = Self.firstEmbeddedURL(in: highlight.contentText) {
                        embeddedLinkPreviewSection(url: embeddedURL.absoluteString)
                    }
                }
                .padding(20)
            }

            Divider().opacity(0.5)

            noteInput
        }
        .frame(minWidth: 520, idealWidth: 740, minHeight: 420, idealHeight: 720)
        .task {
            if isScreenshot && image == nil {
                let path = highlight.contentText
                image = await Task.detached {
                    NSImage(contentsOfFile: path)
                }.value
            }
            loadNotes()
            tags = DatabaseManager.shared.tagsForHighlight(id: highlight.id)
        }
    }

    // MARK: - Header Bar (always visible)

    private var headerTitleText: String {
        if let wt = highlight.windowTitle, !wt.isEmpty { return wt }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: highlight.date)
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row — title on the left, bare-icon actions on the right
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(headerTitleText)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .layoutPriority(1)

                Spacer(minLength: 12)

                HStack(spacing: 16) {
                    InstantTooltipButton(icon: "doc.on.doc", label: "Copy content") {
                        copyContent(); showConfirmation("Copied")
                    }
                    if isScreenshot || isFile {
                        InstantTooltipButton(icon: "folder", label: "Reveal in Finder") {
                            showInFinder(); showConfirmation("Revealed in Finder")
                        }
                    }
                    if isFile {
                        InstantTooltipButton(icon: "arrow.up.forward.app", label: "Open file") {
                            openFile(highlight.contentText); showConfirmation("Opened")
                        }
                    }
                    InstantTooltipButton(icon: "xmark", label: "Close") {
                        onDismiss?()
                    }
                }
            }

            // Meta row — flat line: date · time · app · host  |  #tags  + add       Copied
            headerMetaLine
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var headerMetaLine: some View {
        let hasTitle = highlight.windowTitle?.isEmpty == false
        let host = CardMetadata.domain(from: highlight.sourceUrl)

        HStack(spacing: 0) {
            // Provenance group
            Group {
                if hasTitle {
                    Text(highlight.date, style: .date)
                    dot
                }
                Text(highlight.date, style: .time)
                if let app = highlight.sourceApp {
                    dot
                    Text(app)
                }
                if let host, let url = highlight.sourceUrl {
                    dot
                    InlineLink(text: host, url: url) {
                        openURL(url); showConfirmation("Opened \(host)")
                    }
                    .contextMenu {
                        Button("Copy URL") {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(url, forType: .string)
                            showConfirmation("Copied URL")
                        }
                    }
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            // Spacer between provenance and organisation groups
            if !tags.isEmpty {
                Spacer().frame(width: 18)
            } else {
                Spacer().frame(width: 12)
            }

            // Organisation group — flat tags + add
            HStack(spacing: 10) {
                ForEach(tags) { tag in
                    FlatTag(
                        name: tag.name,
                        onRemove: { removeCollection(tag) },
                        onTap: onTagNavigation.map { handler in
                            { handler(highlight, tag) }
                        }
                    )
                }

                Button(action: {
                    showCollectionPicker.toggle()
                    if showCollectionPicker {
                        allCollections = DatabaseManager.shared.allTags()
                        collectionInput = ""
                    }
                }) {
                    Text(tags.isEmpty ? "+ add collection" : "+")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(tags.isEmpty ? "Add to a collection" : "Add to another collection")
                .popover(isPresented: $showCollectionPicker, arrowEdge: .bottom) {
                    collectionPickerContent
                }
            }

            Spacer(minLength: 8)

            // Inline confirmation — no pill, no background
            if let text = confirmationText {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .lineLimit(1)
    }

    private var dot: some View {
        Text(" · ")
            .font(.system(size: 12))
            .foregroundStyle(.quaternary)
    }

    private var collectionPickerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search input
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search or create...", text: $collectionInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { createOrApplyCollection() }
                if !collectionInput.isEmpty {
                    Button(action: { collectionInput = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Existing collections list
            if !filteredCollections.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredCollections) { tag in
                            collectionRow(tag)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 40, maxHeight: 200)
            } else if collectionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No collections yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                Text("No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }

            // "Create new" at the bottom
            if !collectionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let trimmed = collectionInput.trimmingCharacters(in: .whitespacesAndNewlines)
                let exactMatch = filteredCollections.contains { $0.name.lowercased() == trimmed.lowercased() }
                if !exactMatch {
                    Divider()
                    Button(action: { createOrApplyCollection() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.blue)
                            Text("Create \"\(trimmed)\"")
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 240)
    }

    private func collectionRow(_ tag: Tag) -> some View {
        let isApplied = tags.contains { $0.id == tag.id }
        return Button(action: {
            if isApplied { removeCollection(tag) } else { applyCollection(tag) }
        }) {
            HStack(spacing: 8) {
                Image(systemName: isApplied ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isApplied ? Color.blue : Color.gray.opacity(0.4))
                    .font(.system(size: 14))
                Text(tag.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isApplied ? Color.blue.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filteredCollections: [Tag] {
        let trimmed = collectionInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return allCollections }
        return allCollections.filter { $0.name.lowercased().contains(trimmed) }
    }

    private func createOrApplyCollection() {
        let name = collectionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let tag = DatabaseManager.shared.findOrCreateTag(name: name) {
            applyCollection(tag)
        }
        collectionInput = ""
    }

    private func applyCollection(_ tag: Tag) {
        guard !tags.contains(where: { $0.id == tag.id }) else { return }
        DatabaseManager.shared.addTag(tag.id, toHighlight: highlight.id)
        tags.append(tag)
        allCollections = DatabaseManager.shared.allTags()
    }

    private func removeCollection(_ tag: Tag) {
        DatabaseManager.shared.removeTag(tag.id, fromHighlight: highlight.id)
        tags.removeAll { $0.id == tag.id }
    }

    // MARK: - Collections (moved to header bar — see collectionChips)

    // MARK: - Notes

    @ViewBuilder
    private var notesTimeline: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Notes")

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(notes) { note in
                        NoteRow(note: note) { deleteNote(note) }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var noteInput: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("Add a note...", text: $newNoteText, axis: .vertical)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.vertical, 6)
                .onKeyPress(.return) {
                    // Shift+Return inserts a newline (default TextField behavior).
                    // Plain Return submits.
                    if NSEvent.modifierFlags.contains(.shift) { return .ignored }
                    if noteIsEmpty { return .ignored }
                    submitNote()
                    return .handled
                }

            Button(action: submitNote) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(noteIsEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(noteIsEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var noteIsEmpty: Bool {
        newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    private func loadNotes() {
        notes = DatabaseManager.shared.notesForHighlight(id: highlight.id)
    }

    private func submitNote() {
        let body = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        DatabaseManager.shared.addNoteToHighlight(highlightId: highlight.id, body: body)
        newNoteText = ""
        loadNotes()
        NotificationCenter.default.post(name: .highlightDidSave, object: nil)
    }

    private func deleteNote(_ note: HighlightNote) {
        DatabaseManager.shared.deleteNote(id: note.id, highlightId: highlight.id)
        loadNotes()
    }

    private func copyContent() {
        let pb = NSPasteboard.general
        pb.clearContents()
        if isScreenshot {
            if let image { pb.writeObjects([image]) }
        } else {
            pb.setString(highlight.contentText, forType: .string)
        }
    }

    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: highlight.contentText)])
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Recording Detail

    @ViewBuilder
    private var recordingDetailContent: some View {
        let filePath = highlight.contentText
        let fileURL = URL(fileURLWithPath: filePath)
        let exists = FileManager.default.fileExists(atPath: filePath)

        VStack(alignment: .leading, spacing: 12) {
            if exists {
                InlineVideoPlayer(url: fileURL)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 16) {
                    Button(action: {
                        NSWorkspace.shared.open(fileURL)
                    }) {
                        Label("Open in QuickTime", systemImage: "play.rectangle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }) {
                        Label("Show in Finder", systemImage: "folder")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Recording file not found")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Recording metadata
            if let recordingId = highlight.recordingId,
               let rec = DatabaseManager.shared.recording(byId: recordingId) {
                HStack(spacing: 16) {
                    Label(rec.formattedDuration, systemImage: "clock")
                    Label(rec.formattedFileSize, systemImage: "internaldrive")
                    if rec.hasAudio {
                        Label("Audio", systemImage: "waveform")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Link detail (full-size preview for URL copies)

    private var linkDetailContent: some View {
        DetailLinkPreview(urlString: highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Downloaded file link (URL-copy whose target file was auto-downloaded)

    @ViewBuilder
    private var downloadedFileLinkContent: some View {
        if let fileId = highlight.fileId,
           let fileRec = DatabaseManager.shared.fileRecord(byId: fileId) {
            VStack(alignment: .leading, spacing: 12) {
                filePreview(fileRec)

                HStack(spacing: 12) {
                    fileInfoRow("File", fileRec.fileName, "doc")
                    fileInfoRow("Size", fileRec.formattedFileSize, "externaldrive")
                    if let ct = fileRec.contentType {
                        fileInfoRow("Type", ct, "tag")
                    }
                }

                // Source-link row — keeps the "this was a copied link" affordance.
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    InlineLink(
                        text: highlight.contentText,
                        url: highlight.contentText
                    ) {
                        openURL(highlight.contentText)
                        showConfirmation("Opened")
                    }
                    .font(.caption)
                }
            }
        } else {
            // Download still in flight or failed — fall back to link preview.
            linkDetailContent
        }
    }

    // MARK: - Embedded link preview (URLs inside non-URL text)

    private static let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func firstEmbeddedURL(in text: String) -> URL? {
        guard let detector = urlDetector else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range),
              let url = match.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    @ViewBuilder
    private func embeddedLinkPreviewSection(url: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Link in this note")
            EmbeddedLinkPreview(urlString: url)
        }
    }

    @ViewBuilder
    private var fileDetailContent: some View {
        let fileRec: FileRecord? = {
            if let fileId = highlight.fileId,
               let r = DatabaseManager.shared.fileRecord(byId: fileId) {
                return r
            }
            return DatabaseManager.shared.fileRecordByPath(highlight.contentText)
        }()
        if let fileRec {
            VStack(alignment: .leading, spacing: 12) {
                // Inline preview based on content type
                filePreview(fileRec)

                // File info
                HStack(spacing: 12) {
                    fileInfoRow("File", fileRec.fileName, "doc")
                    fileInfoRow("Size", fileRec.formattedFileSize, "externaldrive")
                    if let ct = fileRec.contentType {
                        fileInfoRow("Type", ct, "tag")
                    }
                }

                // File existence check
                if !FileManager.default.fileExists(atPath: fileRec.filePath) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("File has been moved or deleted")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    @ViewBuilder
    private func filePreview(_ fileRec: FileRecord) -> some View {
        let ct = fileRec.contentType ?? ""
        let url = URL(fileURLWithPath: fileRec.filePath)

        let ext = url.pathExtension.lowercased()

        if ct == "pdf" {
            // Interactive PDF viewer — NSViewRepresentable has no intrinsic
            // size, so give it an explicit frame or it collapses to 0 height.
            PDFPreviewView(url: url)
                .frame(maxWidth: .infinity, minHeight: 400, idealHeight: 500, maxHeight: 600)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        } else if ct == "ebook" || ext == "epub" {
            // Full EPUB reader via Quick Look — paginated, scrollable, selectable.
            QuickLookPreviewView(url: url)
                .frame(maxWidth: .infinity, minHeight: 400, idealHeight: 520, maxHeight: 640)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        } else if ct == "image", let img = NSImage(contentsOfFile: fileRec.filePath) {
            // Full image
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxHeight: 400)
        } else if ct == "video" {
            // Owns its AVPlayer in @State so typing in the note field (which
            // re-runs CardDetailView.body) doesn't rebuild the player and blink.
            StableVideoPlayer(url: url)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let thumbPath = fileRec.thumbnailPath,
                  let thumbImage = NSImage(contentsOfFile: thumbPath) {
            // QL thumbnail for documents etc.
            Image(nsImage: thumbImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxHeight: 300)
        } else {
            // System file icon
            HStack {
                Spacer()
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileRec.filePath))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 64)
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private func fileInfoRow(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

}

private struct StableVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        self._player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .onChange(of: url) { _, newURL in
                player.replaceCurrentItem(with: AVPlayerItem(url: newURL))
            }
    }
}
