import SwiftUI

/// Persistent, always-visible affordance for adding a highlight to the
/// currently pinned stack (or a fresh one if nothing is pinned). Sits in
/// every card's footer row, opposite the timestamp, so the action is one
/// cursor move away no matter where an item appears.
///
/// Compact mode: icon only — used in masonry cards and stack-detail grid
/// cells where space is tight.
///
/// Expanded mode: icon + "Add to stack" label — used in the card detail
/// view where there's more horizontal room and the extra affordance is
/// worth the real estate.
struct AddToStackButton: View {
    let highlightId: String
    var expanded: Bool = false
    var onAdded: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var justAdded = false
    @State private var pulse = false

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 4) {
                Image(systemName: justAdded ? "checkmark" : "rectangle.stack.badge.plus")
                    .font(.system(size: expanded ? 11 : 10, weight: .medium))
                if expanded {
                    Text(justAdded ? "Added" : "Add to stack")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, expanded ? 8 : 5)
            .padding(.vertical, expanded ? 4 : 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(background)
            )
            .scaleEffect(pulse ? 1.12 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(justAdded ? "Added to stack" : "Add to stack")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    private var foreground: Color {
        if justAdded { return Color.accentColor }
        return isHovered ? .primary : Color.secondary.opacity(0.7)
    }

    private var background: Color {
        if justAdded { return Color.accentColor.opacity(0.1) }
        return isHovered ? Color.primary.opacity(0.08) : Color.clear
    }

    private func tap() {
        _ = DatabaseManager.shared.addHighlightToPinnedOrNewStack(highlightId)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { pulse = true }
        withAnimation(.easeInOut(duration: 0.2)) { justAdded = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.15)) { pulse = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeOut(duration: 0.25)) { justAdded = false }
        }
        onAdded?()
    }
}

private extension ShapeStyle where Self == Color {
    static var tertiary: Color { Color.secondary.opacity(0.65) }
}
