import SwiftUI
import AppKit

/// Fires content-specific cleanup for a tab that just closed. Currently
/// only `.workspace(id:)` has cleanup — empty unnamed workspaces get
/// pruned so unfilled drafts don't accumulate. Called from every
/// user-initiated close path (close button, context menu, ⌘W, close
/// pane). Move/split paths preserve the tab so they don't go through
/// here.
@MainActor
func pruneIfClosedWorkspace(_ content: WorkspaceTabContent?) {
    if case .workspace(let id) = content {
        DatabaseManager.shared.pruneWorkspaceIfEmptyUnnamed(id: id)
    }
}

@MainActor
func pruneClosedWorkspaceTabs(_ closed: [WorkspaceTabContent]) {
    for content in closed { pruneIfClosedWorkspace(content) }
}

/// Hosts the workspace's N panes in a native `NSSplitView` so divider drag
/// runs entirely in the AppKit event loop. SwiftUI's body never re-evaluates
/// during a drag — the split view mutates arranged-subview frames directly,
/// each `NSHostingView` reflows via the `Layout` protocol with cached
/// per-card heights, and `state.paneWidths` only commits on mouse-up.
///
/// This replaces the prior `tabRow + bodyRow` HStack pair, which paid a
/// full SwiftUI body re-evaluation across both adjacent panes per drag
/// tick — workable at one pane (sidebar), too expensive at two.
struct PanesSplitView<TabBody: View>: NSViewRepresentable {
    typealias TargetedSplit = (paneId: UUID, side: SplitSide)

    @Binding var state: WorkspaceState
    @Binding var targetedSplit: TargetedSplit?
    var pinnedStackId: String?
    var onTogglePinForStack: (String) -> Void
    @ViewBuilder var tabBody: (WorkspaceTabContent, UUID, UUID) -> TabBody

    /// Custom env values do not auto-bridge into `NSHostingView`'s rootView,
    /// so we read them here and re-inject when constructing each hosting
    /// view's rootView. Currently only `pinnedStackMembers` flows in from
    /// `BrowseView`'s `.environment(\.pinnedStackMembers, ...)` modifier.
    @Environment(\.pinnedStackMembers) private var pinnedStackMembers

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSplitView {
        let split = PanesNSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = context.coordinator
        split.translatesAutoresizingMaskIntoConstraints = false

        // Seed the coordinator's authoritative widths BEFORE inserting
        // subviews so the resize delegate (called during the very first
        // layout pass) has the right fractions to apply.
        context.coordinator.currentWidths = state.paneWidths

        for pane in state.panes {
            let hosting = makeHostingView(for: pane)
            context.coordinator.hostingViews[pane.id] = hosting
            split.addArrangedSubview(hosting)
        }
        context.coordinator.arrangedPaneIds = state.panes.map { $0.id }

        // Wait one runloop for autolayout to give the split view real
        // bounds, then drive a delegate-backed layout pass so initial
        // divider positions match `state.paneWidths` exactly (rather
        // than NSSplitView's default even-split heuristic).
        DispatchQueue.main.async { [weak split] in
            guard let split = split else { return }
            split.adjustSubviews()
        }
        return split
    }

    func updateNSView(_ split: NSSplitView, context: Context) {
        let coordinator = context.coordinator

        // Refresh the commit closure each pass so it captures the latest
        // `state` binding writer. Coordinator calls this on drag end.
        coordinator.commitWidths = { fractions in
            state.setPaneWidths(fractions)
        }
        // Authoritative source of truth for the resize delegate. State
        // is the only writer outside of an active drag; during drag we
        // skip touching layout (`isDragging` short-circuits below).
        coordinator.currentWidths = state.paneWidths

        let desiredIds = state.panes.map { $0.id }
        let isSameOrder = coordinator.arrangedPaneIds == desiredIds

        if isSameOrder {
            for pane in state.panes {
                if let hosting = coordinator.hostingViews[pane.id] {
                    hosting.rootView = makeRootView(for: pane)
                }
            }
        } else {
            // Surgical reshape: only the subviews that actually came or
            // went are touched. Removing-and-re-adding everything (the
            // prior approach) tossed NSSplitView's layout intent on the
            // floor and let it fall back to default proportional sizing,
            // which made the right-most pane render way smaller than the
            // model said it should be.
            let desiredSet = Set(desiredIds)

            // 1. Remove vanished panes' hosting views.
            for id in coordinator.arrangedPaneIds where !desiredSet.contains(id) {
                if let hosting = coordinator.hostingViews[id] {
                    split.removeArrangedSubview(hosting)
                    hosting.removeFromSuperview()
                    coordinator.hostingViews.removeValue(forKey: id)
                }
            }

            // 2. Insert new panes' hosting views at the correct index.
            for (idx, paneId) in desiredIds.enumerated() {
                if coordinator.hostingViews[paneId] == nil,
                   let pane = state.panes.first(where: { $0.id == paneId }) {
                    let hosting = makeHostingView(for: pane)
                    coordinator.hostingViews[paneId] = hosting
                    split.insertArrangedSubview(hosting, at: idx)
                }
            }

            // 3. Refresh root views (active-pane accent, tab counts, etc.).
            for pane in state.panes {
                if let hosting = coordinator.hostingViews[pane.id] {
                    hosting.rootView = makeRootView(for: pane)
                }
            }

            coordinator.arrangedPaneIds = desiredIds

            // 4. Drive layout from `currentWidths` so the new pane lands
            //    at exactly the fraction the model assigned to it. Skip
            //    during drag so we don't fight with NSSplitView's own
            //    per-tick frame mutations.
            if !coordinator.isDragging {
                split.adjustSubviews()
            }
        }
    }

