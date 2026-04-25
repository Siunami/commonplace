import SwiftUI
import AppKit

/// Top-level workspace surface. Renders an arbitrary number of panes
/// side-by-side as two stacked rows: a 28pt tab-strip row and a body
/// row. Both rows share the same per-pane width fractions (from
/// `state.paneWidths`), so vertical dividers between adjacent panes
/// stay visually continuous between chrome and content.
///
/// Owns no data — all state mutations route through the `state`
/// binding. The `tabBody` builder is supplied by the caller so the
/// workspace stays agnostic about per-tab data dependencies.
struct WorkspaceView<Body: View>: View {
    @Binding var state: WorkspaceState
    /// Id of the currently pinned stack — passed through to each pane's
    /// tab strip so stack tab pills can render the correct pin glyph.
    var pinnedStackId: String?
    /// Callback invoked when a pin button on a stack tab is tapped.
    var onTogglePinForStack: (String) -> Void = { _ in }
    /// Builder for one tab's body. Receives the tab's content plus the
    /// owning pane's id and the tab's id, so bodies that need to
    /// self-mutate (e.g. the new-tab chooser) can do so without
    /// re-locating themselves in the workspace tree.
    @ViewBuilder var tabBody: (WorkspaceTabContent, UUID, UUID) -> Body

    private let dividerWidth: CGFloat = 6
    private let tabRowHeight: CGFloat = 28
    private let edgeZoneWidth: CGFloat = 90
    /// Floor on a pane's pixel width during divider drag. Below this
    /// the drag refuses to shrink either neighbour. Mirrors Obsidian's
    /// hard min so users can't drag panes into invisibility.
    private let minPanePixelWidth: CGFloat = 150

    /// (paneIndex, side) — the workspace paints a translucent ghost
    /// half-pane on the targeted side of the targeted pane while a
    /// tab drag hovers an edge drop zone. nil = no drag in progress
    /// or no edge currently targeted.
    @State private var targetedSplit: (paneIndex: Int, side: SplitSide)? = nil

    /// Temporary in-flight pane widths during an active divider drag.
    /// Writes here stay local — the parent binding `state.paneWidths`
    /// is only touched on `onEnd`. Keeps drag smooth by not rippling
    /// every tick up through `state` and re-rendering the entire
    /// downstream view tree.
    @State private var liveWidths: [Double]? = nil

    private var effectiveWidths: [Double] {
        let widths = liveWidths ?? state.paneWidths
        // Defend against shape mismatch between local + canonical
        // arrays during transitions (pane added/removed mid-drag).
        if widths.count == state.panes.count { return widths }
        return state.paneWidths.count == state.panes.count
            ? state.paneWidths
            : Array(repeating: 1.0 / Double(max(1, state.panes.count)), count: state.panes.count)
    }

    // MARK: - Search sidebar

    @AppStorage("searchSidebarOpen") private var sidebarOpen: Bool = false
    @AppStorage("searchSidebarWidth") private var sidebarWidth: Double = 320
    private let sidebarMinWidth: Double = 240
    private let sidebarMaxWidth: Double = 520

    @State private var liveSidebarWidth: Double? = nil

