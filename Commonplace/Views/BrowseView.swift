import SwiftUI
import AppKit
import AVKit
import Combine
import UniformTypeIdentifiers
import PDFKit
import Quartz
import QuickLookThumbnailing
import MarkdownUI

// MARK: - Pinned floater placement

/// Which edge of the workspace the pinned-stack floater sits against.
/// Persisted via `@AppStorage` in `BrowseView`; toggled by tossing the
/// floater past the flip threshold or via the right-click context menu.
/// Which of the four corners of the archive surface the pinned-stack
/// floater currently lives in. Persisted via `@AppStorage` under a new
/// key (`pinnedFloaterCorner`) — existing users on the old two-state
/// `pinnedFloaterSide` key get the new default `.bottomTrailing`, which
/// matches their old `.trailing` behavior.
enum FloaterCorner: String {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }

    var hStackAlignment: HorizontalAlignment {
        switch self {
        case .topLeading, .bottomLeading: return .leading
        case .topTrailing, .bottomTrailing: return .trailing
        }
    }

    var isTop: Bool { self == .topLeading || self == .topTrailing }
    var isBottom: Bool { self == .bottomLeading || self == .bottomTrailing }
    var isLeading: Bool { self == .topLeading || self == .bottomLeading }
    var isTrailing: Bool { self == .topTrailing || self == .bottomTrailing }
}

// MARK: - Search result highlighting

