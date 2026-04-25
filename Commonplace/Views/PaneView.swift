import SwiftUI
import AppKit

/// One pane: just the active tab's body, with an active-pane accent border
/// and a tap target that promotes this pane to active. The pane's tab
/// strip is composed alongside this view by `WorkspaceView.paneColumn(at:)`,
/// not owned here — keeping the strip up there lets it share the column's
/// width allocation with the body so chrome aligns with content.
struct PaneView<Body: View>: View {
    let pane: WorkspacePane
    let isActivePane: Bool
    var onActivatePane: () -> Void
    @ViewBuilder var tabBody: (WorkspaceTabContent, UUID, UUID) -> Body

    var body: some View {
        ZStack {
            if let active = pane.activeTab {
                tabBody(active.content, pane.id, active.id)
                    .id(active.id)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UITokens.surfaceBackground)
        .overlay(activePaneAccent)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isActivePane { onActivatePane() }
        }
    }

    @ViewBuilder
    private var activePaneAccent: some View {
        if isActivePane {
            Rectangle()
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}