    private var effectiveSidebarWidth: Double {
        liveSidebarWidth ?? sidebarWidth
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if sidebarOpen {
                    SearchSidebarView(onClose: { sidebarOpen = false })
                        .frame(width: effectiveSidebarWidth)
                    DividerHandle(
                        onDrag: { delta in
                            let current = liveSidebarWidth ?? sidebarWidth
                            liveSidebarWidth = max(sidebarMinWidth, min(sidebarMaxWidth, current + Double(delta)))
                        },
                        onEnd: {
                            if let final = liveSidebarWidth { sidebarWidth = final }
                            liveSidebarWidth = nil
                        }
                    )
                    .frame(width: dividerWidth)
                }
                paneArea(in: geo)
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSearchSidebar)) { _ in
                sidebarOpen.toggle()
            }
        }
    }

    // MARK: - Pane area layout

    @ViewBuilder
    private func paneArea(in geo: GeometryProxy) -> some View {
        let consumedByLeftRail = sidebarOpen ? effectiveSidebarWidth + Double(dividerWidth) : 0
        let availableWidth = max(1, geo.size.width - CGFloat(consumedByLeftRail))
        // The total width consumed by N-1 inter-pane dividers reduces
        // the pixel space distributed across panes by their fractions.
        let dividerCount = max(0, state.panes.count - 1)
        let dividersTotal = CGFloat(dividerCount) * dividerWidth
        let paneSpace = max(1, availableWidth - dividersTotal)
        let widths = effectiveWidths
        let pixelWidths: [CGFloat] = (0..<state.panes.count).map { idx in
            paneSpace * CGFloat(widths.indices.contains(idx) ? widths[idx] : 1.0 / Double(state.panes.count))
        }

        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                tabRow(pixelWidths: pixelWidths, totalW: availableWidth)
                bodyRow(pixelWidths: pixelWidths, totalW: availableWidth, height: geo.size.height - tabRowHeight)
            }

            if let target = targetedSplit, target.paneIndex < pixelWidths.count {
                splitGhost(
                    paneIndex: target.paneIndex,
                    side: target.side,
                    pixelWidths: pixelWidths,
                    totalHeight: geo.size.height
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: targetedSplit?.paneIndex)
    }

    // MARK: - Tab row

    @ViewBuilder
    private func tabRow(pixelWidths: [CGFloat], totalW: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(state.panes.enumerated()), id: \.element.id) { idx, pane in
                paneTabStrip(pane)
                    .frame(width: pixelWidths.indices.contains(idx) ? pixelWidths[idx] : 0)
                if idx < state.panes.count - 1 {
                    paneDivider(at: idx, totalW: totalW)
                        .frame(width: dividerWidth)
                }
            }
        }
        .frame(height: tabRowHeight)
        .background(UITokens.surfaceCard)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(UITokens.surfaceBorder)
                .frame(height: 0.5)
        }
    }

    // MARK: - Body row

    @ViewBuilder
    private func bodyRow(pixelWidths: [CGFloat], totalW: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(state.panes.enumerated()), id: \.element.id) { idx, pane in
                paneBody(pane)
                    .frame(width: pixelWidths.indices.contains(idx) ? pixelWidths[idx] : 0, height: height)
                    .overlay(alignment: .leading) {
                        edgeSplitZone(paneIndex: idx, side: .leading, height: height)
                    }
                    .overlay(alignment: .trailing) {
                        edgeSplitZone(paneIndex: idx, side: .trailing, height: height)
                    }
                if idx < state.panes.count - 1 {
                    paneDivider(at: idx, totalW: totalW)
                        .frame(width: dividerWidth, height: height)
                }
            }
        }
    }

    // MARK: - Divider drag

    /// One divider between pane[index] and pane[index+1]. During drag,
    /// only those two pane widths shift — others stay fixed. Local
    /// `liveWidths` array isolates the per-tick writes from `state`,
    /// so the parent view tree doesn't invalidate on every pixel.
    @ViewBuilder
    private func paneDivider(at index: Int, totalW: CGFloat) -> some View {
        DividerHandle(
            onDrag: { delta in
                let baseline = liveWidths ?? state.paneWidths
                guard baseline.count == state.panes.count,
                      baseline.indices.contains(index),
                      baseline.indices.contains(index + 1) else { return }
                // Convert the pixel delta into a fraction of total
                // pane space, then shift it from one neighbour to the
                // other while clamping both above the min-pixel floor.
                let dividerCount = CGFloat(max(0, state.panes.count - 1))
                let paneSpace = max(1, totalW - dividerCount * dividerWidth)
                let fractionDelta = Double(delta) / Double(paneSpace)
                let minFraction = Double(minPanePixelWidth) / Double(paneSpace)
                var next = baseline
                let leftCandidate = next[index] + fractionDelta
                let rightCandidate = next[index + 1] - fractionDelta
                if leftCandidate < minFraction || rightCandidate < minFraction { return }
                next[index] = leftCandidate
                next[index + 1] = rightCandidate
                liveWidths = next
            },
            onEnd: {
                if let final = liveWidths { state.setPaneWidths(final) }
                liveWidths = nil
            }
        )
    }

    // MARK: - Edge drop zones

    /// Per-pane drop zone on left/right edge. Drop on the leading edge
    /// of pane[i] inserts a new pane at index `i`; drop on trailing
    /// edge inserts at `i+1`. The whole workspace shows a translucent
    /// half-pane preview on the targeted side of the targeted pane
    /// while the drag hovers.
    @ViewBuilder
    private func edgeSplitZone(paneIndex: Int, side: SplitSide, height: CGFloat) -> some View {
        EdgeDropZone(
            width: edgeZoneWidth,
            height: height,
            side: side,
            onTargetedChange: { hovering in
                if hovering {
                    targetedSplit = (paneIndex: paneIndex, side: side)
                } else if let current = targetedSplit,
                          current.paneIndex == paneIndex && current.side == side {
                    targetedSplit = nil
                }
            },
            onDrop: { payload in
                let insertAt = side == .leading ? paneIndex : paneIndex + 1
                state.splitWithMovedTab(
                    fromPane: payload.paneId,
                    tabId: payload.tabId,
                    insertingAt: insertAt
                )
                targetedSplit = nil
            }
        )
    }

    // MARK: - Split ghost preview

    /// Translucent half-pane preview painted over the targeted pane
    /// while a tab drag hovers an edge drop zone.
    @ViewBuilder
    private func splitGhost(
        paneIndex: Int,
        side: SplitSide,
        pixelWidths: [CGFloat],
        totalHeight: CGFloat
    ) -> some View {
        if pixelWidths.indices.contains(paneIndex) {
            let xOffset: CGFloat = (0..<paneIndex).reduce(0) { acc, i in
                acc + pixelWidths[i] + dividerWidth
            }
            let paneWidth = pixelWidths[paneIndex]
            let halfWidth = paneWidth * 0.5
            let ghostX = side == .leading ? xOffset : xOffset + paneWidth - halfWidth

            ZStack {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.14))
                Rectangle()
                    .strokeBorder(
                        Color.accentColor.opacity(0.65),
                        style: StrokeStyle(lineWidth: 2, dash: [10, 5])
                    )
                VStack(spacing: 8) {
                    Image(systemName: side == .leading ? "rectangle.lefthalf.filled" : "rectangle.righthalf.filled")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Color.accentColor.opacity(0.85))
                    Text("New pane")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor.opacity(0.9))
                }
            }
            .frame(width: halfWidth, height: totalHeight)
            .offset(x: ghostX, y: 0)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Per-pane components

    @ViewBuilder
    private func paneBody(_ pane: WorkspacePane) -> some View {
        PaneView(
            pane: pane,
            isActivePane: pane.id == state.activePaneId,
            onActivatePane: { state.activePaneId = pane.id },
            tabBody: tabBody
        )
    }

    @ViewBuilder
    private func paneTabStrip(_ pane: WorkspacePane) -> some View {
        TabStrip(
            pane: pane,
            isActivePane: pane.id == state.activePaneId,
            pinnedStackId: pinnedStackId,
            showsClosePane: state.panes.count > 1,
            onActivateTab: { tabId in
                state.activePaneId = pane.id
                if let idx = state.panes.firstIndex(where: { $0.id == pane.id }) {
                    state.panes[idx].activeTabId = tabId
                }
            },
            onCloseTab: { tabId in
                state.closeTab(paneId: pane.id, tabId: tabId)
            },
            onContextAction: { action, tabId in
                switch action {
                case .openInSplit:
                    // Same semantics as a drag-to-trailing-edge: split
                    // off the tab into a new pane immediately to the
                    // right of this one.
                    if let idx = state.panes.firstIndex(where: { $0.id == pane.id }) {
                        state.splitWithMovedTab(fromPane: pane.id, tabId: tabId, insertingAt: idx + 1)
                    }
                case .close:
                    state.closeTab(paneId: pane.id, tabId: tabId)
                }
            },
            onAddTab: {
                state.activePaneId = pane.id
                state.openTab(.newTab, inPane: pane.id)
            },
            onSplit: {
                // Spawn a new pane to the right of this one, seeded
                // with a fresh chooser. The new pane becomes active.
                if let idx = state.panes.firstIndex(where: { $0.id == pane.id }) {
                    state.insertPane(at: idx + 1, withTab: .newTab)
                }
            },
            onClosePane: {
                state.closePane(paneId: pane.id)
            },
            onTogglePinForStack: onTogglePinForStack,
            onDropTab: { payload, insertIndex in
                state.moveTab(
                    fromPane: payload.paneId,
                    tabId: payload.tabId,
                    toPane: pane.id,
                    atIndex: insertIndex
                )
            }
        )
    }
}

