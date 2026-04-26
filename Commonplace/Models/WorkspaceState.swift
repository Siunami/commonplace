import Foundation

/// What a tab actually contains. Each case carries its own identity so
/// any pane can hold any number of tabs of any case — there are NO
/// workspace-wide singletons (the user can have multiple `.allView`
/// tabs, multiple stacks of the same id across different panes, etc.).
/// The previous version of this enum had a `matches` predicate that
/// enforced singletons by case; that's gone — Obsidian-style, fully
/// unopinionated.
enum WorkspaceTabContent: Codable, Equatable {
    case allView
    case stack(id: String)
    case settings
    /// A landing chooser shown when the user hasn't picked content yet
    /// (e.g. just clicked "+" or just split a pane). Picking from the
    /// chooser replaces this tab's content with the chosen view in
    /// place — see `BrowseView.handleChooserPick`.
    case newTab
    /// V1 spatial canvas — a `Workspace` row rendered as a freeform
    /// surface holding `Placement`s. Sibling to `.stack(id:)` rather
    /// than a replacement: the tab/pane shell still owns layout and
    /// navigation; the canvas is just one possible body type.
    case workspace(id: String)
}

/// One open view inside a pane. Identity is per-tab so close/move/
/// reorder target an exact tab. Two tabs holding the same content are
/// fine — they have distinct ids.
struct WorkspaceTab: Identifiable, Codable, Equatable {
    let id: UUID
    var content: WorkspaceTabContent

    init(id: UUID = UUID(), content: WorkspaceTabContent) {
        self.id = id
        self.content = content
    }
}

/// Which side of a target pane a drag-to-edge drop should land on. The
/// receiving handler converts this to a concrete insertion index.
enum SplitSide: Codable {
    case leading
    case trailing
}

/// One pane in the workspace — owns a tab list and its currently active
/// tab. A pane always has at least one tab; dropping the last tab
/// removes the pane (handled by WorkspaceState mutations).
struct WorkspacePane: Identifiable, Codable, Equatable {
    let id: UUID
    var tabs: [WorkspaceTab]
    var activeTabId: UUID

    init(id: UUID = UUID(), tabs: [WorkspaceTab], activeTabId: UUID? = nil) {
        precondition(!tabs.isEmpty, "Pane must have at least one tab")
        self.id = id
        self.tabs = tabs
        self.activeTabId = activeTabId ?? tabs[0].id
    }

    var activeTab: WorkspaceTab? {
        tabs.first(where: { $0.id == activeTabId })
    }
}

/// Flat horizontal N-pane workspace. Each pane has a fractional width
/// in `paneWidths` (sums to ≈ 1.0). Dragging the divider between pane
/// `i` and pane `i+1` adjusts those two widths only — others stay
/// constant. Inserting / closing panes redistributes width
/// proportionally to immediate neighbours.
///
/// No vertical splits. No nesting. The model is intentionally flat to
/// keep mutations and persistence simple.
struct WorkspaceState: Codable, Equatable {
    var panes: [WorkspacePane]
    var activePaneId: UUID
    /// Per-pane width fractions, length matches `panes.count`. Sums to
    /// approximately 1.0 (rounding tolerated). Replaces the old single
    /// `dividerRatio: Double`.
    var paneWidths: [Double]

    /// Minimum fractional width per pane. Below this, divider drag
    /// refuses to shrink. Multiplied by total available pixel width
    /// at the layout layer to enforce a 150pt minimum.
    static let minPaneFraction: Double = 0.05

    init(panes: [WorkspacePane], activePaneId: UUID? = nil, paneWidths: [Double]? = nil) {
        precondition(!panes.isEmpty, "Workspace must have at least one pane")
        self.panes = panes
        self.activePaneId = activePaneId ?? panes[0].id
        if let paneWidths, paneWidths.count == panes.count {
            self.paneWidths = Self.normalize(paneWidths)
        } else {
            self.paneWidths = Self.evenWidths(count: panes.count)
        }
    }

