import SwiftUI

/// Body rendered for `WorkspaceTabContent.newTab`. The user just opened a
/// fresh tab (or split a pane) and hasn't committed to what to put in it
/// yet. The chooser is structured as three thin slabs:
///   1. A compact top bar with primary actions (All view, New workspace)
///      and a Stacks/Workspaces view-mode segment on the right. Default
///      mode is Stacks — the most common landing target.
///   2. A scrolling body that holds the picked collection (stacks grid or
///      workspaces grid).
///   3. A bottom footer for utility buttons (Settings, future tools).
///
/// Picking always calls `onPick(...)`. The caller routes through
/// WorkspaceState and replaces the chooser tab in place.
struct NewTabChooser: View {
    var onPick: (WorkspaceTabContent) -> Void

    @State private var workspaces: [Workspace] = []
    @State private var viewMode: ChooserMode = .stacks

    enum ChooserMode: String, CaseIterable, Identifiable {
        case stacks
        case workspaces
        var id: String { rawValue }
        var label: String {
            switch self {
            case .stacks: return "Stacks"
            case .workspaces: return "Workspaces"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.3)
            body(for: viewMode)
            Divider().opacity(0.3)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UITokens.surfaceBackground)
        .onAppear { reloadWorkspaces() }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceDataDidChange)) { _ in
            reloadWorkspaces()
        }
        .onReceive(NotificationCenter.default.publisher(for: .placementDataDidChange)) { _ in
            // updatedAt bumps on placement create — re-sort for ordering.
            reloadWorkspaces()
        }
    }

    private func reloadWorkspaces() {
        workspaces = DatabaseManager.shared.allWorkspaces()
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 6) {
            ChooserChipButton(symbol: "square.grid.2x2", label: "All view") {
                onPick(.allView)
            }
            ChooserChipButton(symbol: "rectangle.split.3x3", label: "New workspace") {
                if let ws = DatabaseManager.shared.createWorkspace() {
                    onPick(.workspace(id: ws.id))
                }
            }

            Spacer(minLength: 12)

            ChooserModeSegment(mode: $viewMode)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Body

    @ViewBuilder
    private func body(for mode: ChooserMode) -> some View {
        switch mode {
        case .stacks:
            AllStacksView(onOpenStack: { onPick(.stack(id: $0.id)) })
        case .workspaces:
            AllWorkspacesView(
                workspaces: workspaces,
                onOpenWorkspace: { onPick(.workspace(id: $0.id)) }
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            ChooserFooterIconButton(symbol: "gear", help: "Settings") {
                onPick(.settings)
            }
            Spacer()
            // Room for future utility buttons (search, recents, etc.) —
            // intentionally left empty for now so the footer reads as
            // calm chrome rather than a feature dump.
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(UITokens.surfaceCard.opacity(0.5))
    }
}

// MARK: - Top-bar chip

/// Compact action chip for the chooser top bar. Replaces the prior
/// 96pt-tall hero tiles — same primary actions (All view, New workspace),
/// far less visual weight, so the body's collection is the page's
/// primary subject.
private struct ChooserChipButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isHovered ? Color.accentColor : Color.primary.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.10) : UITokens.surfaceCard.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

// MARK: - Mode segment

/// Two-pill segmented control that flips the chooser body between Stacks
/// and Workspaces. Separate from a system Picker so the visual weight
/// matches the rest of the chooser chrome.
private struct ChooserModeSegment: View {
    @Binding var mode: NewTabChooser.ChooserMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NewTabChooser.ChooserMode.allCases) { value in
                segmentButton(for: value)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(UITokens.surfaceCard.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
        )
    }

    private func segmentButton(for value: NewTabChooser.ChooserMode) -> some View {
        let selected = (value == mode)
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) { mode = value }
        } label: {
            Text(value.label)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selected ? UITokens.surfaceBackground : Color.clear)
                        .shadow(color: selected ? UITokens.shadowCard : .clear, radius: 2, y: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Footer icon button

/// Compact icon button for the chooser footer. Same vocabulary as the
/// per-tab IconButton in the tab strip — square frame, hover background,
/// secondary tint at rest.
private struct ChooserFooterIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.10)) { isHovered = hovering }
        }
    }
}

// MARK: - Workspaces collection

/// Vertical-grid sibling to `AllStacksView` — same gridded card vocabulary
/// (220pt-wide tiles, adaptive columns) so workspaces and stacks read as
/// parallel collections in the chooser. Empty state mirrors the stacks
/// empty state in tone.
private struct AllWorkspacesView: View {
    let workspaces: [Workspace]
    let onOpenWorkspace: (Workspace) -> Void

    var body: some View {
        Group {
            if workspaces.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        grid
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 220)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UITokens.surfaceBackground)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Workspaces")
                .font(.system(size: 20, weight: .semibold))
            Text("\(workspaces.count)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var grid: some View {
        LazyVGrid(columns: gridColumns, alignment: .center, spacing: 20) {
            ForEach(workspaces) { workspace in
                WorkspaceCard(workspace: workspace) {
                    onOpenWorkspace(workspace)
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 236), spacing: 20, alignment: .center)]
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "rectangle.split.3x3")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.quaternary)

            VStack(spacing: 6) {
                Text("No workspaces yet")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Spatial canvases for arranging captures.")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }

            Text("Tap “New workspace” above to create one.")
                .font(.system(size: 12))
                .foregroundStyle(.quaternary)
                .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