/// Wraps `text` as an AttributedString with case-insensitive occurrences of
/// `query` visually highlighted. Returns a plain AttributedString when the
/// query is empty (no visible change) so card call sites can wrap every
/// rendered string unconditionally.
///
/// Used across `MasonryCard`, `ArchiveListView`, and their subtypes so
/// whatever field a search matched against gets surfaced visually — the
/// user can see at a glance *why* each card came back in the result set.
enum SearchHighlight {
    static func render(_ text: String, query: String) -> AttributedString {
        var attr = AttributedString(text)
        guard !query.isEmpty, !text.isEmpty else { return attr }
        let needle = query.lowercased()
        let haystack = text.lowercased()
        var searchStart = haystack.startIndex
        while let found = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            if let attrRange = Range(found, in: attr) {
                attr[attrRange].backgroundColor = Color.yellow.opacity(0.55)
                attr[attrRange].foregroundColor = .primary
            }
            searchStart = found.upperBound
        }
        return attr
    }
}

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
            VStack(alignment: .leading, spacing: 4) {
                Markdown(note.body)
                    .markdownTheme(.commonplaceMarginalia)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
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
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                // Thin neutral bar — same marginalia treatment used by
                // the timeline + stack list, so notes read as one
                // consistent vocabulary across surfaces.
                Rectangle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 1)
            }

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
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
    /// Total rows matching the current BrowseLoadRequest — decoupled from the
    /// paginated `highlights` slice so the footer shows the full dataset size
    /// rather than whatever has been scrolled into view so far.
    @State private var totalCaptureCount: Int = 0
    @State private var noteCounts: [String: Int] = [:]
    /// Full bodies of every note attached to a visible highlight, grouped
    /// by highlightId (oldest → newest). Populated alongside `noteCounts`
    /// in `loadCaptures`. The history list reads this to render each note
    /// inline so annotations read as first-class content, not a hidden
    /// count. Only history view consults it today; mosaic still uses
    /// `noteCounts` + `userNote` since cards don't have room for a stack.
    @State private var highlightNotes: [String: [HighlightNote]] = [:]
    @State private var aspectRatios: [String: CGFloat] = [:]
    /// Pre-resolved `CardSourceLink`s, keyed by highlight id. Populated in
    /// batches as pagination fetches more rows so per-card rendering doesn't
    /// have to re-run `FileManager.fileExists` or JSON-decode sourceContext
    /// on every hover / scroll tick.
    @State private var sourceLinks: [String: CardSourceLink] = [:]
    /// Pre-fetched `FileRecord`s for every file-type highlight on the page,
    /// keyed by the highlight's `fileId`. Without this, each `FileCard.task`
    /// fires its own `fileRecord(byId:)` query on mount — a 50-card page
    /// with ~20 file cards = 20+ serialized DB calls firing behind the
    /// render path. One batched query instead.
    @State private var fileRecords: [Int64: FileRecord] = [:]
    @State private var activeFilters: ActiveFilters = .init()
    @State private var appFacets: [AppFacet] = []
    @State private var typeCounts: [String: Int] = [:]
    @State private var isDropTargeted = false
    @State private var hasMore = false
    @State private var pinnedStack: Stack? = nil
    /// Ids of highlights currently in the pinned stack — drives the
    /// "already added" visual state on AddToStackButton.
    @State private var pinnedStackMembers: Set<String> = []
    /// Restored from disk on launch via `WorkspaceStateStore.load()`,
    /// falling back to the default single-pane / single-All-view
    /// workspace if nothing's persisted yet (or if the persisted shape
    /// fails validation — see `WorkspaceStateStore.validate`).
    @State private var workspaceState: WorkspaceState = WorkspaceStateStore.load() ?? .initial
    /// Debounces `WorkspaceStateStore.save` on workspace changes so a
    /// burst of mutations (e.g. tab drag → reorder → activate) writes
    /// once at the end instead of N times.
    @State private var workspacePersistTask: Task<Void, Never>? = nil
    /// Snapshot of the active stack tab's items at the moment a card
    /// detail was opened from it. Used as the gallery sibling list so
    /// arrow-key paging walks the stack rather than the unrelated
    /// archive. Reset to empty whenever the modal opens from anywhere
    /// else (a non-stack tab) so the archive list takes over instead.
    @State private var modalSourceStackItems: [Highlight] = []
    /// Workspace id threaded into `CardDetailView.inWorkspaceId` so a
    /// Phase D derive-from-selection auto-places the new card on the
    /// same canvas the parent was opened from. Set when the card is
    /// opened from a workspace tab; cleared when opened from anywhere
    /// else (archive, stack tab) so the derive flow doesn't
    /// accidentally place into a workspace the user wasn't even viewing.
    @State private var selectedHighlightWorkspaceId: String? = nil
    @State private var fullScreenImage: NSImage?
    @State private var footerBarFrame: CGRect = .zero
    /// Drawer state — a recent-stacks picker that slides in from the right
    /// when the user hovers the pinned floater (after a short delay) or
    /// clicks the chevron affordance. Used to swap the pinned stack
    /// without navigating away from the current view.
    @State private var drawerOpen = false
    @State private var drawerHoverTask: Task<Void, Never>? = nil

    /// Which side the pinned floater (and its drawer column) lands on.
    /// Persisted across launches so the user's preference sticks.
    /// Toggleable by tossing the floater past the threshold or via
    /// the right-click context menu on the floater.
    @AppStorage("pinnedFloaterCorner") private var pinnedFloaterCorner: FloaterCorner = .bottomTrailing
    /// Live drag offset while the user is "tossing" the floater toward
    /// the other side. Reset to zero (with a spring) on drag end —
    /// either the side flipped (and we land at the new anchor) or the
    /// drag was below threshold (and we snap back to where we started).
    @State private var floaterDragOffset: CGSize = .zero
    @State private var isDraggingFloater: Bool = false
    /// When non-nil, the stream was loaded as a windowed slice centered
    /// on this highlight — the user jumped here from a detail-view
    /// capture-event handle. Drives the "Back to newest" chip + changes
    /// infinite-scroll's "load older" boundary to continue from the
    /// window's tail.
    @State private var focusedHighlightId: String? = nil
    /// Set briefly after a scroll-to-target lands so the target card
    /// can flash an accent ring — helps the user's eye find where the
    /// view just jumped to. Cleared by a cancellable task, so rapid
    /// successive jumps don't fight each other over who wins the ring.
    @State private var jumpFlashId: String? = nil
    @State private var jumpFlashTask: Task<Void, Never>? = nil
    @State private var isWindowedMode = false
    /// True while the window's first row is older than the global newest,
    /// i.e. there's still room to page upward. Set when entering windowed
    /// mode, cleared when an upward fetch comes back short or when the
    /// stream resets to global-newest.
    @State private var hasNewer = false
    /// In-flight upward fetch. Tracked separately from `browseLoadTask`
    /// so the near-top trigger doesn't compete with the regular paging
    /// path's task slot. Bool is sufficient — only one upward fetch at
    /// a time, and we don't need to cancel it externally.
    @State private var newerLoadInFlight = false
    /// True once the archive is scrolled past `backToTopRevealOffset`.
    /// Drives the top-anchored Back-to-top pill (with its ⌘↑ shortcut
    /// chip) — hidden while the user is already at the top so it doesn't
    /// add chrome to the obvious case.
    @State private var isScrolledAwayFromTop = false
    private let backToTopRevealOffset: CGFloat = 200

    // (mosaic view was removed — All view is timeline-only)
    // (sticky overlay header was removed — `ArchiveListView` uses native
    // pinned section headers via `LazyVStack(pinnedViews:)`, so the
    // sticky behaviour lives inside the scroll content rather than as a
    // separate top-bar overlay. Eliminates the duplicate "current
    // chunk" label that used to appear in both surfaces.)

    /// Smaller than you'd expect because MasonryLayout measures every
    /// subview on state change — 20 cards is the sweet spot where the
    /// first paint feels instant across searches. Infinite scroll fills
    /// in more as the user scrolls past the viewport.
    private let pageSize = 20
    private let jumpWindowSize = 75
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
                // Pinned stack tap opens a fresh tab in whichever
                // pane is currently active. No teleport-to-existing.
                workspaceState.openTab(.stack(id: pinned.id))
            },
            // Pinned floater is workspace chrome — accidentally
            // grabbing it shouldn't kick off a CanvasDragItem(.stack)
            // drag that lights up every stack/canvas drop target on
            // the screen. The tap still opens the stack in a tab.
            isDraggable: false
        )
        .overlay(alignment: .topTrailing) {
            StackUnpinBadge {
                DatabaseManager.shared.setPinnedStack(id: nil)
            }
            .offset(x: 6, y: -6)
        }
        .overlay(alignment: .topLeading) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { drawerOpen.toggle() }
            } label: {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(UITokens.surfaceFloater))
                    .overlay(Circle().strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .offset(x: -6, y: -6)
            .help(drawerOpen ? "Hide recent stacks" : "Show recent stacks")
        }
        .id("pinned-stack-\(pinned.id)")
    }

    /// Alignment for the floater overlay frame. Maps the four-corner
    /// state directly to a SwiftUI `Alignment`.
    private var pinnedFloaterAlignment: Alignment {
        pinnedFloaterCorner.alignment
    }

    /// HStack alignment for the floater + drawer column. Mirrors the
    /// frame alignment so the drawer's cards line up flush with the
    /// floater on whichever side it's sitting.
    private var pinnedFloaterHStackAlignment: HorizontalAlignment {
        pinnedFloaterCorner.hStackAlignment
    }

    /// Drag-to-toss with 4-corner snap. The floater tracks the cursor
    /// freely in 2D during the drag; on release we project where the
    /// floater would *end up* if it kept moving with its current
    /// velocity (`predictedEndTranslation` — SwiftUI rolls the velocity
    /// into a residual translation) and snap to whichever screen
    /// quadrant that predicted center lands in. So a drag that ends
    /// slightly left of center but flicks rightward lands on a right
    /// corner, matching the user's spatial intent rather than the
    /// raw release point.
    private func floaterDragGesture(in containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !isDraggingFloater {
                    isDraggingFloater = true
                    if drawerOpen {
                        withAnimation(.easeInOut(duration: 0.15)) { drawerOpen = false }
                    }
                }
                // Track the full 2D translation — the floater follows
                // the cursor anywhere on the surface.
                floaterDragOffset = value.translation
            }
            .onEnded { value in
                let currentAnchor = Self.floaterAnchor(for: pinnedFloaterCorner, in: containerSize)
                let predictedCenter = CGPoint(
                    x: currentAnchor.x + value.predictedEndTranslation.width,
                    y: currentAnchor.y + value.predictedEndTranslation.height
                )
                let nextCorner = Self.nearestFloaterCorner(to: predictedCenter, in: containerSize)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    pinnedFloaterCorner = nextCorner
                    floaterDragOffset = .zero
                }
                isDraggingFloater = false
            }
    }

    /// Approximate on-screen center of the floater while at `corner`.
    /// `pad + half` accounts for the corner padding the overlay applies
    /// plus half the floater's footprint, giving a reasonable anchor
    /// for the predicted-center quadrant test.
    private static func floaterAnchor(for corner: FloaterCorner, in size: CGSize) -> CGPoint {
        let pad: CGFloat = 24
        let half: CGFloat = 60
        switch corner {
        case .topLeading:     return CGPoint(x: pad + half, y: pad + half)
        case .topTrailing:    return CGPoint(x: size.width - pad - half, y: pad + half)
        case .bottomLeading:  return CGPoint(x: pad + half, y: size.height - pad - half)
        case .bottomTrailing: return CGPoint(x: size.width - pad - half, y: size.height - pad - half)
        }
    }

    /// Pick the corner whose quadrant contains the predicted center.
    /// Velocity-weighting falls out naturally because the caller passes
    /// `currentAnchor + predictedEndTranslation`, and predicted-end
    /// already factors in residual velocity.
    private static func nearestFloaterCorner(to point: CGPoint, in size: CGSize) -> FloaterCorner {
        let isLeft = point.x < size.width / 2
        let isTop = point.y < size.height / 2
        switch (isLeft, isTop) {
        case (true, true):   return .topLeading
        case (false, true):  return .topTrailing
        case (true, false):  return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }

    /// Floater hover: entering opens the drawer immediately; leaving
    /// schedules a close after a short debounce so moving the cursor into
    /// the drawer column doesn't flicker it shut.
    private func handleFloaterHover(_ hovering: Bool) {
        drawerHoverTask?.cancel()
        if hovering {
            if drawerOpen { return }
            drawerOpen = true
        } else {
            guard drawerOpen else { return }
            let task = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                if Task.isCancelled { return }
                drawerOpen = false
            }
            drawerHoverTask = task
        }
    }

    /// Drawer hover: entering cancels any pending close so the column
    /// stays open while the cursor is over a card. Leaving schedules a
    /// short-debounced close — a re-enter (into the column or back onto
    /// the floater) cancels the pending close.
    private func handleDrawerHover(_ hovering: Bool) {
        drawerHoverTask?.cancel()
        if hovering { return }
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
            drawerOpen = false
        }
        drawerHoverTask = task
    }

    // MARK: - Computed

    private var browseLoadRequest: BrowseLoadRequest {
        BrowseLoadRequest(
            searchText: searchText,
            activeFilters: activeFilters
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

    /// The "+" add tile pins to the top-left of the masonry in every mosaic
    /// filter state. Adding a note under a non-.all filter doesn't guarantee
    /// the new note lands in the filtered bucket (it's typed as .copy so it
    /// only shows under All/Copies), but keeping the affordance always
    /// reachable is worth the mild semantic slippage.
    private var showAddTile: Bool { true }

    /// Currently-active tab content across the workspace. Used to drive
    /// sidebar selection and to decide which sibling list a card-detail
    /// modal walks via arrow keys.
    private var activeTabContent: WorkspaceTabContent? {
        workspaceState.activePane?.activeTab?.content
    }

    // MARK: - Body

    var body: some View {
        WorkspaceView(
            state: $workspaceState,
            pinnedStackId: pinnedStack?.id,
            onTogglePinForStack: { stackId in
                let alreadyPinned = pinnedStack?.id == stackId
                DatabaseManager.shared.setPinnedStack(id: alreadyPinned ? nil : stackId)
            }
        ) { content, paneId, tabId in
            tabBody(for: content, paneId: paneId, tabId: tabId)
        }
        .onChange(of: activeFilters) { _, _ in
            guard isActive else { return }
            loadCaptures(reset: true)
        }
        // Inline search field is gone — search lives in the sidebar
        // now (Cmd+F). `searchText` stays as a dead `""` so the
        // existing BrowseLoadRequest construction keeps working
        // without a fork; it just always takes the filter-only path.
        .coordinateSpace(name: "BrowseRootSpace")
        .onPreferenceChange(BrowseFooterBarFramePreferenceKey.self) { footerBarFrame = $0 }
        .onChange(of: workspaceState) { _, newState in
            // Debounce a burst of mutations (drag-and-drop reorders,
            // tab close cascades, divider drags) into one disk write.
            workspacePersistTask?.cancel()
            workspacePersistTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                WorkspaceStateStore.save(newState)
            }
        }
        .onAppear {
            isActive = true
            DatabaseManager.shared.pruneEmptyStacks()
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
        .onReceive(NotificationCenter.default.publisher(for: .workspaceCommandNewTab).receive(on: DispatchQueue.main)) { _ in
            workspaceState.openTab(.newTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceCommandCloseActiveTab).receive(on: DispatchQueue.main)) { _ in
            guard let pane = workspaceState.activePane else { return }
            pruneIfClosedWorkspace(workspaceState.closeTab(paneId: pane.id, tabId: pane.activeTabId))
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceCommandNextTab).receive(on: DispatchQueue.main)) { _ in
            shiftActiveTab(by: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceCommandPrevTab).receive(on: DispatchQueue.main)) { _ in
            shiftActiveTab(by: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceCommandSelectTab).receive(on: DispatchQueue.main)) { note in
            guard let index = note.userInfo?["index"] as? Int else { return }
            selectTab(at: index)
        }
        .onReceive(NotificationCenter.default.publisher(for: .highlightDidSave).throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)) { _ in
            guard isActive else { return }
            loadCaptures(reset: true)
            refreshSidebarData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .searchSidebarJumpToHighlight).receive(on: DispatchQueue.main)) { note in
            guard isActive else { return }
            guard let id = note.userInfo?["highlightId"] as? String else { return }
            guard let target = DatabaseManager.shared.highlight(byId: id) else { return }
            jumpToHighlight(target)
        }
        .onReceive(NotificationCenter.default.publisher(for: .highlightDataDidChange).receive(on: DispatchQueue.main)) { notification in
            guard isActive else { return }
            let userInfo = notification.userInfo ?? [:]
            let hid = userInfo["highlightId"] as? String
            let change = userInfo["change"] as? String ?? ""

            // Targeted refresh for the affected highlight's cached state.
            if let hid {
                // A change to notes / annotations changes the card's
                // natural height, so drop the memoized height for this
                // id. (NSCache prefix-delete isn't a thing, so we flush
                // the whole cache — cheap to rebuild on next render.)
                MasonryHeightCache.invalidate(id: hid)
                switch change {
                case "notes":
                    let counts = DatabaseManager.shared.noteCountsForHighlights(ids: [hid])
                    noteCounts[hid] = counts[hid] ?? 0
                    // Refresh the full inline-note list for this highlight so
                    // the history view reflects the add/delete immediately.
                    let fetched = DatabaseManager.shared.notesForHighlights(ids: [hid])
                    highlightNotes[hid] = fetched[hid] ?? []
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
                // Annotation changes resize the card. The `MasonryHeightCache.invalidate`
                // call above clears the stale entry; the next layout pass will
                // re-measure via `sizeThatFits` and refill the cache.
            }

            // Sidebar counts always refresh — cheap indexed scans.
            refreshSidebarData()

            if browseLoadRequest.shouldReloadOnHighlightMutation(change: change) {
                loadCaptures(reset: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: BrowseWindowController.showSettingsNotification)) { _ in
            // Settings is special — there's only ever one settings
            // surface globally, so prefer focusing an existing tab if
            // any. Falls back to opening fresh in the active pane.
            if !workspaceState.focusExisting(.settings) {
                workspaceState.openTab(.settings)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stackDataDidChange).receive(on: DispatchQueue.main)) { _ in
            // @State dedupes equal writes (Stack, Set<String> are Equatable),
            // so direct assignment won't re-render when nothing changed.
            pinnedStack = DatabaseManager.shared.pinnedStack()
            pinnedStackMembers = DatabaseManager.shared.highlightIdsInPinnedStack()
            // Drop any stack tab whose underlying stack has been deleted
            // (e.g. merged away). The vanish callback inside StackBody also
            // handles this for the actively-rendered tab; this catches
            // background tabs the user hasn't switched to recently.
            pruneVanishedStackTabs()
        }
        .onReceive(NotificationCenter.default.publisher(for: BrowseWindowController.showHighlightDetailNotification)) { notification in
            guard let highlightId = notification.userInfo?["highlightId"] as? String,
                  let highlight = DatabaseManager.shared.highlight(byId: highlightId) else { return }
            // Reset filters so the item is visible in the background list
            // once the detail overlay is dismissed.
            activeFilters = .init()
            searchText = ""
            isActive = true
            loadCaptures(reset: true)
            withAnimation(.easeInOut(duration: 0.2)) { selectedHighlight = highlight }
        }
        .overlay { cardDetailOverlay }
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
        // Pinned stack floater + stack-switch column — rendered as the
        // topmost overlay so they're always reachable, even when a
        // highlight or stack detail view is open on top of the archive.
        // The column (when open) sits directly above the floater in the
        // same VStack so it reads as "more pinned-style tiles stacked
        // above the pinned one," like messages rising from a chat input.
        // Side (leading vs trailing) is user-toggleable — drag the
        // floater past the threshold toward the other edge to "toss"
        // it across; persists in @AppStorage.
        .overlay(alignment: pinnedFloaterAlignment) {
            if let pinned = pinnedStack {
                GeometryReader { geo in
                    VStack(alignment: pinnedFloaterHStackAlignment, spacing: 8) {
                        // Drawer + floater stack order depends on which
                        // half of the screen the floater lives in. At a
                        // bottom corner the drawer "rises" above the
                        // floater (chat-input metaphor); at a top corner
                        // it "descends" below so the column doesn't run
                        // off-screen.
                        if pinnedFloaterCorner.isBottom {
                            if drawerOpen {
                                drawerView(for: pinned, in: geo.size)
                            }
                            floaterView(for: pinned, in: geo.size)
                        } else {
                            floaterView(for: pinned, in: geo.size)
                            if drawerOpen {
                                drawerView(for: pinned, in: geo.size)
                            }
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: pinnedFloaterAlignment
                    )
                    // Uniform 24pt corner inset on the leading/trailing
                    // edge the floater hugs; bottom corners also clear
                    // the footer bar.
                    .padding(.leading, pinnedFloaterCorner.isLeading ? 24 : 0)
                    .padding(.trailing, pinnedFloaterCorner.isTrailing ? 24 : 0)
                    .padding(.top, pinnedFloaterCorner.isTop ? 24 : 0)
                    .padding(.bottom, pinnedFloaterCorner.isBottom ? footerBarFrame.height + 16 : 0)
                }
            }
        }
        // Membership of the pinned stack flows through the environment so
        // every AddToStackButton below — in masonry, history, pinned
        // origin breadcrumb, card detail, stack detail — renders its
        // "in stack" state without needing the set threaded as a prop.
        .environment(\.pinnedStackMembers, pinnedStackMembers)
    }

    // MARK: - Floater + drawer subviews

    /// The pinned-stack pill itself, with the 4-corner drag gesture and
    /// a context menu that lets the user jump directly to any corner
    /// without dragging.
    @ViewBuilder
    private func floaterView(for pinned: Stack, in containerSize: CGSize) -> some View {
        pinnedStackFloater(pinned)
            .transition(.move(edge: pinnedFloaterCorner.isBottom ? .bottom : .top).combined(with: .opacity))
            .offset(floaterDragOffset)
            .simultaneousGesture(floaterDragGesture(in: containerSize))
            .contextMenu {
                cornerMenuButton("Top left", target: .topLeading)
                cornerMenuButton("Top right", target: .topTrailing)
                cornerMenuButton("Bottom left", target: .bottomLeading)
                cornerMenuButton("Bottom right", target: .bottomTrailing)
            }
    }

    @ViewBuilder
    private func cornerMenuButton(_ label: String, target: FloaterCorner) -> some View {
        Button(label) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                pinnedFloaterCorner = target
            }
        }
        .disabled(pinnedFloaterCorner == target)
    }

    /// The stack-switch column. Sits above the floater at bottom corners
    /// and below at top corners (set by the parent VStack ordering).
    @ViewBuilder
    private func drawerView(for pinned: Stack, in containerSize: CGSize) -> some View {
        StackDrawer(
            currentPinnedId: pinned.id,
            maxColumnHeight: max(120, containerSize.height - footerBarFrame.height - 240),
            onPick: { stack in
                DatabaseManager.shared.setPinnedStack(id: stack.id)
                withAnimation(.easeInOut(duration: 0.2)) { drawerOpen = false }
            },
            onDismiss: {
                withAnimation(.easeInOut(duration: 0.2)) { drawerOpen = false }
            },
            onHoverChange: { _ in }
        )
        .transition(.move(edge: pinnedFloaterCorner.isBottom ? .bottom : .top).combined(with: .opacity))
    }

    // MARK: - Card tap routing

    private func routeCardTap(_ highlight: Highlight) {
        withAnimation(.easeInOut(duration: 0.2)) { selectedHighlight = highlight }
    }

    /// Dismiss the item detail. The source tab stays visible underneath
    /// the modal at all times now, so closing simply drops the modal —
    /// no more origin-stack restoration dance.
    private func dismissHighlight() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedHighlight = nil
            modalSourceStackItems = []
            selectedHighlightWorkspaceId = nil
        }
    }

    /// Item-detail modal extracted from the main `body` overlay. Lives
    /// here so the body's @ViewBuilder chain stays inside the type
    /// checker's reach — embedding the full CardDetailView call (9
    /// argument labels + 5 trailing modifiers) inside the body's nested
    /// .overlay/.if/ZStack tree blew the type-check budget when Phase D
    /// added one more argument to the call.
    @ViewBuilder
    private var cardDetailOverlay: some View {
        if let highlight = selectedHighlight {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { dismissHighlight() }

                CardDetailView(
                    highlight: highlight,
                    onDismiss: { dismissHighlight() },
                    onStackNavigation: { stack in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedHighlight = nil
                            modalSourceStackItems = []
                            selectedHighlightWorkspaceId = nil
                        }
                        workspaceState.openTab(.stack(id: stack.id))
                    },
                    onImageFullscreen: { image in
                        withAnimation(.easeInOut(duration: 0.2)) { fullScreenImage = image }
                    },
                    siblings: siblings(for: highlight),
                    onNavigate: { sibling in
                        selectedHighlight = sibling
                    },
                    onJumpTo: { target in
                        jumpToHighlight(target)
                    },
                    onRevealInAll: { target in
                        revealInAll(target)
                    },
                    onAddFilter: { filter in
                        applyDetailFilter(filter)
                    },
                    inWorkspaceId: selectedHighlightWorkspaceId
                )
                .id(highlight.id)
                .frame(maxWidth: 700, maxHeight: .infinity)
                .background(Color(.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 4)
                .padding(40)
            }
            .transition(.opacity)
            .onExitCommand { dismissHighlight() }
        }
    }

    /// Re-center the archive on `target` — the user clicked a handle in
    /// the capture-events section to jump back to that moment. Fetches a
    /// windowed slice (75 newer + center + 75 older), swaps `highlights`
    /// for it, and animates the scroll. `onChange(of: focusedHighlightId)`
    /// drives the actual `scrollTo(_, anchor: .center)` so the view has
    /// the new rows in its layout before the animation runs.
    private func jumpToHighlight(_ target: Highlight) {
        selectedHighlight = nil
        modalSourceStackItems = []

        // Widen to the full archive — a target from a different filter
        // wouldn't otherwise be present in `filteredHighlights`.
        activeFilters = .init()
        searchText = ""

        let window = DatabaseManager.shared.highlightsWindow(
            centerTimestamp: target.timestamp,
            before: jumpWindowSize,
            after: jumpWindowSize
        )

        highlights = window
        highlightsOffset = window.count
        hasMore = !window.isEmpty
        isWindowedMode = true
        // Assume more newer rows exist until an upward fetch proves
        // otherwise. The window center is rarely exactly at the global
        // newest, so this is a safe default.
        hasNewer = true
        totalCaptureCount = DatabaseManager.shared.browseHighlightsCount(
            BrowseLoadRequest(searchText: "", activeFilters: .init())
        )
        focusedHighlightId = target.id
    }

    /// "Show in All" from a card-detail header: ensure the All tab is
    /// active, drop any origin-stack sibling context, and scroll-snap to
    /// the target. Works whether the modal was opened from the All tab
    /// (archive already mounted) or from a stack tab (archive needs to
    /// mount first). We clear `focusedHighlightId` so the subsequent
    /// assign inside `jumpToHighlight` is always a real change — otherwise
    /// re-revealing the same item would be a no-op. The deferred dispatch
    /// lets the tab swap mount the ScrollViewReader before we set the
    /// focus id it listens for.
    private func revealInAll(_ target: Highlight) {
        focusedHighlightId = nil
        modalSourceStackItems = []
        // Make sure the active pane has an All-view tab. If one
        // already exists in any pane, focus it (jump-to-moment is an
        // explicit "show me this" action — landing the user on a
        // pre-existing All view feels right). Otherwise open fresh
        // in the active pane.
        if !workspaceState.focusExisting(.allView) {
            workspaceState.openTab(.allView)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            jumpToHighlight(target)
        }
    }

    /// Apply a "filter the All view by this metadata value" intent
    /// raised by a CardDetailView funnel button. Dismisses the detail
    /// modal, ensures an All-view tab is active, and inserts the value
    /// into the right `ActiveFilters` facet. The pill bar shows the new
    /// constraint immediately and the masonry reloads via the existing
    /// `.onChange(of: activeFilters)` path.
    private func applyDetailFilter(_ filter: CardDetailFilter) {
        dismissHighlight()
        if !workspaceState.focusExisting(.allView) {
            workspaceState.openTab(.allView)
        }
        switch filter {
        case .app(let name):
            activeFilters.apps.insert(name)
        case .url(let url):
            activeFilters.urls.insert(url)
        }
    }

    /// Shift the active pane's active tab by `delta`, wrapping at both
    /// ends. Drives `⌘⇧]` / `⌘⇧[` from the Tab menu.
    private func shiftActiveTab(by delta: Int) {
        guard let pane = workspaceState.activePane else { return }
        guard let paneIdx = workspaceState.panes.firstIndex(where: { $0.id == pane.id }) else { return }
        let tabs = pane.tabs
        guard !tabs.isEmpty else { return }
        guard let currentIdx = tabs.firstIndex(where: { $0.id == pane.activeTabId }) else { return }
        let count = tabs.count
        let next = ((currentIdx + delta) % count + count) % count
        workspaceState.panes[paneIdx].activeTabId = tabs[next].id
    }

    /// Jump to the Nth (0-indexed) tab in the active pane. No-op when
    /// the pane has fewer tabs than the requested index. Drives
    /// `⌘1..9` from the Tab menu.
    private func selectTab(at index: Int) {
        guard let pane = workspaceState.activePane else { return }
        guard let paneIdx = workspaceState.panes.firstIndex(where: { $0.id == pane.id }) else { return }
        guard pane.tabs.indices.contains(index) else { return }
        workspaceState.panes[paneIdx].activeTabId = pane.tabs[index].id
    }

    /// Scroll the All-view archive back to its first row. When in
    /// windowed mode (i.e. the user jumped to a moment via "Show in
    /// All"), this also resets the stream to the global newest-first
    /// view — the user expects "back to top" to mean "back to the
    /// freshest captures", not "the top of this random window slice".
    private func jumpToTop(proxy: ScrollViewProxy) {
        if isWindowedMode {
            isWindowedMode = false
            hasNewer = false
            highlightsOffset = 0
            loadCaptures(reset: true)
            // Defer the scroll a runloop tick so the new (reset)
            // highlights are mounted before scrollTo resolves the id.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let firstId = highlights.first?.id {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(firstId, anchor: .top)
                    }
                }
            }
            return
        }
        guard let firstId = filteredHighlights.first?.id else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(firstId, anchor: .top)
        }
    }

    /// Ordered list of items the user can page through with arrow keys
    /// while `highlight` is on screen. When the modal was opened from a
    /// stack tab, the snapshot taken at open time wins; otherwise the
    /// currently-filtered archive list is used. Arrow nav quietly no-ops
    /// when the list has only the current item or doesn't contain it.
    private func siblings(for highlight: Highlight) -> [Highlight] {
        if !modalSourceStackItems.isEmpty,
           modalSourceStackItems.contains(where: { $0.id == highlight.id }) {
            return modalSourceStackItems
        }
        return highlights
    }

    /// Sweep stack tabs that no longer correspond to a real stack and
    /// close them. Called from .stackDataDidChange so a deleted/merged
    /// stack doesn't leave a dangling tab pointing at nothing.
    private func pruneVanishedStackTabs() {
        var deletions: [(paneId: UUID, tabId: UUID)] = []
        for pane in workspaceState.panes {
            for tab in pane.tabs {
                if case .stack(let id) = tab.content,
                   DatabaseManager.shared.stack(byId: id) == nil {
                    deletions.append((pane.id, tab.id))
                }
            }
        }
        for d in deletions {
            workspaceState.closeTab(paneId: d.paneId, tabId: d.tabId)
        }
    }

    // MARK: - Tab body dispatch

    /// Map a tab content case onto its body. The All-view tab reuses the
    /// archive masonry; stack tabs render `StackBody`; the new-tab chooser
    /// renders `NewTabChooser` and self-closes (or replaces itself) on
    /// pick; settings reuses `SettingsView`. The pane/tab IDs are threaded
    /// through so bodies that need to mutate their own slot in the
    /// workspace tree (currently just the chooser) don't have to re-locate
    /// themselves on every render.
    @ViewBuilder
    private func tabBody(for content: WorkspaceTabContent, paneId: UUID, tabId: UUID) -> some View {
        switch content {
        case .allView:
            archiveBody
        case .stack(let id):
            stackTabBody(id: id)
        case .newTab:
            NewTabChooser(onPick: { picked in
                handleChooserPick(picked, paneId: paneId, tabId: tabId)
            })
        case .settings:
            ScrollView {
                SettingsView()
                    .frame(maxWidth: 500)
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(UITokens.surfaceBackground)
        case .workspace(let id):
            WorkspaceCanvasView(
                workspaceId: id,
                onOpenHighlight: { highlight in
                    // Same channel All view + StackBody use — the
                    // CardDetailView modal is owned at the BrowseView
                    // level so every body type opens the same overlay.
                    // Stamp the workspace id so a Phase D derive lands
                    // a placement on this canvas next to the parent.
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedHighlightWorkspaceId = id
                        selectedHighlight = highlight
                    }
                }
            )
        }
    }

    /// Resolve a chooser selection. The user clicked "+" in a specific
    /// pane and picked some content — the chooser tab in THAT pane
    /// becomes the picked content in place. No pane teleporting, no
    /// dedup against existing tabs. Multiple instances of the same
    /// content across panes are explicitly allowed.
    private func handleChooserPick(_ picked: WorkspaceTabContent, paneId: UUID, tabId: UUID) {
        workspaceState.replaceContent(paneId: paneId, tabId: tabId, newContent: picked)
    }

    @ViewBuilder
    private func stackTabBody(id: String) -> some View {
        if let stack = DatabaseManager.shared.stack(byId: id) {
            StackBody(
                stack: stack,
                onOpenHighlight: { highlight in
                    let items = DatabaseManager.shared.highlightsForStack(stackId: stack.id)
                    modalSourceStackItems = items
                    withAnimation(.easeInOut(duration: 0.2)) { selectedHighlight = highlight }
                },
                onOpenSubstack: { child in
                    workspaceState.openTab(.stack(id: child.id))
                },
                onStackVanished: {
                    // Close every tab anywhere in the workspace that
                    // points to this vanished stack.
                    var closures: [(UUID, UUID)] = []
                    for pane in workspaceState.panes {
                        for tab in pane.tabs where tab.content == .stack(id: id) {
                            closures.append((pane.id, tab.id))
                        }
                    }
                    for (paneId, tabId) in closures {
                        workspaceState.closeTab(paneId: paneId, tabId: tabId)
                    }
                },
                onOpenOriginWorkspace: { workspaceId in
                    workspaceState.openTab(.workspace(id: workspaceId))
                }
            )
        } else {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.stack.badge.minus")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("This stack is no longer available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(UITokens.surfaceBackground)
        }
    }

    /// The classic browse archive: empty state OR masonry/history of
    /// captures, with a search/count footer at the bottom and drag-and-
    /// drop import support across the whole surface.
    private var archiveBody: some View {
        ZStack(alignment: .bottom) {
            UITokens.surfaceBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                AllViewFilterBar(
                    activeFilters: $activeFilters,
                    appFacets: appFacets,
                    typeCounts: typeCounts,
                    candidateCount: { candidate in
                        var test = activeFilters
                        switch candidate {
                        case .type(let t):
                            // Already-selected candidates report the current
                            // result count rather than a "what if added"
                            // figure (since adding a present value is a
                            // no-op under AND semantics).
                            test.types.insert(t)
                        case .app(let a):
                            test.apps.insert(a)
                        }
                        return DatabaseManager.shared.browseHighlightsCount(
                            BrowseLoadRequest(searchText: searchText, activeFilters: test)
                        )
                    }
                )

                if filteredHighlights.isEmpty {
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
                    ScrollViewReader { proxy in
                        ScrollView {
                            ArchiveListView(
                                highlights: filteredHighlights,
                                highlightNotes: highlightNotes,
                                noteCounts: noteCounts,
                                onSelect: { highlight in
                                    routeCardTap(highlight)
                                },
                                onApproachEnd: {
                                    if hasMore { loadCaptures(reset: false) }
                                }
                            )
                            .padding(.bottom, pinnedStack != nil ? 220 : 0)
                            .animation(nil, value: pinnedStack)
                        }
                        // Persistent vertical scroller. Default `.automatic`
                        // hid the indicator unless actively scrolling, which
                        // read as "the scrollbar doesn't work" — the bar
                        // simply wasn't on screen long enough to grab.
                        .scrollIndicators(.visible, axes: .vertical)
                        .overlay(alignment: .top) {
                            if isScrolledAwayFromTop {
                                BackToTopChip(action: { jumpToTop(proxy: proxy) })
                                    .padding(.top, 12)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .background(
                            // Invisible ⌘↑ keyboard binding scoped to the
                            // archive ScrollView. Lives in the background
                            // so it doesn't add chrome but participates
                            // in the window's command table while the
                            // archive is on screen.
                            Button("") { jumpToTop(proxy: proxy) }
                                .keyboardShortcut(.upArrow, modifiers: .command)
                                .opacity(0)
                                .accessibilityHidden(true)
                                .frame(width: 0, height: 0)
                                .allowsHitTesting(false)
                        )
                        .onScrollGeometryChange(for: Bool.self) { geo in
                            let bottomEdge = geo.contentOffset.y + geo.containerSize.height
                            let threshold = geo.contentSize.height - 400
                            return bottomEdge >= threshold
                        } action: { _, isNearBottom in
                            if isNearBottom && hasMore {
                                loadCaptures(reset: false)
                            }
                        }
                        .onScrollGeometryChange(for: Bool.self) { geo in
                            geo.contentOffset.y > backToTopRevealOffset
                        } action: { _, scrolled in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isScrolledAwayFromTop = scrolled
                            }
                        }
                        .onScrollGeometryChange(for: Bool.self) { geo in
                            geo.contentOffset.y < 400
                        } action: { _, isNearTop in
                            if isNearTop && isWindowedMode && hasNewer {
                                loadNewerCaptures(proxy: proxy)
                            }
                        }
                        .onChange(of: focusedHighlightId) { _, newValue in
                            guard let id = newValue else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                            // Flash the arriving card so the eye can
                            // latch onto it after the scroll lands.
                            jumpFlashTask?.cancel()
                            jumpFlashTask = Task {
                                try? await Task.sleep(for: .milliseconds(280))
                                guard !Task.isCancelled else { return }
                                await MainActor.run { jumpFlashId = id }
                                try? await Task.sleep(for: .milliseconds(950))
                                guard !Task.isCancelled else { return }
                                await MainActor.run { jumpFlashId = nil }
                            }
                        }
                    }
                }

                Divider()
                HStack(spacing: 8) {
                    Button(action: {
                        NotificationCenter.default.post(name: .toggleSearchSidebar, object: nil)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text("Search")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text("⌘F")
                                .font(.system(size: 10))
                                .foregroundStyle(.quaternary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Open search (⌘F)")

                    Spacer()

                    Text("\(totalCaptureCount) captures")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if isReloadingCaptures {
                        ProgressView()
                            .controlSize(.small)
                    }
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
            // Internal cross-pane drop. Cards / stacks dragged from
            // anywhere also land here — semantically a no-op (the
            // archive already holds every captured card by definition)
            // but accepted so the All-view follows the same
            // unopinionated "every list takes drops" rule as workspaces
            // and stacks.
            .dropDestination(for: CanvasDragItem.self) { items, _ in
                CaptureLog.info("[all-view drop] received \(items.count) item(s) — no-op (already in archive)")
                return !items.isEmpty
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
        }
    }

    // MARK: - Data Loading

    private func loadCaptures(reset: Bool) {
        guard isActive else { return }
        if reset {
            browseLoadGeneration += 1
            browseLoadTask?.cancel()
            hasMore = false
            // Only show the spinner if the query is still running after
            // 200ms. Fast searches (FTS5 + small page) finish in <50ms,
            // and flashing the spinner for every keystroke reads as lag.
            let spinnerGen = browseLoadGeneration
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                if spinnerGen == browseLoadGeneration && browseLoadTask != nil {
                    isReloadingCaptures = true
                }
            }
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
            let batchIds = batch.map(\.id)

            // Stage instrumentation — one log line per search tells us
            // exactly where time is going when the user perceives lag.
            // Cheap to leave on; flip to `.debug` if noise ever matters.
            let stageStart = Date()
            let t0 = Date()
            let newCounts = db.noteCountsForHighlights(ids: batchIds)
            let tCounts = Int(Date().timeIntervalSince(t0) * 1000)
            let t1 = Date()
            let newNotes = db.notesForHighlights(ids: batchIds)
            let tNotes = Int(Date().timeIntervalSince(t1) * 1000)
            let t2 = Date()
            let newRatios = db.aspectRatiosForHighlights(ids: batchIds)
            let tRatios = Int(Date().timeIntervalSince(t2) * 1000)
            let t3 = Date()
            // Resolve source links here (off the render path). Runs
            // `FileManager.fileExists` checks + JSON decode in a batch so
            // MasonryCard's body no longer burns syscalls on every render.
            let newSourceLinks = CardSourceLinkResolver.resolveBatch(batch)
            let tSource = Int(Date().timeIntervalSince(t3) * 1000)
            let t4 = Date()
            // Batch-fetch FileRecords so FileCards don't each fire their
            // own DB query on mount.
            let fileIds = batch.compactMap(\.fileId)
            let newFileRecords = db.fileRecords(byIds: fileIds)
            let tFiles = Int(Date().timeIntervalSince(t4) * 1000)
            let tBatchTotal = Int(Date().timeIntervalSince(stageStart) * 1000)
            CaptureLog.info("[search stage] batch queries total=\(tBatchTotal)ms (noteCounts=\(tCounts)ms notes=\(tNotes)ms ratios=\(tRatios)ms sourceLinks=\(tSource)ms fileRecords=\(tFiles)ms) batch=\(batch.count) rows")

            guard !Task.isCancelled else { return }

            let tMain = Date()
            await MainActor.run {
                guard generation == browseLoadGeneration else { return }

                // Phase 1 — render the mosaic as soon as rows + batches
                // are in hand. Count + facets follow in phase 2 so the
                // user isn't blocked on a full-table count/group-by for
                // the initial paint.
                //
                // Dedupe by id: an in-flight paginated load can race with
                // a reset triggered by .highlightDidSave /
                // .highlightDataDidChange, and real-time inserts can
                // shift rows so the same id appears on consecutive OFFSET
                // pages. Either way, duplicate ids in ForEach give
                // undefined layout (overlapping masonry cards).
                if reset {
                    highlights = batch
                    highlightsOffset = batch.count
                    sourceLinks = newSourceLinks
                    fileRecords = newFileRecords
                } else {
                    let existingIds = Set(highlights.map(\.id))
                    let newRows = batch.filter { !existingIds.contains($0.id) }
                    highlights.append(contentsOf: newRows)
                    highlightsOffset += batch.count
                    sourceLinks.merge(newSourceLinks) { _, new in new }
                    fileRecords.merge(newFileRecords) { _, new in new }
                }
                hasMore = batch.count == limit
                noteCounts.merge(newCounts) { _, new in new }
                if reset {
                    highlightNotes = newNotes
                } else {
                    highlightNotes.merge(newNotes) { _, new in new }
                }
                aspectRatios.merge(newRatios) { _, new in new }
                isReloadingCaptures = false
                browseLoadTask = nil
            }
            let tMainTotal = Int(Date().timeIntervalSince(tMain) * 1000)
            CaptureLog.info("[search stage] phase 1 main-actor write: \(tMainTotal)ms")

            // Phase 2 — count + facets. Waits 300ms before running so
            // rapid typing doesn't trigger the facet GROUP BY per
            // keystroke. Every new keystroke cancels this task; only
            // when typing settles does phase 2 actually run. This was
            // the second full SwiftUI body re-eval per keystroke —
            // splitting it off from the critical path halves the
            // render-pipeline work during active typing.
            guard reset, !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let tPhase2 = Date()
            let tFacets0 = Date()
            let facets = shouldRefreshFacets
                ? db.appFacets(request)
                : [(appName: String, bundleId: String?, count: Int)]()
            let tFacets = Int(Date().timeIntervalSince(tFacets0) * 1000)
            let tCount0 = Date()
            let total = db.browseHighlightsCount(request)
            let tCount = Int(Date().timeIntervalSince(tCount0) * 1000)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard generation == browseLoadGeneration else { return }
                if shouldRefreshFacets {
                    appFacets = facets.map {
                        AppFacet(appName: $0.appName, bundleId: $0.bundleId, count: $0.count)
                    }
                }
                totalCaptureCount = total
            }
            let tPhase2Total = Int(Date().timeIntervalSince(tPhase2) * 1000)
            CaptureLog.info("[search stage] phase 2 count+facets: total=\(tPhase2Total)ms (facets=\(tFacets)ms count=\(tCount)ms)")
        }
        browseLoadTask = task
    }

    /// Page upward in windowed mode: fetch up to `pageSize` rows newer
    /// than the current top row's timestamp and prepend them. Anchors
    /// the scroll position to the previous top row so the user's view
    /// doesn't visibly jump when the new rows insert above.
    private func loadNewerCaptures(proxy: ScrollViewProxy) {
        guard isWindowedMode, hasNewer, !newerLoadInFlight,
              let topTimestamp = highlights.first?.timestamp,
              let anchorId = highlights.first?.id else { return }
        newerLoadInFlight = true
        let limit = pageSize

        Task.detached(priority: .userInitiated) {
            let db = DatabaseManager.shared
            let batch = db.highlightsNewer(thanTimestamp: topTimestamp, limit: limit)
            let batchIds = batch.map(\.id)
            let counts = db.noteCountsForHighlights(ids: batchIds)
            let notes = db.notesForHighlights(ids: batchIds)
            let ratios = db.aspectRatiosForHighlights(ids: batchIds)
            let links = CardSourceLinkResolver.resolveBatch(batch)
            let fileIds = batch.compactMap(\.fileId)
            let files = db.fileRecords(byIds: fileIds)

            await MainActor.run {
                defer { newerLoadInFlight = false }
                guard isWindowedMode else { return }
                let existingIds = Set(highlights.map(\.id))
                let newRows = batch.filter { !existingIds.contains($0.id) }
                guard !newRows.isEmpty else {
                    hasNewer = false
                    return
                }
                highlights = newRows + highlights
                noteCounts.merge(counts) { _, n in n }
                highlightNotes.merge(notes) { _, n in n }
                aspectRatios.merge(ratios) { _, n in n }
                sourceLinks.merge(links) { _, n in n }
                fileRecords.merge(files) { _, n in n }
                hasNewer = newRows.count == limit
                // Re-anchor on the row that was previously at the top so
                // the user's visible position doesn't shift down by the
                // height of the prepended batch. No animation — this is
                // a positional correction, not a user gesture.
                proxy.scrollTo(anchorId, anchor: .top)
            }
        }
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

/// LayoutValueKey that MasonryCard uses to publish its `highlight.id` to
/// the surrounding `MasonryLayout`. Gives the layout a stable identity
/// per subview so it can memoize per-card heights across searches —
/// when the same card reappears in a later result set, its height is a
/// dict lookup instead of a fresh `sizeThatFits` walk.
private struct MasonryCardIdKey: LayoutValueKey {
    static let defaultValue: String? = nil
}

/// Process-wide height memo keyed by (highlight.id, columnWidth bucket).
/// Bucketing tolerates width drift during drag without blowing the cache
/// — critical for smooth pane-divider resize where colWidth can shift
/// by several pt per frame. The 8pt bucket means a card measured at
/// 380pt is reused at 372–387pt without re-measurement; the visible
/// height difference for a 7pt width change is sub-pt for text and a
/// fraction of a line for images, imperceptible during live drag and
/// resolved via re-measure once the drag crosses a bucket boundary.
private enum MasonryHeightCache {
    private static let cache: NSCache<NSString, NSNumber> = {
        let c = NSCache<NSString, NSNumber>()
        c.countLimit = 5000
        return c
    }()

    /// Pt-width bucket size. Higher = more cache hits during drag,
    /// at the cost of slightly stale heights between bucket boundaries.
    private static let bucketSize: Int = 8

    static func key(id: String, colWidth: CGFloat) -> NSString {
        let bucket = Int((colWidth / CGFloat(bucketSize)).rounded()) * bucketSize
        return "\(id)|\(bucket)" as NSString
    }

    static func cached(id: String, colWidth: CGFloat) -> CGFloat? {
        guard let v = cache.object(forKey: key(id: id, colWidth: colWidth)) else { return nil }
        return CGFloat(v.doubleValue)
    }

    static func store(_ h: CGFloat, id: String, colWidth: CGFloat) {
        cache.setObject(NSNumber(value: Double(h)), forKey: key(id: id, colWidth: colWidth))
    }

    static func invalidate(id: String) {
        // No fast prefix removal on NSCache; clearing the whole cache
        // is cheap enough for the rare invalidation (note edit,
        // annotation change). Alternative would be to keep a parallel
        // dict but that duplicates state.
        cache.removeAllObjects()
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
        /// Hash of the subview-id sequence seen at last full measure.
        /// When the current sequence matches, we know the content is
        /// identical and can reuse `heights` verbatim. Prevents the
        /// earlier bug where subview-count-matches-but-content-differs
        /// gave wrong layouts.
        var contentHash: Int = 0
        var assignments: [(col: Int, y: CGFloat)] = []
        var contentHeight: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> CacheData { CacheData() }

    /// Build a hash over subview identities. Subviews publish their
    /// `highlight.id` through `MasonryCardIdKey`; the AddTile publishes
    /// no id, so it hashes to a stable sentinel. Any reordering or
    /// content swap flips the hash and forces a full re-measure.
    private func subviewsHash(_ subviews: Subviews) -> Int {
        var hasher = Hasher()
        for s in subviews {
            hasher.combine(s[MasonryCardIdKey.self] ?? "__addtile__")
        }
        return hasher.finalize()
    }

    /// Three-tier height resolution:
    ///   1. `MasonryCardHeightKey` — pre-computed in pure Swift by
    ///      `MasonryHeightComputer`, pushed down via layoutValue. Zero
    ///      SwiftUI measurement. This is the fast path we want every
    ///      card to hit.
    ///   2. `MasonryHeightCache` — id-keyed memo of a prior SwiftUI
    ///      measurement. Catches cards that arrived without a
    ///      pre-computed height (race at first render).
    ///   3. `sizeThatFits` fallback — the expensive walk, only taken
    ///      when both upstream paths miss. Results backfill (2).
    private func measureHeights(subviews: Subviews, colWidth: CGFloat) -> [CGFloat] {
        // Heights come from SwiftUI's own `sizeThatFits` (accurate by
        // definition — that's the same value used to render). The
        // id-keyed cache memoizes the result so subsequent layout
        // passes are an O(1) dict lookup. The pre-compute path that
        // tried to bypass `sizeThatFits` was removed: SwiftUI's
        // resolved fonts (`design: .serif` → New York on modern
        // macOS) don't match the NSFont we measured against, which
        // produced under-estimated heights and visible card overlap.
        return subviews.map { s -> CGFloat in
            if let id = s[MasonryCardIdKey.self],
               let cached = MasonryHeightCache.cached(id: id, colWidth: colWidth) {
                return cached
            }
            let measured = s.sizeThatFits(.init(width: colWidth, height: nil)).height
            let h = measured.isFinite ? measured : 0
            if let id = s[MasonryCardIdKey.self] {
                MasonryHeightCache.store(h, id: id, colWidth: colWidth)
            }
            return h
        }
    }

    private func refreshCache(
        for totalWidth: CGFloat,
        subviews: Subviews,
        cache: inout CacheData
    ) {
        let columns = columnCount(for: totalWidth)
        let colWidth = columnWidth(for: totalWidth, columns: columns)
        let hash = subviewsHash(subviews)

        // Fast path — identical content + same column count, with
        // colWidth drift up to 8pt. Skips every `sizeThatFits` walk.
        // The 8pt tolerance is the difference between smooth and
        // stuttery during pane-divider drag: a fast drag shifts each
        // pane's width by 3-6pt per frame, far past the old 1pt
        // tolerance. Heights cached at the previous width remain
        // accurate enough at the new width that the visible result
        // is indistinguishable from a full re-measure during the
        // drag, and the layout snaps tight on `onEnd` when the user
        // releases. Beyond 8pt, fall through to the full re-measure
        // path so column-count changes (or genuine resize) get
        // accurate layout.
        if !cache.heights.isEmpty,
           cache.contentHash == hash,
           cache.heights.count == subviews.count,
           cache.columns == columns,
           abs(cache.columnWidth - colWidth) < 8.0 {
            let (colHeights, assignments) = layout(columns: columns, colWidth: colWidth, heights: cache.heights)
            cache.measuredWidth = totalWidth
            cache.columnWidth = colWidth
            cache.assignments = assignments
            cache.contentHeight = colHeights.max() ?? 0
            return
        }

        // Full re-measure, but each per-subview call checks the shared
        // id-keyed height cache first — so even this "slow" path is
        // often a dict lookup per card when the user is running a new
        // search that surfaces cards they've seen before.
        let heights = measureHeights(subviews: subviews, colWidth: colWidth)
        let (colHeights, assignments) = layout(columns: columns, colWidth: colWidth, heights: heights)
        cache.measuredWidth = totalWidth
        cache.columns = columns
        cache.columnWidth = colWidth
        cache.heights = heights
        cache.contentHash = hash
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
        // Route through `refreshCache` so the drag-tight fast path kicks
        // in. When SwiftUI's layout hasn't changed width between
        // `sizeThatFits` and here (the normal case), `refreshCache` is a
        // no-op that reuses the existing heights. Async image loads that
        // landed between passes are handled by SwiftUI re-invoking
        // `sizeThatFits` with a fresh layout pass, which invalidates the
        // cache via the subview count or width deltas.
        refreshCache(for: bounds.width, subviews: subviews, cache: &cache)
        let colWidth = cache.columnWidth
        for (i, subview) in subviews.enumerated() {
            let a = cache.assignments[i]
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
enum CardSourceLink: Equatable {
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
    /// Pre-resolved source link for this highlight, computed off the render
    /// path by BrowseView's pagination pipeline. When nil, no hover pill is
    /// shown. See `CardSourceLinkResolver` — this used to be a computed
    /// property that ran two `FileManager.fileExists` syscalls per render.
    var sourceLink: CardSourceLink? = nil
    /// Pre-fetched FileRecord for file-type highlights. When nil, FileCard
    /// falls back to its own DB lookup on mount (keeps the legacy
    /// fileRecordByPath fallback path intact for orphan highlights).
    var fileRecord: FileRecord? = nil
    /// Current search query. When non-empty, cards render their visible
    /// text via `SearchHighlight.render` so matches highlight in the
    /// actual rendered field — body, filename, link title, annotation,
    /// etc. Empty string is a no-op.
    var searchQuery: String = ""
    @State private var isHovered = false
    @State private var isLinkHovered = false

    private var hasAnnotation: Bool {
        if let note = highlight.userNote, !note.isEmpty { return true }
        return false
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

            if hasAnnotation || noteCount > 1 {
                VStack(alignment: .leading, spacing: 5) {
                    if hasAnnotation {
                        Text(SearchHighlight.render(highlight.userNote ?? "", query: searchQuery))
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
        .contentShape(RoundedRectangle(cornerRadius: UITokens.radiusCard))
        .overlay(alignment: .bottomTrailing) {
            AddToStackButton(highlightId: highlight.id, style: .overlay)
                .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            if let link = sourceLink, isHovered, highlight.isURLCopy {
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
        // Drag this card to a workspace canvas (creates a placement) or
        // to another stack (adds membership). Uses `Transferable` with a
        // private custom UTType so external apps don't see the payload.
        .draggable(CanvasDragItem(kind: .highlight, id: highlight.id))
        // Publish the highlight id so `MasonryLayout` can memoize
        // height across relayouts via `MasonryHeightCache`.
        .layoutValue(key: MasonryCardIdKey.self, value: highlight.id)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch highlight.highlightType {
        case "screenshot":
            ScreenshotCard(highlight: highlight, preferredAspectRatio: preferredAspectRatio)
        case "recording":
            ScreenshotCard(highlight: highlight, preferredAspectRatio: preferredAspectRatio)
        case "highlight":
            HighlightCard(highlight: highlight, searchQuery: searchQuery)
        case "note":
            NoteCard(highlight: highlight, searchQuery: searchQuery)
        case "file":
            FileCard(highlight: highlight, preferredAspectRatio: preferredAspectRatio, prefetchedRecord: fileRecord, searchQuery: searchQuery)
        default:
            if highlight.isURLCopy {
                LinkCard(highlight: highlight, preferredAspectRatio: preferredAspectRatio, searchQuery: searchQuery)
            } else {
                TextCard(highlight: highlight, searchQuery: searchQuery)
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
                        .clipped()
                } else {
                    placeholder
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                overlay
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
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
                image = await CardImageCache.load(path: path)
                if image == nil {
                    image = await LiveThumbnail.generate(for: URL(fileURLWithPath: path))
                }
                if image == nil, let fileId = highlight.fileId,
                   let rec = DatabaseManager.shared.fileRecord(byId: fileId),
                   let thumbPath = rec.thumbnailPath {
                    image = await CardImageCache.load(path: thumbPath)
                }
            }
        }
    }
}

// MARK: - Card Image Cache

/// Process-wide NSCache for card thumbnails. Without this, tab toggles (All
/// → Stacks → All) hard-unmount the archive mosaic via PaneView's `.id`
/// switch, and every MasonryCard's `.task { }` re-decodes its image from
/// disk on the return trip — a 500-card archive burns a massive spike.
/// Keyed by absolute file path so both `NSImage(contentsOfFile:)` call
/// sites and `LiveThumbnail` share entries.
enum CardImageCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 2000
        return c
    }()

    static func cached(path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    static func store(_ image: NSImage, path: String) {
        cache.setObject(image, forKey: path as NSString)
    }

    /// Cache-aware convenience for the common `NSImage(contentsOfFile:)`
    /// pattern. Returns cached value synchronously if present, otherwise
    /// loads off-main and stores the result before returning.
    static func load(path: String) async -> NSImage? {
        if let cached = cached(path: path) { return cached }
        let loaded = await Task.detached(priority: .utility) {
            NSImage(contentsOfFile: path)
        }.value
        if let loaded { store(loaded, path: path) }
        return loaded
    }
}

// MARK: - Live Thumbnail Fallback

/// Generates a preview image on demand for videos and PDFs when the cached
/// `thumbnailPath` is missing or the file at that path cannot be loaded.
/// Used by RecordingCard and FileCard so the masonry always shows a real
/// preview instead of an icon placeholder.
enum LiveThumbnail {
    static func generate(for fileURL: URL) async -> NSImage? {
        let path = fileURL.path
        if let cached = CardImageCache.cached(path: path) { return cached }

        let ext = fileURL.pathExtension.lowercased()
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let result = await generateUncached(fileURL: fileURL, ext: ext)
        if let result { CardImageCache.store(result, path: path) }
        return result
    }

    private static func generateUncached(fileURL: URL, ext: String) async -> NSImage? {
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
    var searchQuery: String = ""

    var body: some View {
        if TextHighlightRouter.isImageFilePath(highlight.contentText) {
            ScreenshotCard(highlight: highlight)
        } else {
            let style = TextCardStyle.style(for: highlight.contentText)
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 2)

                Text(SearchHighlight.render(highlight.contentText, query: searchQuery))
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
    var searchQuery: String = ""

    var body: some View {
        if TextHighlightRouter.isImageFilePath(highlight.contentText) {
            ScreenshotCard(highlight: highlight)
        } else {
            let style = TextCardStyle.style(for: highlight.contentText)
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.orange.opacity(0.8))
                    .frame(width: 2)

                Text(SearchHighlight.render(highlight.contentText, query: searchQuery))
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
    /// Result is a pure function of `text` (path existence doesn't flip mid-
    /// session in any meaningful way for a capture archive), so we cache by
    /// content string. Avoids re-running `FileManager.fileExists` on every
    /// hover-driven body re-eval of TextCard / HighlightCard.
    private static let cache = NSCache<NSString, NSNumber>()

    static func isImageFilePath(_ text: String) -> Bool {
        let key = text as NSString
        if let cached = cache.object(forKey: key) { return cached.boolValue }
        let result = compute(text)
        cache.setObject(NSNumber(value: result), forKey: key)
        return result
    }

    private static func compute(_ text: String) -> Bool {
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
    var searchQuery: String = ""

    var body: some View {
        let style = TextCardStyle.style(for: highlight.contentText)
        Text(SearchHighlight.render(highlight.contentText, query: searchQuery))
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
    /// Pre-fetched from BrowseView's pagination pipeline. When provided,
    /// `.task` skips the per-mount DB lookup entirely and goes straight to
    /// thumbnail loading.
    var prefetchedRecord: FileRecord? = nil
    var searchQuery: String = ""
    @State private var thumbnail: NSImage?
    @State private var resolvedRecord: FileRecord?
    /// Memoized `NSWorkspace.icon(forFile:)` result. Resolved once in
    /// `.task` and reused across hover-driven body re-evals. Without this
    /// the placeholder's `Image(nsImage: systemFileIcon)` call re-hits the
    /// workspace icon subsystem on every hover tick.
    @State private var cachedIcon: NSImage?

    private var fileRecord: FileRecord? { prefetchedRecord ?? resolvedRecord }

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
            Text(SearchHighlight.render(
                fileRecord?.fileName ?? URL(fileURLWithPath: highlight.contentText).lastPathComponent,
                query: searchQuery
            ))
                .font(.caption)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 2)

        }
        .task {
            // Resolve the FileRecord: prefer BrowseView's prefetched batch,
            // then the foreign key, then a path lookup for highlights
            // inserted before the FK fix.
            let rec: FileRecord?
            if let pre = prefetchedRecord {
                rec = pre
            } else {
                var r: FileRecord?
                if let fId = highlight.fileId {
                    r = DatabaseManager.shared.fileRecord(byId: fId)
                }
                if r == nil {
                    r = DatabaseManager.shared.fileRecordByPath(highlight.contentText)
                }
                rec = r
                resolvedRecord = rec
            }
            guard let rec else { return }

            if let thumbPath = rec.thumbnailPath {
                thumbnail = await CardImageCache.load(path: thumbPath)
            }
            // Always try a live preview for videos/PDFs when the cached
            // thumbnail is missing or failed to load.
            if thumbnail == nil {
                thumbnail = await LiveThumbnail.generate(for: URL(fileURLWithPath: rec.filePath))
            }
            // Resolve the placeholder icon once — the body will read the
            // cached value regardless of whether the thumbnail ended up
            // being shown.
            cachedIcon = resolveSystemIcon(for: rec)
        }
    }

    private var systemFileIcon: NSImage {
        cachedIcon ?? NSWorkspace.shared.icon(for: .data)
    }

    private func resolveSystemIcon(for rec: FileRecord) -> NSImage {
        let path = highlight.contentText
        if FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        if let ext = rec.fileExtension,
           let utType = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: utType)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
}

// MARK: - Link Host Cache

/// Memoized host-label resolution for LinkCard (and its variants). The
/// parse+replace runs every body eval before `preview` arrives, and for
/// cards that never fetch a preview it would run forever. Since the result
/// is a pure function of `urlString`, stash it in a shared NSCache.
private enum LinkHostCache {
    private static let cache = NSCache<NSString, NSString>()

    static func host(for urlString: String) -> String {
        let key = urlString as NSString
        if let cached = cache.object(forKey: key) { return cached as String }
        let host = URL(string: urlString)?.host?.replacingOccurrences(of: "www.", with: "") ?? urlString
        cache.setObject(host as NSString, forKey: key)
        return host
    }
}

// MARK: - Link Card

private struct LinkCard: View {
    let highlight: Highlight
    /// Pre-resolved intrinsic aspect ratio for the link's hero image, from
    /// BrowseView's batch map. See ScreenshotCard for the rationale.
    var preferredAspectRatio: CGFloat? = nil
    var searchQuery: String = ""
    @State private var preview: LinkPreview?
    @State private var heroImage: NSImage?
    @State private var faviconImage: NSImage?
    @State private var didLoad = false

    private var urlString: String {
        highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayHost: String {
        preview?.siteName ?? LinkHostCache.host(for: urlString)
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
                    Text(SearchHighlight.render(displayHost, query: searchQuery))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(SearchHighlight.render(displayTitle, query: searchQuery))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)

                if let desc = preview?.ogDescription, !desc.isEmpty {
                    Text(SearchHighlight.render(desc, query: searchQuery))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }

                if let app = highlight.sourceApp {
                    Text(SearchHighlight.render(app, query: searchQuery))
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
                self.heroImage = await CardImageCache.load(path: path)
            }
            if let path = fetched?.faviconPath {
                self.faviconImage = await CardImageCache.load(path: path)
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
        preview?.siteName ?? LinkHostCache.host(for: urlString)
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
                self.heroImage = await CardImageCache.load(path: path)
            }
            if let path = fetched?.faviconPath {
                self.faviconImage = await CardImageCache.load(path: path)
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
    /// Hover-revealed "filter All view by this URL" affordance. When
    /// supplied, the funnel button appears at the trailing edge — its
    /// click adds the URL to `ActiveFilters.urls` and dismisses the
    /// detail modal. Tapping the body of the preview itself still
    /// opens the URL in the browser, the existing primary action.
    var onAddFilter: (() -> Void)? = nil
    @State private var preview: LinkPreview?
    @State private var heroImage: NSImage?
    @State private var faviconImage: NSImage?
    @State private var didLoad = false
    @State private var isHovered = false

    private var displayHost: String {
        preview?.siteName ?? LinkHostCache.host(for: urlString)
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
                    if onAddFilter != nil {
                        FilterByFunnelButton(help: "Filter All view by this URL") {
                            onAddFilter?()
                        }
                        .opacity(isHovered ? 1 : 0)
                        .allowsHitTesting(isHovered)
                    }
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
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
            }
            .task {
                let fetched = await LinkPreviewStore.shared.preview(for: urlString)
                self.preview = fetched
                self.didLoad = true
                if let path = fetched?.imagePath {
                    self.heroImage = await CardImageCache.load(path: path)
                }
                if let path = fetched?.faviconPath {
                    self.faviconImage = await CardImageCache.load(path: path)
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
                .foregroundStyle(isHovered ? Color.primary : Color.primary.opacity(0.5))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                )
                .contentShape(Rectangle())
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

/// Top-anchored pill that scrolls the archive back to its first row.
/// Shown only after the user has scrolled `backToTopRevealOffset` away
/// from the top, so it never adds chrome to the "I'm already at the
/// top" case. Surfaces the ⌘↑ shortcut inline as a small kbd-style
/// chip — clicking the pill and pressing the shortcut do the same thing.
private struct BackToTopChip: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.to.line")
                    .font(.system(size: 11, weight: .semibold))
                Text("Back to top")
                    .font(.system(size: 12, weight: .medium))
                shortcutChip
            }
            .foregroundStyle(isHovered ? .primary : .secondary)
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(UITokens.surfaceFloater)
                    .shadow(color: UITokens.shadowFloater, radius: 6, y: 2)
            )
            .overlay(
                Capsule()
                    .strokeBorder(UITokens.surfaceBorderStrong, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Scroll to the most recent capture (⌘↑)")
    }

    private var shortcutChip: some View {
        Text("⌘↑")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
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

// MARK: - Highlight Thumbnail Loader
//
// Shared image-loading pipeline for capture previews (mosaic, list-row
// thumbnails, search sidebar). Tries the raw
// content path first (screenshots land there verbatim), falls back to
// LiveThumbnail for recordings/PDFs/other file types, then the persisted
// thumbnailPath on FileRecord. Returns nil for text-like highlights.

enum HighlightThumbnailLoader {
    static func load(for highlight: Highlight) async -> NSImage? {
        let path = highlight.contentText
        if let direct = await CardImageCache.load(path: path) {
            return direct
        }
        if let live = await LiveThumbnail.generate(for: URL(fileURLWithPath: path)) {
            return live
        }
        if let fileId = highlight.fileId,
           let rec = DatabaseManager.shared.fileRecord(byId: fileId),
           let thumbPath = rec.thumbnailPath {
            return await CardImageCache.load(path: thumbPath)
        }
        return nil
    }
}