    /// Default app-launch state — single pane with a single All-view tab.
    static var initial: WorkspaceState {
        let tab = WorkspaceTab(content: .allView)
        let pane = WorkspacePane(tabs: [tab])
        return WorkspaceState(panes: [pane])
    }

    var activePane: WorkspacePane? {
        panes.first(where: { $0.id == activePaneId })
    }

    var activePaneIndex: Int {
        panes.firstIndex(where: { $0.id == activePaneId }) ?? 0
    }

    // MARK: - Lookups

    /// First (paneId, tabId) holding a tab whose content matches by
    /// value-equality. Used by *explicit* "focus existing" actions
    /// (rare). Default open path no longer goes through this.
    func locate(_ content: WorkspaceTabContent) -> (paneId: UUID, tabId: UUID)? {
        for pane in panes {
            if let tab = pane.tabs.first(where: { $0.content == content }) {
                return (pane.id, tab.id)
            }
        }
        return nil
    }

    // MARK: - Tab mutations

    /// Open a new tab with the given content in `paneId` (or the active
    /// pane if nil). **Always opens fresh** — no auto-focus on existing
    /// tabs. The user's pane intent is respected.
    mutating func openTab(_ content: WorkspaceTabContent, inPane paneId: UUID? = nil) {
        let target = paneId ?? activePaneId
        let newTab = WorkspaceTab(content: content)
        updatePane(target) { pane in
            pane.tabs.append(newTab)
            pane.activeTabId = newTab.id
        }
        activePaneId = target
    }

    /// Explicitly focus an existing tab matching `content`, anywhere in
    /// the workspace. Returns true if found. Use this only when the
    /// caller specifically wants the "jump to wherever it already is"
    /// semantics — the default open path is `openTab`.
    @discardableResult
    mutating func focusExisting(_ content: WorkspaceTabContent) -> Bool {
        guard let location = locate(content) else { return false }
        activePaneId = location.paneId
        updatePane(location.paneId) { $0.activeTabId = location.tabId }
        return true
    }

    /// Close a specific tab. If it was the last tab in its pane, the
    /// pane itself collapses and its width redistributes proportionally
    /// to surviving neighbours. If the closed pane was the only pane,
    /// the workspace resets to `.initial` so it never reaches an empty
    /// state. Returns the closed tab's content so callers can fire
    /// content-specific cleanup (e.g. pruning empty unnamed workspaces).
    @discardableResult
    mutating func closeTab(paneId: UUID, tabId: UUID) -> WorkspaceTabContent? {
        guard let paneIdx = panes.firstIndex(where: { $0.id == paneId }) else { return nil }
        guard let tabIdx = panes[paneIdx].tabs.firstIndex(where: { $0.id == tabId }) else { return nil }
        let closedContent = panes[paneIdx].tabs[tabIdx].content
        panes[paneIdx].tabs.remove(at: tabIdx)
        if panes[paneIdx].tabs.isEmpty {
            removePane(at: paneIdx)
            return closedContent
        }
        if panes[paneIdx].activeTabId == tabId {
            let fallbackIdx = max(0, tabIdx - 1)
            panes[paneIdx].activeTabId = panes[paneIdx].tabs[min(fallbackIdx, panes[paneIdx].tabs.count - 1)].id
        }
        return closedContent
    }

    /// Replace a tab's content in place. Used by the new-tab chooser
    /// when the user picks a content type — the chooser tab mutates
    /// into the picked content rather than spawning a sibling.
    mutating func replaceContent(paneId: UUID, tabId: UUID, newContent: WorkspaceTabContent) {
        guard let paneIdx = panes.firstIndex(where: { $0.id == paneId }) else { return }
        guard let tabIdx = panes[paneIdx].tabs.firstIndex(where: { $0.id == tabId }) else { return }
        panes[paneIdx].tabs[tabIdx].content = newContent
    }

