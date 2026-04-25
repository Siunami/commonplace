import SwiftUI

/// Body rendered for `WorkspaceTabContent.newTab`. The user just opened a
/// fresh tab (or split a pane) and hasn't committed to what to put in it
/// yet — the chooser surfaces three options without guessing intent:
///   • Open or focus an All view tab
///   • Open or focus the Settings tab
///   • Open (or focus) any specific stack via the embedded stacks grid
///
/// Picking always calls `onPick(...)` with the chosen content. The caller
/// is responsible for routing through `WorkspaceState.openOrFocus` /
/// `replaceContent` and closing this chooser tab.
struct NewTabChooser: View {
    var onPick: (WorkspaceTabContent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionRow
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider().opacity(0.4)

            AllStacksView(onOpenStack: { stack in
                onPick(.stack(id: stack.id))
            })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UITokens.surfaceBackground)
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            HStack(spacing: 12) {
                ChooserActionButton(
                    title: "All view",
                    subtitle: "Browse every capture",
                    symbol: "square.grid.2x2",
                    action: { onPick(.allView) }
                )
                ChooserActionButton(
                    title: "Settings",
                    subtitle: "Preferences & integrations",
                    symbol: "gear",
                    action: { onPick(.settings) }
                )
                Spacer(minLength: 0)
            }
        }
    }
}

/// Tile-style button used in the chooser's action row. Plain rectangle with
/// subtle hover lift — matches the visual weight of a stack card without
/// competing with the actual stack grid below.
private struct ChooserActionButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minWidth: 200, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(isHovered ? 0.05 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
