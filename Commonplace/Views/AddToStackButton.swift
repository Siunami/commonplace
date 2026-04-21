import SwiftUI

/// Persistent, always-visible affordance for adding a highlight to the
/// currently pinned stack (or a fresh one if nothing is pinned). Sits in
/// every card's footer row, opposite the timestamp, so the action is one
/// cursor move away no matter where an item appears.
///
/// Acts as a toggle: tapping an already-included item removes it. The
/// visual flips from a gray "+" glyph to a filled accent-colored check
/// so membership is readable at a glance.
///
/// Membership state is read from the `\.pinnedStackMembers` environment,
/// which the owning screen (BrowseView, StackDetailView, …) keeps in
/// sync via `.stackDataDidChange`. This avoids having to thread the set
/// through every card type and footer in the hierarchy.
///
/// Style determines the button's visual treatment for its host surface.
///
/// - `compact`: small icon-only pill with a neutral background. Used in
///   the history list and detail footers where the button sits alongside
///   other row content.
/// - `expanded`: icon + label. Used in the card detail view.
/// - `overlay`: dark translucent circular glyph meant to float over a
///   card's media/content. Always visible but low-opacity at rest so it
///   doesn't fight the content; rises to full opacity on hover or when
///   the highlight is already in the pinned stack.
enum AddToStackButtonStyle {
    case compact
    case expanded
    case overlay
}

struct AddToStackButton: View {
    let highlightId: String
    var style: AddToStackButtonStyle = .compact
    var onAdded: (() -> Void)? = nil

    @Environment(\.pinnedStackMembers) private var pinnedStackMembers
    @State private var isHovered = false
    @State private var pulse = false

    private var isInStack: Bool { pinnedStackMembers.contains(highlightId) }

    var body: some View {
        Button(action: tap) {
            content
        }
        .buttonStyle(.plain)
        .help(isInStack ? "Remove from stack" : "Add to stack")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .overlay:
            overlayBody
        case .expanded, .compact:
            pillBody
        }
    }

    private var pillBody: some View {
        let expanded = (style == .expanded)
        return HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: expanded ? 11 : 10, weight: .medium))
            if expanded {
                Text(isInStack ? "In stack" : "Add to stack")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundStyle(pillForeground)
        .padding(.horizontal, expanded ? 8 : 5)
        .padding(.vertical, expanded ? 4 : 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(pillBackground)
        )
        .scaleEffect(pulse ? 1.12 : 1.0)
        // Invisible hit-area expander. Without it the compact glyph
        // is only ~16×16, easy to miss — misses fell through to the
        // parent row's onTapGesture and fired "open" on the next row.
        .padding(expanded ? 0 : 6)
        .contentShape(Rectangle())
    }

    private var overlayBody: some View {
        Image(systemName: iconName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(overlayForeground)
            .frame(width: 26, height: 26)
            .background(
                Circle().fill(overlayBackground)
            )
            .overlay(
                Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .scaleEffect(pulse ? 1.15 : 1.0)
            .opacity(overlayOpacity)
            .contentShape(Circle())
    }

    private var iconName: String {
        isInStack ? "checkmark.circle.fill" : "rectangle.stack.badge.plus"
    }

    private var pillForeground: Color {
        if isInStack { return Color.accentColor }
        return isHovered ? .primary : Color.secondary.opacity(0.7)
    }

    private var pillBackground: Color {
        if isInStack {
            return isHovered ? Color.accentColor.opacity(0.18) : Color.accentColor.opacity(0.12)
        }
        return isHovered ? Color.primary.opacity(0.08) : Color.clear
    }

    private var overlayForeground: Color {
        isInStack ? .white : .white
    }

    private var overlayBackground: Color {
        if isInStack {
            return Color.accentColor.opacity(isHovered ? 0.95 : 0.9)
        }
        return Color.black.opacity(isHovered ? 0.65 : 0.45)
    }

    private var overlayOpacity: Double {
        if isInStack || isHovered { return 1.0 }
        return 0.55
    }

    private func tap() {
        if isInStack {
            DatabaseManager.shared.removeHighlightFromPinnedStack(highlightId)
        } else {
            _ = DatabaseManager.shared.addHighlightToPinnedOrNewStack(highlightId)
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { pulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.15)) { pulse = false }
        }
        onAdded?()
    }
}

// MARK: - Environment

private struct PinnedStackMembersKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

extension EnvironmentValues {
    /// Set of highlight ids currently in the pinned stack. Owning screens
    /// inject this with `.environment(\.pinnedStackMembers, …)` and refresh
    /// on `.stackDataDidChange`.
    var pinnedStackMembers: Set<String> {
        get { self[PinnedStackMembersKey.self] }
        set { self[PinnedStackMembersKey.self] = newValue }
    }
}

private extension ShapeStyle where Self == Color {
    static var tertiary: Color { Color.secondary.opacity(0.65) }
}