    /// Move a tab to a new position. `src == dst` is an in-pane reorder.
    /// Cross-pane moves leave a trailing empty source pane collapsed.
    mutating func moveTab(fromPane src: UUID, tabId: UUID, toPane dst: UUID, atIndex: Int) {
        guard let srcIdx = panes.firstIndex(where: { $0.id == src }) else { return }
        guard let tabIdx = panes[srcIdx].tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let movedTab = panes[srcIdx].tabs[tabIdx]

        if src == dst {
            // In-pane reorder: removing shifts indices ahead of the
            // target down by one when moving rightwards.
            panes[srcIdx].tabs.remove(at: tabIdx)
            let adjusted = atIndex > tabIdx ? atIndex - 1 : atIndex
            let clamped = max(0, min(panes[srcIdx].tabs.count, adjusted))
            panes[srcIdx].tabs.insert(movedTab, at: clamped)
            panes[srcIdx].activeTabId = movedTab.id
            return
        }

        // Cross-pane move. Remove from source first, collapse source
        // if it's now empty.
        panes[srcIdx].tabs.remove(at: tabIdx)
        if panes[srcIdx].tabs.isEmpty {
            removePane(at: srcIdx)
        } else if panes[srcIdx].activeTabId == tabId {
            let fallback = max(0, tabIdx - 1)
            panes[srcIdx].activeTabId = panes[srcIdx].tabs[min(fallback, panes[srcIdx].tabs.count - 1)].id
        }

        // Re-locate destination — pane indices may have shifted if
        // source collapsed and was removed before the destination.
        guard let dstIdx = panes.firstIndex(where: { $0.id == dst }) else { return }
        let clamped = max(0, min(panes[dstIdx].tabs.count, atIndex))
        panes[dstIdx].tabs.insert(movedTab, at: clamped)
        panes[dstIdx].activeTabId = movedTab.id
        activePaneId = dst
    }

    // MARK: - Pane mutations

    /// Insert a new pane at the given index, seeded with one tab
    /// holding `content`. Width is taken from the affected neighbour
    /// (split in half — neighbour shrinks, new pane gets the other
    /// half). The new pane becomes active.
    @discardableResult
    mutating func insertPane(at index: Int, withTab content: WorkspaceTabContent) -> UUID {
        let clampedIndex = max(0, min(panes.count, index))
        let newPane = WorkspacePane(tabs: [WorkspaceTab(content: content)])
        insertPaneInternal(newPane, at: clampedIndex)
        activePaneId = newPane.id
        return newPane.id
    }

    /// Move `tabId` from `sourcePaneId` into a freshly created pane
    /// inserted at `insertingAt` index. The new pane absorbs half of
    /// the neighbour's width. If the source pane becomes empty as a
    /// result, it collapses.
    mutating func splitWithMovedTab(
        fromPane sourcePaneId: UUID,
        tabId: UUID,
        insertingAt index: Int
    ) {
        guard let srcIdx = panes.firstIndex(where: { $0.id == sourcePaneId }) else { return }
        guard let tabIdx = panes[srcIdx].tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let movedTab = panes[srcIdx].tabs.remove(at: tabIdx)

        // Source-pane bookkeeping FIRST so insertion can compute a
        // stable post-removal index.
        var sourceCollapsed = false
        if panes[srcIdx].tabs.isEmpty {
            removePane(at: srcIdx)
            sourceCollapsed = true
        } else if panes[srcIdx].activeTabId == tabId {
            let fallback = max(0, tabIdx - 1)
            panes[srcIdx].activeTabId = panes[srcIdx].tabs[min(fallback, panes[srcIdx].tabs.count - 1)].id
        }

        // Adjust insertion index if the source collapsed before it.
        var targetIndex = index
        if sourceCollapsed && srcIdx < targetIndex {
            targetIndex -= 1
        }

        let newPane = WorkspacePane(tabs: [movedTab])
        insertPaneInternal(newPane, at: max(0, min(panes.count, targetIndex)))
        activePaneId = newPane.id
    }

    /// Close a whole pane (and all its tabs). Returns the contents of
    /// every tab that was in the pane so callers can fire per-content
    /// cleanup (e.g. pruning empty unnamed workspaces).
    @discardableResult
    mutating func closePane(paneId: UUID) -> [WorkspaceTabContent] {
        guard let idx = panes.firstIndex(where: { $0.id == paneId }) else { return [] }
        let closedContents = panes[idx].tabs.map(\.content)
        removePane(at: idx)
        return closedContents
    }

