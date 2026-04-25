import SwiftUI
import AppKit

/// Horizontal tab bar for one pane. Renders the pane's tabs as pills with
/// title + close button, plus trailing per-pane controls (+ to spawn a new
/// chooser tab, split icon to open a sibling pane, × to close this pane).
/// Mounted by `WorkspaceView.paneColumn(at:)` at the top of each pane's
/// column so the strip and the pane body share the same width allocation.
///
/// Pills are drag sources; the inner HStack is a drop target — drop a tab
/// here to reorder (same pane) or move (cross pane). Insert position is
/// computed from the drop x against per-pill frames captured via
/// `TabFramePreferenceKey` in this strip's local coordinate space.
struct TabStrip: View {
    let pane: WorkspacePane
    let isActivePane: Bool
    /// Id of the currently pinned stack (if any). Stack tab pills use this
    /// to render a filled vs hollow pin and as the source of truth for the
    /// toggle. Non-stack tabs ignore it.
    var pinnedStackId: String?
    /// Hide the close-pane (×) button when only one pane exists — closing
    /// the only pane has no defined behavior, so the button would just
    /// be inert chrome.
    var showsClosePane: Bool = true
    var onActivateTab: (UUID) -> Void
    var onCloseTab: (UUID) -> Void
    var onContextAction: (TabContextAction, UUID) -> Void
    var onAddTab: () -> Void
    var onSplit: () -> Void
    var onClosePane: () -> Void
    /// Toggle pin for the given stack id. Caller routes to setPinnedStack
    /// — no-ops if the id no longer exists. Only invoked from stack pills.
    var onTogglePinForStack: (String) -> Void
    /// Drop handler — invoked when a tab from any strip is dropped onto
    /// this one. The caller wires this to `WorkspaceState.moveTab(...)`
    /// using `pane.id` as the destination.
    var onDropTab: (TabDragPayload, _ insertIndex: Int) -> Void

    enum TabContextAction {
        case openInSplit
        case close
    }

    /// Per-pill frames captured in this strip's coordinate space. Updated
    /// via PreferenceKey on every layout pass; consulted on drop to map
    /// the cursor x to the correct insert index.
    @State private var pillFrames: [UUID: CGRect] = [:]
    @State private var isDropTargeted = false

    private var stripCoordinateSpace: String { "tabStrip-\(pane.id.uuidString)" }

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(pane.tabs) { tab in
                        pill(for: tab)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 6)
                // Span the full strip width so drops in the empty area
                // past the last pill still land inside the drop target.
                // `insertIndex` already returns `tabs.count` for x values
                // past the rightmost pill, so the append path works.
                .frame(maxWidth: .infinity, alignment: .leading)
                .coordinateSpace(name: stripCoordinateSpace)
                .onPreferenceChange(TabFramePreferenceKey.self) { frames in
                    pillFrames = frames
                }
                .dropDestination(for: TabDragPayload.self) { items, location in
                    guard let payload = items.first else { return false }
                    let insertIdx = insertIndex(for: location.x)
                    onDropTab(payload, insertIdx)
                    return true
                } isTargeted: { hovering in
                    isDropTargeted = hovering
                }
            }
            .background(dropHighlight)

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                IconButton(systemName: "plus", help: "New tab", action: onAddTab)
                IconButton(systemName: "rectangle.split.2x1", help: "Open in split pane", action: onSplit)
                if showsClosePane {
                    IconButton(systemName: "xmark", help: "Close pane", action: onClosePane)
                }
            }
            .padding(.trailing, 6)
        }
        .frame(maxHeight: .infinity)
        .background(stripBackground)
    }

    @ViewBuilder
    private func pill(for tab: WorkspaceTab) -> some View {
        TabPill(
            title: title(for: tab.content),
            symbol: symbol(for: tab.content),
            isActive: tab.id == pane.activeTabId,
            isActivePane: isActivePane,
            pinState: pinState(for: tab.content),
            onTap: { onActivateTab(tab.id) },
            onClose: { onCloseTab(tab.id) },
            onContextAction: { action in onContextAction(action, tab.id) }
        )
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: TabFramePreferenceKey.self,
                    value: [tab.id: geo.frame(in: .named(stripCoordinateSpace))]
                )
            }
        }
        .draggable(TabDragPayload(paneId: pane.id, tabId: tab.id)) {
            TabPillDragPreview(
                title: title(for: tab.content),
                symbol: symbol(for: tab.content)
            )
        }
    }

    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.10))
        } else {
            Color.clear
        }
    }

    /// Map a cursor x in this strip to the insert index. Walks captured
    /// pill frames (sorted by x) and returns the index whose midpoint the
    /// cursor has passed. Falls back to "append" when no pills exist or
    /// the cursor is past the rightmost pill.
    private func insertIndex(for x: CGFloat) -> Int {
        let ordered = pane.tabs.enumerated().compactMap { idx, tab -> (Int, CGRect)? in
            guard let frame = pillFrames[tab.id] else { return nil }
            return (idx, frame)
        }
        for (idx, frame) in ordered {
            if x < frame.midX { return idx }
        }
        return pane.tabs.count
    }

    private var stripBackground: some View {
        UITokens.surfaceCard
            .opacity(isActivePane ? 1.0 : 0.6)
    }

    private func title(for content: WorkspaceTabContent) -> String {
        switch content {
        case .allView:
            return "All"
        case .stack(let id):
            if let stack = DatabaseManager.shared.stack(byId: id) {
                return stack.isNamed ? (stack.name ?? "Stack") : "Unnamed stack"
            }
            return "Stack"
        case .settings:
            return "Settings"
        case .newTab:
            return "New tab"
        }
    }

    private func symbol(for content: WorkspaceTabContent) -> String {
        switch content {
        case .allView:
            return "square.grid.2x2"
        case .stack:
            return "rectangle.stack"
        case .settings:
            return "gear"
        case .newTab:
            return "plus"
        }
    }

    private func pinState(for content: WorkspaceTabContent) -> TabPillPinState? {
        guard case .stack(let id) = content else { return nil }
        return TabPillPinState(
            isPinned: pinnedStackId == id,
            onToggle: { onTogglePinForStack(id) }
        )
    }
}

