import SwiftUI
import AppKit

/// Top-level workspace surface. Hosts the search sidebar (still SwiftUI,
/// single-pane drag is fine there) plus an N-pane area backed by AppKit's
/// `NSSplitView` (`PanesSplitView`). Routing the inter-pane divider drag
/// through AppKit means SwiftUI's body never re-evaluates during a drag;
/// each pane's tree only sees a `Layout` size change, with cached masonry
/// heights short-circuiting the heavy work.
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

    /// Identifies the pane (by id) and edge currently targeted by an
    /// in-flight tab drag. The owning pane draws its own translucent
    /// half-pane ghost when its id matches. nil = no drag in progress
    /// or no edge currently targeted.
    @State private var targetedSplit: PanesSplitView<Body>.TargetedSplit? = nil

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
        PanesSplitView(
            state: $state,
            targetedSplit: $targetedSplit,
            pinnedStackId: pinnedStackId,
            onTogglePinForStack: onTogglePinForStack,
            tabBody: tabBody
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