    // MARK: - Width mutations

    /// Set all pane widths in one shot. Useful for committing live
    /// drag state. Normalised to sum to 1.0.
    mutating func setPaneWidths(_ widths: [Double]) {
        guard widths.count == panes.count else { return }
        paneWidths = Self.normalize(widths)
    }

    // MARK: - Internal helpers

    private mutating func updatePane(_ paneId: UUID, _ mutate: (inout WorkspacePane) -> Void) {
        guard let idx = panes.firstIndex(where: { $0.id == paneId }) else { return }
        mutate(&panes[idx])
    }

    private mutating func insertPaneInternal(_ newPane: WorkspacePane, at index: Int) {
        // Equal-width heuristic: if the existing panes are all roughly
        // equal-width, the user hasn't expressed any sizing preference
        // (or has dragged back to balance) — redistribute evenly across
        // (n+1) panes so the new pane joins on equal footing.
        //
        // Otherwise the user has shifted dividers to a particular
        // layout — preserve their intent by halving only the donor pane
        // (the one whose space the new pane displaces). All other panes
        // keep their widths.
        if Self.nearlyEqual(paneWidths) {
            panes.insert(newPane, at: index)
            paneWidths = Self.evenWidths(count: panes.count)
            return
        }

        let donorIdx = (index < panes.count) ? index : max(0, panes.count - 1)
        if !paneWidths.indices.contains(donorIdx) {
            // Empty / inconsistent state — fall back to even widths
            // after insert.
            panes.insert(newPane, at: index)
            paneWidths = Self.evenWidths(count: panes.count)
            return
        }
        let donorOriginal = paneWidths[donorIdx]
        let half = donorOriginal / 2.0
        paneWidths[donorIdx] = half
        paneWidths.insert(half, at: index)
        panes.insert(newPane, at: index)
        paneWidths = Self.normalize(paneWidths)
    }

    private mutating func removePane(at index: Int) {
        guard panes.indices.contains(index) else { return }
        let removedId = panes[index].id
        let removedWidth = paneWidths.indices.contains(index) ? paneWidths[index] : 0

        panes.remove(at: index)
        if paneWidths.indices.contains(index) {
            paneWidths.remove(at: index)
        }

        if panes.isEmpty {
            // Workspace must always have at least one pane.
            self = .initial
            return
        }

        // Redistribute the removed pane's width proportionally to
        // surviving neighbours.
        if removedWidth > 0 && !paneWidths.isEmpty {
            let total = paneWidths.reduce(0, +)
            if total > 0 {
                paneWidths = paneWidths.map { $0 + removedWidth * ($0 / total) }
            } else {
                paneWidths = Self.evenWidths(count: panes.count)
            }
        }
        paneWidths = Self.normalize(paneWidths)

        // Active pane fallback if we just removed it.
        if activePaneId == removedId {
            // Prefer the pane now at the same index (the one to the
            // right shifted left); fall back to the previous pane.
            let fallbackIdx = min(index, panes.count - 1)
            activePaneId = panes[fallbackIdx].id
        }
    }

    /// True iff every width is within `tolerance` of the first.
    /// Used by `insertPaneInternal` to switch between even-redistribute
    /// (panes were balanced — no expressed user intent) and donor-halve
    /// (panes were imbalanced — preserve the user's chosen layout).
    /// Tolerance of 0.01 covers small float drift from drag-back-to-
    /// balance while still tripping on any meaningful imbalance (≥1%).
    private static func nearlyEqual(_ widths: [Double], tolerance: Double = 0.01) -> Bool {
        guard let first = widths.first else { return true }
        return widths.allSatisfy { abs($0 - first) <= tolerance }
    }

    private static func evenWidths(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let each = 1.0 / Double(count)
        return Array(repeating: each, count: count)
    }

    private static func normalize(_ widths: [Double]) -> [Double] {
        let positive = widths.map { max(0.0001, $0) }
        let total = positive.reduce(0, +)
        guard total > 0 else { return evenWidths(count: widths.count) }
        return positive.map { $0 / total }
    }
}