/// Pin affordance for stack tab pills. When supplied, the pill renders a
/// 1-click pin button instead of the default leading icon. Tapping it
/// pins (or unpins, when already pinned) the underlying stack via the
/// pane's onTogglePinForStack callback.
struct TabPillPinState {
    let isPinned: Bool
    let onToggle: () -> Void
}

// MARK: - Tab pill

private struct TabPill: View {
    let title: String
    let symbol: String
    let isActive: Bool
    let isActivePane: Bool
    /// When non-nil, the pill renders a clickable pin button in place of
    /// the static `symbol` icon. Used exclusively for stack tabs.
    let pinState: TabPillPinState?
    let onTap: () -> Void
    let onClose: () -> Void
    let onContextAction: (TabStrip.TabContextAction) -> Void

    @State private var isHovered = false
    @State private var isPinHovered = false

    var body: some View {
        HStack(spacing: 5) {
            leadingGlyph
            Text(title)
                .font(.system(size: 11, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                    )
            }
            .buttonStyle(.plain)
            .help("Close tab")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: 200)
        .fixedSize(horizontal: true, vertical: false)
        .background(pillBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(activeIndicator)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("Open in split pane") { onContextAction(.openInSplit) }
            Divider()
            Button("Close tab") { onContextAction(.close) }
        }
    }

    /// Either a clickable pin button (for stack tabs) or a static symbol
    /// icon. The pin button is sized to match the symbol so the pill
    /// height stays constant across tab types.
    @ViewBuilder
    private var leadingGlyph: some View {
        if let pinState {
            Button(action: pinState.onToggle) {
                Image(systemName: pinState.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(pinTint)
                    .frame(width: 12, height: 12)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isPinHovered ? 0.08 : 0))
                    )
            }
            .buttonStyle(.plain)
            .help(pinState.isPinned ? "Unpin stack" : "Pin stack")
            .onHover { isPinHovered = $0 }
        } else {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }

    private var pinTint: Color {
        if let pinState, pinState.isPinned { return Color.accentColor }
        return isActive ? .primary : .secondary
    }

    @ViewBuilder
    private var pillBackground: some View {
        if isActive {
            UITokens.surfaceBackground
        } else if isHovered {
            Color.primary.opacity(0.04)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var activeIndicator: some View {
        if isActive && isActivePane {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
        }
    }
}

// MARK: - Drag preview

/// Lightweight ghost rendered next to the cursor during a tab drag. Mirrors
/// the pill geometry but stripped down — no close button, no pin, no
/// gestures — so the cursor isn't carrying interactive surface around.
private struct TabPillDragPreview: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.primary)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Frame preference

/// Captures each TabPill's frame in the strip's local coordinate space.
/// Drop handler reads the merged map to figure out which gap the cursor
/// is over without the strip having to re-measure on every event.
private struct TabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, n in n })
    }
}

// MARK: - Compact icon button

private struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
