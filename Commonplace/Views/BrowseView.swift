import SwiftUI
import AppKit
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

    // MARK: - Surface elevation
    //
    // Three adaptive layers — background → card → floating. In dark mode
    // each step is lighter than the last; in light mode each step is more
    // saturated white. Borders + shadows add definition on top of the fill.

    static let surfaceBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.09, alpha: 1.0)
            : NSColor(calibratedWhite: 0.94, alpha: 1.0)
    })

    static let surfaceCard = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.17, alpha: 1.0)
            : NSColor.white
    })

    static let surfaceFloater = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.22, alpha: 1.0)
            : NSColor.white
    })

    static let surfaceBorder = Color.primary.opacity(0.08)
    static let surfaceBorderStrong = Color.primary.opacity(0.14)

    // Elevation shadows — stronger than the old 0.05/2pt to read in dark mode.
    static let shadowCard = Color.black.opacity(0.22)
    static let shadowFloater = Color.black.opacity(0.38)

    // Corner radii.
    static let radiusCard: CGFloat = 10
    static let radiusFloater: CGFloat = 14
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

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(UITokens.sectionLabelFont)
            .tracking(UITokens.sectionLabelTracking)
            .foregroundStyle(.tertiary)
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
    var onTimestampTap: ((Double) -> Void)? = nil
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

                HStack(spacing: 8) {
                    if let seconds = note.timestampSeconds, let onTimestampTap {
                        Button(action: { onTimestampTap(seconds) }) {
                            HStack(spacing: 3) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8, weight: .semibold))
                                Text(VideoTimestampFormatter.format(seconds))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Jump to this moment in the video")
                    }
                    Text(CardMetadata.timeAgo(from: note.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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
    @State private var browseLoadTask: Task<Void, Never>? = nil
    @State private var browseLoadGeneration = 0
    @State private var sidebarRefreshTask: Task<Void, Never>? = nil
    @State private var sidebarRefreshGeneration = 0
    @State private var isReloadingCaptures = false
    @State private var noteCounts: [String: Int] = [:]
    @State private var aspectRatios: [String: CGFloat] = [:]
    @State private var selectedFilter: CaptureFilter = .all
    @State private var selectedApp: String? = nil
    @State private var appFacets: [AppFacet] = []
    // Scroll position managed by SwiftUI's default behavior
    @State private var typeCounts: [String: Int] = [:]
    @State private var isDropTargeted = false
    @State private var showSettings = false
    @State private var hasMore = false
    @State private var pinnedStack: Stack? = nil
    /// Ids of highlights currently in the pinned stack — drives the
    /// "already added" visual state on AddToStackButton.
    @State private var pinnedStackMembers: Set<String> = []
    @State private var selectedStack: Stack? = nil
    @State private var showStacks = false
    @State private var fullScreenImage: NSImage?
    @State private var footerBarFrame: CGRect = .zero
    @AppStorage("browseViewMode") private var viewMode: BrowseViewMode = .mosaic
    private let pageSize = 50

    /// The pinned stack rendered as a compact, intrinsic-sized floating tile
    /// anchored to the browse window's bottom-right corner. Sized by content
    /// (small square mosaic + label row) so it never dominates the window.
    /// The floater lives just above the footer bar, reuses the same card
    /// surface as every other StackCard, and leans on the isPinned-driven
    /// stronger shadow plus the pin-off badge to signal that it's the active
    /// container.
    @ViewBuilder
    private func pinnedStackFloater(_ pinned: Stack) -> some View {
        StackCard(
            stack: pinned,
            isPinned: true,
            onTap: {
                selectedStack = pinned
            }
        )
        .overlay(alignment: .topTrailing) {
            StackUnpinBadge {
                DatabaseManager.shared.setPinnedStack(id: nil)
            }
            .offset(x: 6, y: -6)
        }
        .id("pinned-stack-\(pinned.id)")
    }

    // MARK: - Computed

    private var browseLoadRequest: BrowseLoadRequest {
        BrowseLoadRequest(
            searchText: searchText,
            selectedFilter: selectedFilter,
            selectedApp: selectedApp
        )
    }

    private var filteredHighlights: [Highlight] {
        highlights
    }

    private var emptyStateTitle: String {
        if browseLoadRequest.hasActiveSearch {
            return "No matching captures"
        }
        if browseLoadRequest.hasActiveFilters {
            return "No captures match this filter"
        }
        return "No captures yet"
    }

    private var emptyStateSubtitle: String? {
        if browseLoadRequest.hasActiveSearch || browseLoadRequest.hasActiveFilters {
            return "Clear the search or adjust the current filters."
        }
        return nil
    }

    /// The "+" add tile pins to the top-left of the masonry only on user-curated
    /// views. Type and App filters are metadata-derived (things land in those
    /// buckets based on how they were captured), so "add to Screenshots" or
    /// "add to app = Chrome" is semantically meaningless there.
    private var showAddTile: Bool {
        selectedFilter == .all && selectedApp == nil && !showSettings
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            CaptureFilterSidebar(
                appFacets: appFacets,
                typeCounts: typeCounts,
                selectedApp: $selectedApp,
                selectedFilter: $selectedFilter,
                showSettings: $showSettings,
                showStacks: $showStacks
            )
            .onChange(of: selectedApp) { _, _ in
                guard isActive else { return }
                loadCaptures(reset: true)
            }
            .onChange(of: selectedFilter) { _, _ in
                guard isActive else { return }
                loadCaptures(reset: true)
            }
            .onChange(of: searchText) { _, _ in
                guard isActive else { return }
                loadCaptures(reset: true)
            }

            Divider()

            ZStack(alignment: .bottom) {
                // Darker surface than the sidebar so cards visually rest
                // on a distinct backdrop — fundamental to the elevation
                // hierarchy (background → card → floating).
                UITokens.surfaceBackground
                    .ignoresSafeArea()

                if showSettings {
                    ScrollView {
                        SettingsView()
                            .frame(maxWidth: 500)
                            .padding(24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if showStacks {
                    AllStacksView(onOpenStack: { stack in
                        withAnimation(.easeInOut(duration: 0.2)) { selectedStack = stack }
                    })
                } else {

            VStack(spacing: 0) {
                if filteredHighlights.isEmpty && !(showAddTile && viewMode == .mosaic) {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "tray")
                            .font(.system(size: 36))
                            .foregroundStyle(.quaternary)
                        Text(emptyStateTitle)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        if let emptyStateSubtitle {
                            Text(emptyStateSubtitle)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            VStack(spacing: 4) {
                                Text("Cmd+Shift+3 — screenshot")
                                Text("Cmd+Shift+4 — region capture")
                                Text("Copy text anywhere — auto-captured")
                                Text("Drop files here to import")
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Group {
                            switch viewMode {
                            case .mosaic:
                                MasonryLayout(minColumnWidth: 260, spacing: 14, pinFirst: showAddTile) {
                                    if showAddTile {
                                        AddTile()
                                    }
                                    ForEach(filteredHighlights) { highlight in
                                        MasonryCard(
                                            highlight: highlight,
                                            noteCount: noteCounts[highlight.id] ?? 0,
                                            preferredAspectRatio: aspectRatios[highlight.id]
                                        )
                                        .id(highlight.id)
                                        .onTapGesture {
                                            routeCardTap(highlight)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                            case .history:
                                HistoryListView(
                                    highlights: filteredHighlights,
                                    noteCounts: noteCounts,
                                    onSelect: { highlight in
                                        routeCardTap(highlight)
                                    }
                                )
                            }
                        }
                        // Force a clean unmount/remount when the user toggles
                        // between mosaic and history. Without it, SwiftUI
                        // preserves the ScrollView subtree and async-loading
                        // cards re-enter with stale measurement caches, which
                        // is what was producing the overlap after a mode
                        // switch.
                        .id(viewMode)
                        // Reserve clearance below the last card so the floating
                        // pinned stack doesn't obscure content at the bottom.
                        // `.animation(nil, …)` suppresses the implicit animation
                        // when the floater appears — without it, the 220pt
                        // change would animate alongside other pinnedStack
                        // transitions, re-flowing every masonry card.
                        .padding(.bottom, pinnedStack != nil ? 220 : 0)
                        .animation(nil, value: pinnedStack)
                    }
                    .onScrollGeometryChange(for: Bool.self) { geo in
                        // True when scrolled within 400pt of the bottom of the content
                        let bottomEdge = geo.contentOffset.y + geo.containerSize.height
                        let threshold = geo.contentSize.height - 400
                        return bottomEdge >= threshold
                    } action: { _, isNearBottom in
                        if isNearBottom && hasMore {
                            loadCaptures(reset: false)
                        }
                    }
                }

                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("\(filteredHighlights.count) captures")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if isReloadingCaptures {
                        ProgressView()
                            .controlSize(.small)
                    }
                    BrowseViewModeToggle(viewMode: $viewMode)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: BrowseFooterBarFramePreferenceKey.self,
                            value: proxy.frame(in: .named("BrowseRootSpace"))
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { clearFocus() })
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
            } // end ZStack
        }
        .coordinateSpace(name: "BrowseRootSpace")
        .onPreferenceChange(BrowseFooterBarFramePreferenceKey.self) { footerBarFrame = $0 }
        .onAppear {
            isActive = true
            loadCaptures(reset: true)
            refreshSidebarData()
            pinnedStack = DatabaseManager.shared.pinnedStack()
            pinnedStackMembers = DatabaseManager.shared.highlightIdsInPinnedStack()
        }
        .onDisappear {
            isActive = false
            browseLoadTask?.cancel()
            browseLoadTask = nil
            sidebarRefreshTask?.cancel()
            sidebarRefreshTask = nil
            isReloadingCaptures = false
        }
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

            // Sidebar counts always refresh — cheap indexed scans.
            refreshSidebarData()

            if browseLoadRequest.shouldReloadOnHighlightMutation(change: change) {
                loadCaptures(reset: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: BrowseWindowController.showSettingsNotification)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .stackDataDidChange).receive(on: DispatchQueue.main)) { _ in
            // @State dedupes equal writes (Stack, Set<String> are Equatable),
            // so direct assignment won't re-render when nothing changed.
            pinnedStack = DatabaseManager.shared.pinnedStack()
            pinnedStackMembers = DatabaseManager.shared.highlightIdsInPinnedStack()
            if let sel = selectedStack,
               let refreshed = DatabaseManager.shared.stack(byId: sel.id) {
                selectedStack = refreshed
            } else if selectedStack != nil {
                selectedStack = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: BrowseWindowController.showHighlightDetailNotification)) { notification in
            guard let highlightId = notification.userInfo?["highlightId"] as? String,
                  let highlight = DatabaseManager.shared.highlight(byId: highlightId) else { return }
            // Reset sidebar to "All" so the item is visible in the background list
            // once the detail overlay is dismissed.
            selectedFilter = .all
            selectedApp = nil
            searchText = ""
            isActive = true
            loadCaptures(reset: true)
            withAnimation(.easeInOut(duration: 0.2)) { selectedHighlight = highlight }
        }
        .overlay {
            if let highlight = selectedHighlight {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { selectedHighlight = nil } }

                    CardDetailView(
                        highlight: highlight,
                        onDismiss: { withAnimation(.easeInOut(duration: 0.2)) { selectedHighlight = nil } },
                        onStackNavigation: { stack in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedHighlight = nil
                                selectedStack = stack
                            }
                        },
                        onImageFullscreen: { image in
                            withAnimation(.easeInOut(duration: 0.2)) { fullScreenImage = image }
                        }
                    )
                        .id(highlight.id)
                        .frame(maxWidth: 700, maxHeight: .infinity)
                        .background(Color(.windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.25), radius: 16, y: 4)
                        .padding(40)
                }
                .transition(.opacity)
                .onExitCommand { withAnimation(.easeInOut(duration: 0.2)) { selectedHighlight = nil } }
            }
        }
        .overlay {
            if let stack = selectedStack {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { selectedStack = nil } }

                    StackDetailView(
                        stack: stack,
                        onDismiss: { withAnimation(.easeInOut(duration: 0.2)) { selectedStack = nil } },
                        onOpenHighlight: { highlight in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedStack = nil
                                selectedHighlight = highlight
                            }
                        }
                    )
                    .id(stack.id)
                    .frame(maxWidth: 900, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 4)
                    .padding(40)
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if let image = fullScreenImage {
                FullImageViewer(
                    image: image,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) { fullScreenImage = nil }
                    }
                )
                .transition(.opacity)
            }
        }
        // Pinned stack floater — rendered as the topmost overlay so it's
        // always reachable, even when a highlight or stack detail view
        // is open on top of the archive. Anchored to the window's
        // bottom-right corner with explicit clearance above the footer.
        .overlay(alignment: .bottomTrailing) {
            if let pinned = pinnedStack {
                pinnedStackFloater(pinned)
                    .padding(.trailing, 16)
                    .padding(.bottom, footerBarFrame.height + 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Membership of the pinned stack flows through the environment so
        // every AddToStackButton below — in masonry, history, pinned
        // origin breadcrumb, card detail, stack detail — renders its
        // "in stack" state without needing the set threaded as a prop.
        .environment(\.pinnedStackMembers, pinnedStackMembers)
    }

    // MARK: - Card tap routing

    private func routeCardTap(_ highlight: Highlight) {
        withAnimation(.easeInOut(duration: 0.2)) { selectedHighlight = highlight }
    }

    // MARK: - Data Loading

    private func loadCaptures(reset: Bool) {
        guard isActive else { return }
        if reset {
            browseLoadGeneration += 1
            browseLoadTask?.cancel()
            hasMore = false
            isReloadingCaptures = true
        } else if browseLoadTask != nil {
            return
        }

        let request = browseLoadRequest
        let generation = browseLoadGeneration
        let offset = reset ? 0 : highlightsOffset
        let limit = pageSize
        let shouldRefreshFacets = reset

        let task = Task.detached(priority: .userInitiated) {
            let db = DatabaseManager.shared
            let batch = db.browseHighlights(request, offset: offset, limit: limit)
            let newCounts = db.noteCountsForHighlights(ids: batch.map(\.id))
            let newRatios = db.aspectRatiosForHighlights(ids: batch.map(\.id))
            let facets: [(appName: String, bundleId: String?, count: Int)]? =
                shouldRefreshFacets ? db.appFacets() : nil

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard generation == browseLoadGeneration else { return }

                // Dedupe by id: an in-flight paginated load can race with a
                // reset triggered by .highlightDidSave / .highlightDataDidChange,
                // and real-time inserts can shift rows so the same id appears
                // on consecutive OFFSET pages. Either way, duplicate ids in
                // ForEach give undefined layout (overlapping masonry cards).
                if reset {
                    highlights = batch
                    highlightsOffset = batch.count
                } else {
                    let existingIds = Set(highlights.map(\.id))
                    let newRows = batch.filter { !existingIds.contains($0.id) }
                    highlights.append(contentsOf: newRows)
                    highlightsOffset += batch.count
                }
                hasMore = batch.count == limit
                noteCounts.merge(newCounts) { _, new in new }
                aspectRatios.merge(newRatios) { _, new in new }
                if let facets {
                    appFacets = facets.map {
                        AppFacet(appName: $0.appName, bundleId: $0.bundleId, count: $0.count)
                    }
                }
                isReloadingCaptures = false
                browseLoadTask = nil
            }
        }
        browseLoadTask = task
    }

    private func clearFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func refreshSidebarData() {
        sidebarRefreshGeneration += 1
        let generation = sidebarRefreshGeneration
        sidebarRefreshTask?.cancel()

        let task = Task.detached(priority: .userInitiated) {
            let db = DatabaseManager.shared
            var counts = db.typeCounts()
            counts["_annotated"] = db.annotatedHighlightCount()
            counts["_links"] = db.linkHighlightCount()
            counts["_videos"] = db.videoHighlightCount()
            counts["_filesNoVideo"] = db.fileExcludingVideoCount()

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard generation == sidebarRefreshGeneration else { return }
                typeCounts = counts
                sidebarRefreshTask = nil
            }
        }
        sidebarRefreshTask = task
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

private struct BrowseFooterBarFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct MasonryLayout: Layout {
    let minColumnWidth: CGFloat
    let spacing: CGFloat
    /// When true, subview index 0 is placed at (col 0, row 0) regardless of
    /// column heights. The remaining subviews flow using the shortest-column
    /// heuristic. Used by the Browse view to pin the "+" AddTile top-left.
    var pinFirst: Bool = false

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
        var measuredWidth: CGFloat = 0
        var columns: Int = 0
        var columnWidth: CGFloat = 0
        var heights: [CGFloat] = []
        var assignments: [(col: Int, y: CGFloat)] = []
        var contentHeight: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> CacheData { CacheData() }

    private func measureHeights(subviews: Subviews, colWidth: CGFloat) -> [CGFloat] {
        subviews.map {
            let measured = $0.sizeThatFits(.init(width: colWidth, height: nil)).height
            return measured.isFinite ? measured : 0
        }
    }

    private func refreshCache(
        for totalWidth: CGFloat,
        subviews: Subviews,
        cache: inout CacheData
    ) {
        // Always re-measure and re-layout. The previous "structureChanged"
        // short-circuit could stick with stale assignments when a card's
        // intrinsic height changed mid-transition (async image/link-preview
        // loads, mode-switch animations). layout() is O(n·cols) on
        // already-measured heights — cheap enough to run unconditionally.
        let columns = columnCount(for: totalWidth)
        let colWidth = columnWidth(for: totalWidth, columns: columns)
        let heights = measureHeights(subviews: subviews, colWidth: colWidth)
        let (colHeights, assignments) = layout(columns: columns, colWidth: colWidth, heights: heights)
        cache.measuredWidth = totalWidth
        cache.columns = columns
        cache.columnWidth = colWidth
        cache.heights = heights
        cache.assignments = assignments
        cache.contentHeight = colHeights.max() ?? 0
    }

    /// Shortest-column-first with deterministic tie-breaking (leftmost column wins).
    /// This balances column heights evenly while being consistent across relayouts.
    /// When `pinFirst` is true, index 0 is always placed at (col 0, y 0) and the
    /// rest flow starting from that column's bumped height.
    private func layout(columns: Int, colWidth: CGFloat, heights: [CGFloat]) -> (colHeights: [CGFloat], assignments: [(col: Int, y: CGFloat)]) {
        var colHeights = Array(repeating: CGFloat(0), count: columns)
        var assignments: [(col: Int, y: CGFloat)] = []
        assignments.reserveCapacity(heights.count)

        var startIndex = 0
        if pinFirst, let firstHeight = heights.first {
            assignments.append((col: 0, y: 0))
            colHeights[0] = firstHeight
            startIndex = 1
        }

        for i in startIndex..<heights.count {
            let h = heights[i]
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
        refreshCache(for: width, subviews: subviews, cache: &cache)
        return CGSize(width: width, height: cache.contentHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        // Re-measure inline and compute placements from scratch. Using the
        // cache here would hold assignments from `sizeThatFits` that can be
        // stale by the time we place — async image/link-preview loads
        // between the two calls change card natural heights. Those stale
        // Y offsets caused the visible overlap. Propose `height: nil` so
        // each subview renders at its natural height and neither we nor
        // SwiftUI try to squeeze a view smaller than its content requires.
        let columns = columnCount(for: bounds.width)
        let colWidth = columnWidth(for: bounds.width, columns: columns)
        let heights = measureHeights(subviews: subviews, colWidth: colWidth)
        let (_, assignments) = layout(columns: columns, colWidth: colWidth, heights: heights)
        cache.measuredWidth = bounds.width
        cache.columns = columns
        cache.columnWidth = colWidth
        cache.heights = heights
        cache.assignments = assignments
        for (i, subview) in subviews.enumerated() {
            let a = assignments[i]
            let x = bounds.minX + CGFloat(a.col) * (colWidth + spacing)
            let y = bounds.minY + a.y
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: .init(width: colWidth, height: nil)
            )
        }
    }
}

// MARK: - Source Link

/// Openable reference attached to a card's hover-revealed top-right pill.
/// Ranked so enricher-extracted deeplinks and web URLs win over weaker
/// fallbacks (file path, then bare app-launch) — see `MasonryCard.sourceLink`.
enum CardSourceLink {
    case url(String, label: String)
    case file(URL, label: String)
    case app(bundleId: String, label: String)

    var label: String {
        switch self {
        case .url(_, let l), .file(_, let l), .app(_, let l): return l
        }
    }

    var iconName: String {
        switch self {
        case .url, .file: return "arrow.up.forward.square.fill"
        case .app: return "arrow.up.forward.app.fill"
        }
    }

    func open() {
        switch self {
        case .url(let s, _):
            if let url = URL(string: s) { NSWorkspace.shared.open(url) }
        case .file(let url, _):
            NSWorkspace.shared.open(url)
        case .app(let bundleId, _):
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                NSWorkspace.shared.open(appURL)
            }
        }
    }
}

// MARK: - Masonry Card

private struct MasonryCard: View {
    let highlight: Highlight
    var noteCount: Int = 0
    /// Pre-resolved intrinsic aspect ratio (width/height) for this highlight's
    /// media, loaded in a batch by BrowseView. Passing it down lets the cover
    /// preview reserve aspect-correct space before any image/video decodes,
    /// which keeps neighbour cards from re-flowing when the bitmap arrives.
    var preferredAspectRatio: CGFloat? = nil
    @State private var isHovered = false
    @State private var isLinkHovered = false

    private var hasAnnotation: Bool {
        if let note = highlight.userNote, !note.isEmpty { return true }
        return false
    }

    /// Best "open outside the app" target for this card, picked by strength.
    /// Enricher URLs (Slack permalinks, browser page URL) > `sourceUrl` >
    /// URL-copy `contentText` > file path > bare app launch via `bundleId`.
    private var sourceLink: CardSourceLink? {
        if let entry = highlight.decodedSourceContext.first(where: { $0.url != nil }),
           let urlString = entry.url, let parsed = URL(string: urlString) {
            return .url(urlString, label: hostLabel(from: parsed, fallback: urlString))
        }

        if let urlString = highlight.sourceUrl, !urlString.isEmpty,
           let parsed = URL(string: urlString), parsed.scheme?.hasPrefix("http") == true {
            return .url(urlString, label: hostLabel(from: parsed, fallback: urlString))
        }

        if highlight.isURLCopy {
            let trimmed = highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = URL(string: trimmed) {
                return .url(trimmed, label: hostLabel(from: parsed, fallback: trimmed))
            }
        }

        if let path = highlight.sourceUrl, path.hasPrefix("/"),
           FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            return .file(url, label: url.lastPathComponent)
        }
        if let path = highlight.documentPath, !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            return .file(url, label: url.lastPathComponent)
        }

        if let bid = highlight.bundleId, !bid.isEmpty,
           let name = highlight.sourceApp, !name.isEmpty {
            return .app(bundleId: bid, label: name)
        }
        return nil
    }

    private func hostLabel(from url: URL, fallback: String) -> String {
        if let host = url.host, !host.isEmpty {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return fallback
    }

    private func linkHelp(_ link: CardSourceLink) -> String {
        switch link {
        case .url(let s, _): return "Open \(s)"
        case .file(let u, _): return "Open \(u.lastPathComponent)"
        case .app(_, let name): return "Open in \(name)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            cardContent
                .overlay(alignment: .bottomTrailing) {
                    AddToStackButton(highlightId: highlight.id, style: .overlay)
                        .padding(8)
                }

            if hasAnnotation || noteCount > 1 {
                VStack(alignment: .leading, spacing: 5) {
                    if hasAnnotation {
                        Text(highlight.userNote ?? "")
                            .font(.system(.callout, design: .serif))
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(6)
                    }

                    if noteCount > 1 {
                        Text("+\(noteCount - 1) more")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(hasAnnotation ? Color.orange.opacity(0.7) : Color.clear)
                        .frame(width: 2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(UITokens.surfaceCard)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: UITokens.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: UITokens.radiusCard)
                .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
        )
        .shadow(color: UITokens.shadowCard, radius: 6, y: 2)
        .overlay(alignment: .topTrailing) {
            if let link = sourceLink, isHovered {
                Button(action: { link.open() }) {
                    HStack(spacing: 0) {
                        Text(link.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(width: isLinkHovered ? nil : 0, alignment: .trailing)
                            .clipped()
                            .padding(.leading, isLinkHovered ? 8 : 0)
                            .padding(.trailing, isLinkHovered ? 4 : 0)
                        Image(systemName: link.iconName)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                    }
                    .padding(.trailing, 4)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(.black.opacity(0.55))
                            .opacity(isLinkHovered ? 1 : 0)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .help(linkHelp(link))
                .padding(8)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isLinkHovered = hovering
                    }
                }
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .materialContextMenu(for: highlight)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch highlight.highlightType {
        case "screenshot":
            ScreenshotCard(highlight: highlight, preferredAspectRatio: preferredAspectRatio)
        case "recording":
            ScreenshotCard(highlight: highlight, preferredAspectRatio: preferredAspectRatio)
        case "highlight":
            HighlightCard(highlight: highlight)
        case "note":
            NoteCard(highlight: highlight)
        case "file":
            FileCard(highlight: highlight, preferredAspectRatio: preferredAspectRatio)
        default:
            if highlight.isURLCopy {
                LinkCard(highlight: highlight, preferredAspectRatio: preferredAspectRatio)
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

private struct CardCoverPreview<Placeholder: View, Overlay: View>: View {
    let image: NSImage?
    let fallbackAspectRatio: CGFloat
    let preferredAspectRatio: CGFloat?
    let aspectRatioBuckets: [CGFloat]
    let placeholder: Placeholder
    let overlay: Overlay

    /// Aspect-ratio bucket committed on first appearance. Masonry is
    /// single-pass: once a card reports a height, neighbours pack
    /// against it, and a later bucket change would cause overlap. This
    /// @State captures the bucket exactly once and ignores subsequent
    /// `preferredAspectRatio` arrivals — the cover reserves a stable
    /// frame from first render through the whole card's lifetime.
    @State private var lockedAspect: CGFloat?

    init(
        image: NSImage?,
        fallbackAspectRatio: CGFloat = 1.3,
        preferredAspectRatio: CGFloat? = nil,
        aspectRatioBuckets: [CGFloat] = [0.82, 1.18, 1.62],
        @ViewBuilder placeholder: () -> Placeholder,
        @ViewBuilder overlay: () -> Overlay
    ) {
        self.image = image
        self.fallbackAspectRatio = fallbackAspectRatio
        self.preferredAspectRatio = preferredAspectRatio
        self.aspectRatioBuckets = aspectRatioBuckets
        self.placeholder = placeholder()
        self.overlay = overlay()
    }

    private var resolvedAspectRatio: CGFloat {
        if let lockedAspect { return lockedAspect }
        return computeAspectRatio()
    }

    private func computeAspectRatio() -> CGFloat {
        let buckets = aspectRatioBuckets.isEmpty ? [fallbackAspectRatio] : aspectRatioBuckets.sorted()
        let reference = preferredAspectRatio ?? fallbackAspectRatio
        return nearestAspectRatio(to: reference, buckets: buckets)
    }

    private func nearestAspectRatio(to rawValue: CGFloat, buckets: [CGFloat]) -> CGFloat {
        buckets.min(by: { abs($0 - rawValue) < abs($1 - rawValue) }) ?? fallbackAspectRatio
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(Rectangle())
                } else {
                    placeholder
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                overlay
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(Rectangle())
        }
        .aspectRatio(resolvedAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.12))
        .onAppear {
            if lockedAspect == nil {
                lockedAspect = computeAspectRatio()
            }
        }
        .onChange(of: preferredAspectRatio) { _, _ in
            if lockedAspect == nil {
                lockedAspect = computeAspectRatio()
            }
        }
    }
}

private extension CardCoverPreview where Overlay == EmptyView {
    init(
        image: NSImage?,
        fallbackAspectRatio: CGFloat = 1.3,
        preferredAspectRatio: CGFloat? = nil,
        aspectRatioBuckets: [CGFloat] = [0.82, 1.18, 1.62],
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.init(
            image: image,
            fallbackAspectRatio: fallbackAspectRatio,
            preferredAspectRatio: preferredAspectRatio,
            aspectRatioBuckets: aspectRatioBuckets,
            placeholder: placeholder,
            overlay: { EmptyView() }
        )
    }
}

private struct ScreenshotCard: View {
    let highlight: Highlight
    /// Intrinsic aspect ratio pre-resolved by BrowseView's batch map. Passed
    /// down instead of re-queried here so the cover can reserve an
    /// aspect-correct frame before `image` finishes loading — without this
    /// the card resizes when the bitmap arrives and neighbours shift.
    var preferredAspectRatio: CGFloat? = nil
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardCoverPreview(
                image: image,
                fallbackAspectRatio: 1.42,
                preferredAspectRatio: preferredAspectRatio,
                aspectRatioBuckets: [0.82, 1.25, 1.78]
            ) {
                Rectangle()
                    .fill(.quaternary.opacity(0.3))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .task {
            if image == nil {
                let path = highlight.contentText
                // Try loading as image first (screenshots, PNGs)
                image = await Task.detached {
                    NSImage(contentsOfFile: path)
                }.value
                // Fall back to video thumbnail extraction for recordings (.mov, .mp4)
                if image == nil {
                    image = await LiveThumbnail.generate(for: URL(fileURLWithPath: path))
                }
                // Fall back to FileRecord thumbnail if available
                if image == nil, let fileId = highlight.fileId,
                   let rec = DatabaseManager.shared.fileRecord(byId: fileId),
                   let thumbPath = rec.thumbnailPath {
                    image = await Task.detached {
                        NSImage(contentsOfFile: thumbPath)
                    }.value
                }
            }
        }
    }
}

// MARK: - Live Thumbnail Fallback

/// Generates a preview image on demand for videos and PDFs when the cached
/// `thumbnailPath` is missing or the file at that path cannot be loaded.
/// Used by RecordingCard and FileCard so the masonry always shows a real
/// preview instead of an icon placeholder.
enum LiveThumbnail {
    static func generate(for fileURL: URL) async -> NSImage? {
        let ext = fileURL.pathExtension.lowercased()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        // Image files: load directly. QuickLook sometimes returns nil for PNGs
        // and other common image types, which causes the masonry to render a
        // file-icon placeholder instead of the actual image.
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "bmp", "tiff", "tif", "webp"]
        if imageExts.contains(ext) {
            return await Task.detached(priority: .utility) {
                NSImage(contentsOf: fileURL)
            }.value
        }

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

struct InlineVideoPlayer: NSViewRepresentable {
    let url: URL
    var controller: VideoPlaybackController?

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
        if let controller {
            context.coordinator.attach(controller: controller, player: player)
        }
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
        private var timeObserverToken: Any?

        func attach(controller: VideoPlaybackController, player: AVPlayer) {
            Task { @MainActor in
                controller.attach(player)
            }
            let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
            timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                Task { @MainActor in
                    controller.updateCurrentTime(time.seconds)
                }
            }
        }

        func tearDown() {
            if let token = timeObserverToken {
                player?.removeTimeObserver(token)
                timeObserverToken = nil
            }
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            if let pv = playerView, pv.window != nil, !pv.isHidden {
                pv.player = nil
            }
            playerView = nil
            player = nil
        }

        deinit {
            if let token = timeObserverToken, let player {
                player.removeTimeObserver(token)
            }
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }
    }
}

// MARK: - Text Card

/// Length-driven typographic style for the text-only cards. Short snippets
/// scale up so they read as pull-quotes (à la mymind/Pinterest); long
/// snippets drop to a reading size and clamp to a generous line limit.
private enum TextCardStyle {
    struct Style {
        let font: Font
        let lineLimit: Int
        let verticalPadding: CGFloat
        let horizontalPadding: CGFloat
    }

    static func style(for text: String) -> Style {
        let count = text.count
        if count < 60 {
            return Style(
                font: .system(size: 20, weight: .medium, design: .serif),
                lineLimit: 6,
                verticalPadding: 12,
                horizontalPadding: 14
            )
        }
        if count < 200 {
            return Style(
                font: .system(size: 14, design: .serif),
                lineLimit: 10,
                verticalPadding: 10,
                horizontalPadding: 12
            )
        }
        return Style(
            font: .system(size: 13, design: .serif),
            lineLimit: 14,
            verticalPadding: 10,
            horizontalPadding: 12
        )
    }
}

private struct TextCard: View {
    let highlight: Highlight

    var body: some View {
        if TextHighlightRouter.isImageFilePath(highlight.contentText) {
            ScreenshotCard(highlight: highlight)
        } else {
            let style = TextCardStyle.style(for: highlight.contentText)
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 2)

                Text(highlight.contentText)
                    .font(style.font)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(style.lineLimit)
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.vertical, style.verticalPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Highlight Card

private struct HighlightCard: View {
    let highlight: Highlight

    var body: some View {
        if TextHighlightRouter.isImageFilePath(highlight.contentText) {
            ScreenshotCard(highlight: highlight)
        } else {
            let style = TextCardStyle.style(for: highlight.contentText)
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.orange.opacity(0.8))
                    .frame(width: 2)

                Text(highlight.contentText)
                    .font(style.font)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(style.lineLimit)
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.vertical, style.verticalPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Shared detection — some highlights have a raw image file path as their
// contentText due to legacy capture paths. Render those as images instead of
// spewing the internal path across the masonry.
private enum TextHighlightRouter {
    private static let imageExts: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "bmp", "tiff", "tif", "webp"
    ]

    static func isImageFilePath(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return false }
        guard !trimmed.contains("\n") else { return false }
        let ext = (trimmed as NSString).pathExtension.lowercased()
        guard imageExts.contains(ext) else { return false }
        return FileManager.default.fileExists(atPath: trimmed)
    }
}

// MARK: - Note Card

private struct NoteCard: View {
    let highlight: Highlight

    var body: some View {
        let style = TextCardStyle.style(for: highlight.contentText)
        Text(highlight.contentText)
            .font(style.font)
            .foregroundStyle(.primary.opacity(0.85))
            .lineLimit(style.lineLimit)
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, style.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - File Card

private struct FileCard: View {
    let highlight: Highlight
    /// Pre-resolved intrinsic aspect ratio from BrowseView's batch map. See
    /// ScreenshotCard for the rationale — same problem, same fix.
    var preferredAspectRatio: CGFloat? = nil
    @State private var thumbnail: NSImage?
    @State private var fileRecord: FileRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardCoverPreview(
                image: thumbnail,
                fallbackAspectRatio: 1.28,
                preferredAspectRatio: preferredAspectRatio,
                aspectRatioBuckets: [1.0, 1.28, 1.58]
            ) {
                Rectangle()
                    .fill(.quaternary.opacity(0.15))
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
            } overlay: {
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
            Text(fileRecord?.fileName ?? URL(fileURLWithPath: highlight.contentText).lastPathComponent)
                .font(.caption)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 2)

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
    /// Pre-resolved intrinsic aspect ratio for the link's hero image, from
    /// BrowseView's batch map. See ScreenshotCard for the rationale.
    var preferredAspectRatio: CGFloat? = nil
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardCoverPreview(
                image: heroImage,
                fallbackAspectRatio: 1.45,
                preferredAspectRatio: preferredAspectRatio,
                aspectRatioBuckets: [1.33, 1.58, 1.82]
            ) {
                Rectangle()
                    .fill(.quaternary.opacity(0.15))
                    .overlay {
                        if !didLoad {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "link")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
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

                if let desc = preview?.ogDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }

                if let app = highlight.sourceApp {
                    Text(app)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
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

struct DetailLinkPreview: View {
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

                    if let desc = preview?.ogDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if preview?.ogAuthor != nil || preview?.publishedDate != nil {
                        HStack(spacing: 6) {
                            if let author = preview?.ogAuthor, !author.isEmpty {
                                Text(author)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            if preview?.ogAuthor != nil && preview?.publishedDate != nil {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            if let date = preview?.publishedDate {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
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

struct EmbeddedLinkPreview: View {
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

struct InstantTooltipButton: View {
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

struct PDFPreviewView: NSViewRepresentable {
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
struct QuickLookPreviewView: NSViewRepresentable {
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
func openFile(_ path: String) {
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

// CardDetailView and StableVideoPlayer live in CardDetailView.swift

// MARK: - Browse View Mode

enum BrowseViewMode: String, CaseIterable {
    case mosaic
    case history
}

private struct BrowseViewModeToggle: View {
    @Binding var viewMode: BrowseViewMode

    var body: some View {
        HStack(spacing: 2) {
            button(mode: .mosaic, icon: "square.grid.2x2.fill", help: "Mosaic")
            button(mode: .history, icon: "list.bullet", help: "History")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(UITokens.chipFill)
        )
    }

    @ViewBuilder
    private func button(mode: BrowseViewMode, icon: String, help: String) -> some View {
        let selected = viewMode == mode
        Button(action: { viewMode = mode }) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? .primary : Color.secondary.opacity(0.7))
                .frame(width: 22, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected ? UITokens.surfaceCard : Color.clear)
                        .shadow(color: selected ? UITokens.shadowCard : .clear, radius: 2, y: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - History Grouping
//
// Chronologically ordered captures are split first by calendar day, then by
// "burst" inside each day — a burst is a run of items within `burstGap`
// seconds of each other. Bursts surface the natural rhythm of capture
// sessions ("everything I grabbed while researching X at 2 PM") without the
// user having to eyeball timestamps. A 30-minute gap is the default
// boundary; long enough that a short coffee break doesn't split a session,
// short enough that morning vs. afternoon work remains distinct.

struct HistoryCluster: Identifiable {
    let id = UUID()
    let highlights: [Highlight]  // newest first within the cluster

    var itemCount: Int { highlights.count }
    var startDate: Date { highlights.last?.date ?? Date() }
    var endDate: Date { highlights.first?.date ?? Date() }

    var rangeLabel: String {
        let f = DateFormatter()
        f.timeStyle = .short
        let s = f.string(from: startDate)
        let e = f.string(from: endDate)
        return s == e ? s : "\(s) – \(e)"
    }
}

struct HistoryDay: Identifiable {
    let id: Date  // start-of-day; unique per day
    let label: String
    let clusters: [HistoryCluster]

    var totalCount: Int { clusters.reduce(0) { $0 + $1.itemCount } }
    var allHighlightIds: [String] { clusters.flatMap { $0.highlights.map(\.id) } }
}

// Inline preview categories. Screenshots, recordings, and files all render
// a real thumbnail, so they collapse into the same "media" bucket for strip
// grouping. Everything else stays a compact row.
private extension Highlight {
    var isMediaType: Bool {
        highlightType == "screenshot" || highlightType == "recording" || highlightType == "file"
    }
}

// One entry in the vertical timeline inside a cluster. A run of consecutive
// media items collapses into `.strip` so a burst of screenshots reads as
// one visual unit rather than N stacked tiles.
enum HistoryTimelineItem: Identifiable {
    case row(Highlight)
    case media(Highlight)
    case strip([Highlight])

    var id: String {
        switch self {
        case .row(let h): return "row-\(h.id)"
        case .media(let h): return "media-\(h.id)"
        case .strip(let hs): return "strip-\(hs.first?.id ?? "")-\(hs.count)"
        }
    }
}

enum HistoryGrouping {
    static let burstGap: TimeInterval = 30 * 60  // 30 minutes

    /// Within a single cluster, merge consecutive media highlights into
    /// strips while leaving text-like items as their own rows.
    static func timelineItems(_ highlights: [Highlight]) -> [HistoryTimelineItem] {
        var items: [HistoryTimelineItem] = []
        var mediaRun: [Highlight] = []

        func flushMedia() {
            if mediaRun.count == 1 {
                items.append(.media(mediaRun[0]))
            } else if mediaRun.count >= 2 {
                items.append(.strip(mediaRun))
            }
            mediaRun = []
        }

        for h in highlights {
            if h.isMediaType {
                mediaRun.append(h)
            } else {
                flushMedia()
                items.append(.row(h))
            }
        }
        flushMedia()
        return items
    }

    static func group(_ highlights: [Highlight]) -> [HistoryDay] {
        guard !highlights.isEmpty else { return [] }
        let calendar = Calendar.current
        var days: [HistoryDay] = []

        var dayStart: Date? = nil
        var dayClusters: [HistoryCluster] = []
        var clusterItems: [Highlight] = []
        var lastItemDate: Date? = nil

        func flushCluster() {
            guard !clusterItems.isEmpty else { return }
            dayClusters.append(HistoryCluster(highlights: clusterItems))
            clusterItems = []
        }
        func flushDay() {
            flushCluster()
            guard let start = dayStart, !dayClusters.isEmpty else { return }
            days.append(HistoryDay(
                id: start,
                label: dayLabel(for: start, calendar: calendar),
                clusters: dayClusters
            ))
            dayClusters = []
        }

        for h in highlights {
            let itemDay = calendar.startOfDay(for: h.date)
            if dayStart == nil {
                dayStart = itemDay
            } else if itemDay != dayStart {
                flushDay()
                dayStart = itemDay
                lastItemDate = nil
            }
            // highlights arrive newest-first, so `last - current` is the gap
            if let last = lastItemDate, last.timeIntervalSince(h.date) > burstGap {
                flushCluster()
            }
            clusterItems.append(h)
            lastItemDate = h.date
        }
        flushDay()
        return days
    }

    static func dayLabel(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        let now = Date()
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            f.dateFormat = "EEEE"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            f.dateFormat = "EEEE, MMM d"
        } else {
            f.dateFormat = "MMM d, yyyy"
        }
        return f.string(from: date)
    }
}

// MARK: - History List

private struct HistoryListView: View {
    let highlights: [Highlight]
    let noteCounts: [String: Int]
    let onSelect: (Highlight) -> Void

    private var days: [HistoryDay] { HistoryGrouping.group(highlights) }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(days) { day in
                Section {
                    ForEach(Array(day.clusters.enumerated()), id: \.element.id) { _, cluster in
                        HistoryClusterHeader(cluster: cluster)
                        ForEach(HistoryGrouping.timelineItems(cluster.highlights)) { item in
                            Group {
                                switch item {
                                case .row(let h):
                                    HistoryRow(
                                        highlight: h,
                                        noteCount: noteCounts[h.id] ?? 0
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelect(h) }
                                case .media(let h):
                                    HistoryMediaRow(
                                        highlight: h,
                                        noteCount: noteCounts[h.id] ?? 0,
                                        onSelect: { onSelect(h) }
                                    )
                                case .strip(let hs):
                                    HistoryMediaStrip(
                                        highlights: hs,
                                        onSelect: onSelect
                                    )
                                }
                            }
                        }
                    }
                } header: {
                    HistoryDayHeader(day: day)
                }
            }
        }
    }
}

// MARK: - Day Header

private struct HistoryDayHeader: View {
    let day: HistoryDay
    @State private var isHovered = false
    @State private var justAdded = false

    var body: some View {
        HStack(spacing: 10) {
            Text(day.label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(UITokens.sectionLabelTracking)
                .foregroundStyle(.secondary)
            Text("\(day.totalCount) \(day.totalCount == 1 ? "capture" : "captures")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button(action: addAll) {
                HStack(spacing: 4) {
                    Image(systemName: justAdded ? "checkmark" : "rectangle.stack.badge.plus")
                        .font(.system(size: 10, weight: .medium))
                    Text(justAdded ? "Added day" : "Add day to stack")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(justAdded ? Color.accentColor : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(justAdded
                              ? Color.accentColor.opacity(0.1)
                              : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
                )
            }
            .buttonStyle(.plain)
            .opacity(isHovered || justAdded ? 1 : 0)
            .help("Add every capture from this day into the pinned stack")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(UITokens.surfaceBackground)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.6)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    private func addAll() {
        _ = DatabaseManager.shared.addHighlightsToPinnedOrNewStack(day.allHighlightIds)
        withAnimation(.easeInOut(duration: 0.2)) { justAdded = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.25)) { justAdded = false }
        }
    }
}

// MARK: - Cluster Header

private struct HistoryClusterHeader: View {
    let cluster: HistoryCluster
    @State private var isHovered = false
    @State private var justAdded = false

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 32, height: 1)
            Text(cluster.rangeLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("·")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("\(cluster.itemCount) item\(cluster.itemCount == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button(action: addAll) {
                HStack(spacing: 4) {
                    Image(systemName: justAdded ? "checkmark" : "rectangle.stack.badge.plus")
                        .font(.system(size: 10, weight: .medium))
                    Text(justAdded ? "Added" : "Add all to stack")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(justAdded ? Color.accentColor : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(justAdded
                              ? Color.accentColor.opacity(0.1)
                              : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
                )
            }
            .buttonStyle(.plain)
            .opacity(isHovered || justAdded ? 1 : 0)
            .help("Add every capture in this time window into the pinned stack")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    private func addAll() {
        let ids = cluster.highlights.map(\.id)
        _ = DatabaseManager.shared.addHighlightsToPinnedOrNewStack(ids)
        withAnimation(.easeInOut(duration: 0.2)) { justAdded = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.25)) { justAdded = false }
        }
    }
}

// MARK: - History Row

private struct HistoryRow: View {
    let highlight: Highlight
    var noteCount: Int = 0
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HistoryRowThumbnail(highlight: highlight)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(primaryText)
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let annotation = highlight.userNote, !annotation.isEmpty {
                    Text(annotation)
                        .font(.caption)
                        .foregroundStyle(.orange.opacity(0.85))
                        .lineLimit(1, reservesSpace: true)
                }

                HStack(spacing: 6) {
                    if let meta = secondaryMeta {
                        Text(meta)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if noteCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 9))
                            Text("\(noteCount)")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                AddToStackButton(highlightId: highlight.id)
                    .opacity(isHovered ? 1 : 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }

    private var primaryText: String {
        switch highlight.highlightType {
        case "screenshot": return "Screenshot"
        case "recording": return "Recording"
        case "file":
            let name = (highlight.contentText as NSString).lastPathComponent
            return name.isEmpty ? "File" : name
        default:
            let trimmed = highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "(empty)" : trimmed
        }
    }

    private var secondaryMeta: String? {
        var parts: [String] = []
        if let app = highlight.sourceApp, !app.isEmpty { parts.append(app) }
        if let short = CardMetadata.shortURL(from: highlight.sourceUrl) {
            parts.append(short)
        }
        if parts.isEmpty, let wt = highlight.windowTitle, !wt.isEmpty {
            parts.append(wt)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var timeString: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: highlight.date)
    }
}

// MARK: - Highlight Thumbnail Loader
//
// Shared image-loading pipeline for history-view previews. Tries the raw
// content path first (screenshots land there verbatim), falls back to
// LiveThumbnail for recordings/PDFs/other file types, then the persisted
// thumbnailPath on FileRecord. Returns nil for text-like highlights.

enum HighlightThumbnailLoader {
    static func load(for highlight: Highlight) async -> NSImage? {
        let path = highlight.contentText
        if let direct = await Task.detached(priority: .utility, operation: {
            NSImage(contentsOfFile: path)
        }).value {
            return direct
        }
        if let live = await LiveThumbnail.generate(for: URL(fileURLWithPath: path)) {
            return live
        }
        if let fileId = highlight.fileId,
           let rec = DatabaseManager.shared.fileRecord(byId: fileId),
           let thumbPath = rec.thumbnailPath {
            return await Task.detached(priority: .utility, operation: {
                NSImage(contentsOfFile: thumbPath)
            }).value
        }
        return nil
    }
}

// MARK: - History Row Thumbnail

private struct HistoryRowThumbnail: View {
    let highlight: Highlight
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(Rectangle())
                } else {
                    ZStack {
                        Rectangle().fill(iconBackground)
                        Image(systemName: iconName)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(iconColor)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(Rectangle())
        }
        .task(id: highlight.id) {
            guard image == nil, highlight.isMediaType else { return }
            image = await HighlightThumbnailLoader.load(for: highlight)
        }
    }

    private var iconName: String {
        switch highlight.highlightType {
        case "screenshot": return "photo"
        case "recording": return "video"
        case "highlight": return "quote.opening"
        case "note": return "square.and.pencil"
        case "file": return "doc"
        default: return highlight.isURLCopy ? "link" : "text.alignleft"
        }
    }

    private var iconColor: Color {
        switch highlight.highlightType {
        case "highlight": return .orange.opacity(0.85)
        case "note": return .blue.opacity(0.8)
        default:
            return highlight.isURLCopy ? .blue.opacity(0.75) : .secondary
        }
    }

    private var iconBackground: Color {
        switch highlight.highlightType {
        case "highlight": return .orange.opacity(0.1)
        case "note": return .blue.opacity(0.08)
        default:
            return highlight.isURLCopy ? Color.blue.opacity(0.07) : UITokens.chipFill
        }
    }
}

// MARK: - History Media Row (single wide inline preview)

private struct HistoryMediaRow: View {
    let highlight: Highlight
    var noteCount: Int = 0
    var onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HistoryMediaPreview(highlight: highlight, contentMode: .fit)
                .frame(maxWidth: 360, alignment: .leading)
                .frame(minHeight: 110, maxHeight: 200)
                .background(UITokens.surfaceBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
                )
                .overlay(alignment: .center) {
                    if highlight.highlightType == "recording" {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                    }
                }

            HStack(spacing: 8) {
                Text(primaryLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let meta = secondaryMeta {
                    Text(meta)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if noteCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 9))
                        Text("\(noteCount)")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                AddToStackButton(highlightId: highlight.id)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }

    private var primaryLabel: String {
        switch highlight.highlightType {
        case "screenshot": return "Screenshot"
        case "recording": return "Recording"
        case "file":
            let name = (highlight.contentText as NSString).lastPathComponent
            return name.isEmpty ? "File" : name
        default: return "Media"
        }
    }

    private var secondaryMeta: String? {
        var parts: [String] = []
        if let app = highlight.sourceApp, !app.isEmpty { parts.append(app) }
        if let short = CardMetadata.shortURL(from: highlight.sourceUrl) {
            parts.append(short)
        }
        return parts.isEmpty ? nil : "· " + parts.joined(separator: " · ")
    }

    private var timeString: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: highlight.date)
    }
}

// MARK: - History Media Strip (2+ consecutive media items)

private struct HistoryMediaStrip: View {
    let highlights: [Highlight]
    let onSelect: (Highlight) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 10, alignment: .top)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(highlights) { h in
                HistoryMediaTile(highlight: h)
                    .onTapGesture { onSelect(h) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

private struct HistoryMediaTile: View {
    let highlight: Highlight
    @State private var isHovered = false

    private let tileHeight: CGFloat = 110

    var body: some View {
        // Fixed-size container — no scaleEffect, so hover can't bleed into
        // neighbour cells. Hover state shifts the border/shadow only.
        ZStack(alignment: .bottom) {
            HistoryMediaPreview(highlight: highlight, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .bottom)

            HStack(spacing: 4) {
                if highlight.highlightType == "recording" {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(timeString)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Spacer(minLength: 0)
                AddToStackButton(highlightId: highlight.id)
                    .opacity(isHovered ? 1 : 0)
                    .colorScheme(.dark)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if highlight.highlightType == "recording" {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(height: tileHeight)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isHovered ? Color.accentColor.opacity(0.5) : UITokens.surfaceBorder,
                    lineWidth: isHovered ? 1 : 0.5
                )
        )
        .shadow(color: isHovered ? UITokens.shadowCard : .clear, radius: 4, y: 2)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in isHovered = hovering }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: highlight.date)
    }
}

// MARK: - History Media Preview (shared thumbnail view)

private struct HistoryMediaPreview: View {
    let highlight: Highlight
    let contentMode: ContentMode
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(Rectangle())
                } else {
                    ZStack {
                        Rectangle().fill(UITokens.chipFill)
                        Image(systemName: fallbackIcon)
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(Rectangle())
        }
        .task(id: highlight.id) {
            guard image == nil else { return }
            image = await HighlightThumbnailLoader.load(for: highlight)
        }
    }

    private var fallbackIcon: String {
        switch highlight.highlightType {
        case "screenshot": return "photo"
        case "recording": return "video"
        case "file": return "doc"
        default: return "photo"
        }
    }
}