    private func makeHostingView(for pane: WorkspacePane) -> NSHostingView<AnyView> {
        let hosting = NSHostingView(rootView: makeRootView(for: pane))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        return hosting
    }

    private func makeRootView(for pane: WorkspacePane) -> AnyView {
        AnyView(paneColumn(pane: pane).environment(\.pinnedStackMembers, pinnedStackMembers))
    }

    // MARK: - Pane column

    @ViewBuilder
    private func paneColumn(pane: WorkspacePane) -> some View {
        VStack(spacing: 0) {
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
                    pruneIfClosedWorkspace(state.closeTab(paneId: pane.id, tabId: tabId))
                },
                onContextAction: { action, tabId in
                    switch action {
                    case .openInSplit:
                        if let idx = state.panes.firstIndex(where: { $0.id == pane.id }) {
                            state.splitWithMovedTab(fromPane: pane.id, tabId: tabId, insertingAt: idx + 1)
                        }
                    case .close:
                        pruneIfClosedWorkspace(state.closeTab(paneId: pane.id, tabId: tabId))
                    }
                },
                onAddTab: {
                    state.activePaneId = pane.id
                    state.openTab(.newTab, inPane: pane.id)
                },
                onSplit: {
                    if let idx = state.panes.firstIndex(where: { $0.id == pane.id }) {
                        state.insertPane(at: idx + 1, withTab: .newTab)
                    }
                },
                onClosePane: {
                    pruneClosedWorkspaceTabs(state.closePane(paneId: pane.id))
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
            .frame(height: 28)
            .background(UITokens.surfaceCard)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(UITokens.surfaceBorder)
                    .frame(height: 0.5)
            }

            PaneView(
                pane: pane,
                isActivePane: pane.id == state.activePaneId,
                onActivatePane: { state.activePaneId = pane.id },
                tabBody: tabBody
            )
            .overlay(alignment: .leading) {
                edgeDropZone(for: pane, side: .leading)
            }
            .overlay(alignment: .trailing) {
                edgeDropZone(for: pane, side: .trailing)
            }
            .overlay {
                if let target = targetedSplit, target.paneId == pane.id {
                    splitGhost(side: target.side)
                }
            }
        }
    }

    @ViewBuilder
    private func edgeDropZone(for pane: WorkspacePane, side: SplitSide) -> some View {
        Color.clear
            .frame(width: 90)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .dropDestination(for: TabDragPayload.self) { items, _ in
                guard let payload = items.first,
                      let idx = state.panes.firstIndex(where: { $0.id == pane.id }) else {
                    return false
                }
                let insertAt = side == .leading ? idx : idx + 1
                state.splitWithMovedTab(
                    fromPane: payload.paneId,
                    tabId: payload.tabId,
                    insertingAt: insertAt
                )
                targetedSplit = nil
                return true
            } isTargeted: { hovering in
                if hovering {
                    targetedSplit = (paneId: pane.id, side: side)
                } else if let current = targetedSplit, current.paneId == pane.id, current.side == side {
                    targetedSplit = nil
                }
            }
    }

    @ViewBuilder
    private func splitGhost(side: SplitSide) -> some View {
        GeometryReader { geo in
            let halfWidth = geo.size.width * 0.5
            let xOffset: CGFloat = side == .trailing ? halfWidth : 0
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
            .frame(width: halfWidth, height: geo.size.height)
            .offset(x: xOffset, y: 0)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSSplitViewDelegate {
        /// Order matches `state.panes` after each successful arrangement
        /// pass; used by `updateNSView` to detect shape vs. content-only
        /// changes cheaply.
        var arrangedPaneIds: [UUID] = []
        var hostingViews: [UUID: NSHostingView<AnyView>] = [:]

        /// Authoritative pane width fractions — mirrored from
        /// `state.paneWidths` on every `updateNSView` (and seeded by
        /// `makeNSView`). The resize delegate consults this to lay out
        /// arranged subviews so split / close / window-resize all land
        /// at the model's intended fractions, regardless of whatever
        /// frames NSSplitView happens to have computed on its own.
        var currentWidths: [Double] = []

        var isDragging = false
        private var mouseUpMonitor: Any?

        /// Called once on drag-end with normalized fractional widths.
        /// Set fresh on every `updateNSView` so it captures the latest
        /// `state` binding writer.
        var commitWidths: ([Double]) -> Void = { _ in }

        // MARK: NSSplitViewDelegate

        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            // Each pane to the LEFT of this divider (inclusive on the left
            // side of the divider) must fit at least `panesMinPixelWidth`.
            let dividerThickness = splitView.dividerThickness
            var minSum: CGFloat = 0
            for i in 0...dividerIndex {
                minSum += panesMinPixelWidth
                if i < dividerIndex {
                    minSum += dividerThickness
                }
            }
            return max(proposedMinimumPosition, minSum)
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            let dividerThickness = splitView.dividerThickness
            let count = splitView.arrangedSubviews.count
            var trailingSum: CGFloat = 0
            // Panes strictly to the right of this divider must fit minimums.
            for i in (dividerIndex + 1)..<count {
                trailingSum += panesMinPixelWidth
                if i < count - 1 {
                    trailingSum += dividerThickness
                }
            }
            let maxAllowed = splitView.bounds.width - trailingSum
            return min(proposedMaximumPosition, maxAllowed)
        }

        /// Lay out arranged subviews from `currentWidths` (the model's
        /// pane fractions). Called on:
        ///   - first layout pass (via `adjustSubviews()` in `makeNSView`)
        ///   - pane add / remove (via `adjustSubviews()` in `updateNSView`)
        ///   - window resize (NSSplitView calls this directly)
        ///
        /// Reading from `currentWidths` rather than the existing frames
        /// means a freshly-inserted pane lands at the fraction the model
        /// allocated to it, instead of inheriting whatever default width
        /// NSSplitView would have given it.
        ///
        /// Falls back to proportional resize from existing frames if
        /// `currentWidths` and the arranged subview count don't match
        /// (transient state during reshape).
        func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
            let count = splitView.arrangedSubviews.count
            guard count > 0 else { return }
            let dividerThickness = splitView.dividerThickness
            let dividerCount = max(0, count - 1)
            let newPaneSpace = max(1, splitView.bounds.width - CGFloat(dividerCount) * dividerThickness)

            let widths: [Double]
            if currentWidths.count == count, currentWidths.reduce(0, +) > 0 {
                widths = currentWidths
            } else {
                let oldWidths = splitView.arrangedSubviews.map { Double($0.frame.width) }
                let oldTotal = oldWidths.reduce(0, +)
                guard oldTotal > 0 else { return }
                widths = oldWidths.map { $0 / oldTotal }
            }

            var x: CGFloat = 0
            for i in 0..<count {
                let w = newPaneSpace * CGFloat(widths[i])
                splitView.arrangedSubviews[i].frame = NSRect(
                    x: x,
                    y: 0,
                    width: w,
                    height: splitView.bounds.height
                )
                x += w
                if i < count - 1 {
                    x += dividerThickness
                }
            }
        }

        /// NSSplitView posts this for every drag tick AND every window
        /// resize. The `NSSplitViewDividerIndex` user-info key is set
        /// only when the user is actively dragging a divider, so use
        /// it to gate dragging-state tracking.
        func splitViewWillResizeSubviews(_ notification: Notification) {
            guard let dividerIndex = notification.userInfo?["NSSplitViewDividerIndex"] as? Int,
                  dividerIndex >= 0 else {
                return
            }
            guard !isDragging else { return }
            isDragging = true
            installMouseUpMonitor()
        }

        private func installMouseUpMonitor() {
            mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                self?.handleDragEnd()
                return event
            }
        }

        private func handleDragEnd() {
            guard isDragging else { return }
            isDragging = false
            if let monitor = mouseUpMonitor {
                NSEvent.removeMonitor(monitor)
                mouseUpMonitor = nil
            }
            // Read final widths from any one of our hosting views' superview.
            guard let anyHosting = hostingViews.values.first,
                  let splitView = anyHosting.superview as? NSSplitView else { return }
            let widths = splitView.arrangedSubviews.map { Double($0.frame.width) }
            let total = widths.reduce(0, +)
            guard total > 0 else { return }
            let fractions = widths.map { $0 / total }
            // Defer the SwiftUI write to the next runloop tick so we don't
            // mutate a binding from inside a layout pass.
            DispatchQueue.main.async { [weak self] in
                self?.commitWidths(fractions)
            }
        }

        deinit {
            if let monitor = mouseUpMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

/// 6pt total thickness keeps the cursor-resize hit area at parity with the
/// previous SwiftUI 6pt divider; AppKit draws a 1pt rule centered in it.
final class PanesNSSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 6 }
    override var dividerColor: NSColor {
        NSColor(named: "SurfaceBorder") ?? .separatorColor
    }
}

/// Floor on a pane's pixel width during divider drag. Mirrors Obsidian's
/// hard min so users can't drag panes into invisibility. Was previously
/// `WorkspaceView.minPanePixelWidth`.
private let panesMinPixelWidth: CGFloat = 150