// MARK: - Divider handle

/// Thin vertical handle between adjacent panes. Wide hit area (6pt)
/// but visually a 1pt rule with hover feedback. Drag to redistribute
/// the two adjacent pane widths; clamped at the layout layer.
private struct DividerHandle: View {
    var onDrag: (CGFloat) -> Void
    /// Fires once when the drag ends so the caller can commit any
    /// local-only live state back to the canonical store.
    var onEnd: () -> Void = {}

    @State private var isHovered = false
    @State private var lastDragX: CGFloat? = nil

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(isHovered ? Color.accentColor.opacity(0.4) : UITokens.surfaceBorder)
                .frame(width: isHovered ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if let last = lastDragX {
                        let delta = value.location.x - last
                        if delta != 0 { onDrag(delta) }
                    }
                    lastDragX = value.location.x
                }
                .onEnded { _ in
                    lastDragX = nil
                    onEnd()
                }
        )
    }
}

// MARK: - Edge drop zone

/// Transparent overlay used at either edge of a pane to catch tab
/// drops that should spawn a new sibling pane on that side. Draws
/// nothing — the workspace owns the ghost preview that appears while
/// a drag is over it.
private struct EdgeDropZone: View {
    let width: CGFloat
    let height: CGFloat
    let side: SplitSide
    let onTargetedChange: (Bool) -> Void
    let onDrop: (TabDragPayload) -> Void

    var body: some View {
        Color.clear
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .dropDestination(for: TabDragPayload.self) { items, _ in
                guard let payload = items.first else { return false }
                onDrop(payload)
                return true
            } isTargeted: { onTargetedChange($0) }
    }
}
