import SwiftUI
import AppKit
import Combine

/// A free-floating column of StackCards anchored above the pinned floater.
/// Each card keeps its own shadow/surface — there is no wrapping panel,
/// border, or background. The column reads as "more pinned-style tiles
/// stacked above the pinned one," like messages rising from a chat input.
///
/// Cards are ordered oldest → newest so the newest sits nearest the
/// pinned floater at the bottom of the column. A compact search pill at
/// the top filters live. Selection scrolls into view. Picking a card calls
/// `onPick` and the drawer dismisses itself.
struct StackDrawer: View {
    var currentPinnedId: String?
    /// Maximum height the column may occupy. The caller derives this from
    /// available window space so the column never extends past the top of
    /// the archive; overflow scrolls internally.
    var maxColumnHeight: CGFloat
    var onPick: (Stack) -> Void
    var onDismiss: () -> Void
    /// Called whenever the cursor enters or leaves the column body. The
    /// caller combines this with the floater's own hover state to decide
    /// when to close the column — so moving the mouse from the floater
    /// into the column doesn't accidentally dismiss.
    var onHoverChange: (Bool) -> Void = { _ in }

    @State private var searchText = ""
    @State private var allStacks: [Stack] = []
    @State private var selectionIndex: Int = 0
    @FocusState private var searchFocused: Bool

    private let db = DatabaseManager.shared
    private let columnWidth: CGFloat = 220

    /// Visible stacks ordered oldest → newest. The newest sits at the
    /// bottom, nearest the pinned floater (the anchor).
    private var filteredStacks: [Stack] {
        let others = allStacks.filter { $0.id != currentPinnedId }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched: [Stack]
        if trimmed.isEmpty {
            matched = others
        } else {
            matched = others.filter { stack in
                guard let name = stack.name else { return false }
                return name.localizedCaseInsensitiveContains(trimmed)
            }
        }
        return matched.reversed()
    }

    var body: some View {
        VStack(spacing: 8) {
            if filteredStacks.isEmpty {
                emptyState
            } else {
                cardColumn
            }

            searchField
        }
        .frame(width: columnWidth)
        .onAppear {
            reload()
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .stackDataDidChange).receive(on: DispatchQueue.main)) { _ in
            reload()
        }
        .onHover { hovering in
            onHoverChange(hovering)
        }
        .onExitCommand(perform: onDismiss)
    }

    // MARK: - Search pill

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Search stacks…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .onSubmit(submitSelection)
                .onKeyPress(.downArrow) {
                    moveSelection(+1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(-1)
                    return .handled
                }
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(UITokens.surfaceFloater)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
        .onChange(of: searchText) { _, _ in
            // After filter changes, anchor the selection to the newest
            // matching stack (the bottom of the visible column).
            selectionIndex = max(0, filteredStacks.count - 1)
        }
    }

    // MARK: - Card column

    private var cardColumn: some View {
        ScrollViewReader { proxy in
            scrollBody
                .onAppear { scrollToNewest(proxy: proxy, animated: false) }
                .onChange(of: selectionIndex) { _, newValue in
                    scrollToSelection(proxy: proxy, index: newValue)
                }
                .onChange(of: filteredStacks.last?.id) { _, _ in
                    scrollToNewest(proxy: proxy, animated: true)
                }
        }
    }

    private var scrollBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(Array(filteredStacks.enumerated()), id: \.element.id) { index, stack in
                    drawerRow(stack: stack, isHighlighted: index == selectionIndex)
                        .id(stack.id)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: maxColumnHeight)
    }

    private func scrollToNewest(proxy: ScrollViewProxy, animated: Bool) {
        guard let last = filteredStacks.last else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.12)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func scrollToSelection(proxy: ScrollViewProxy, index: Int) {
        guard filteredStacks.indices.contains(index) else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
            proxy.scrollTo(filteredStacks[index].id, anchor: .center)
        }
    }

    @ViewBuilder
    private func drawerRow(stack: Stack, isHighlighted: Bool) -> some View {
        StackCard(
            stack: stack,
            isPinned: false,
            onTap: { onPick(stack) }
        )
        .overlay(
            RoundedRectangle(cornerRadius: UITokens.radiusCard)
                .strokeBorder(
                    isHighlighted ? Color.accentColor.opacity(0.9) : Color.clear,
                    lineWidth: isHighlighted ? 1.5 : 0
                )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.quaternary)
            Text(searchText.isEmpty ? "No other stacks yet" : "No matches")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if !searchText.isEmpty {
                Button("Clear search") { searchText = "" }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: UITokens.radiusCard)
                .fill(UITokens.surfaceFloater.opacity(0.7))
        )
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }

    // MARK: - Keyboard selection

    /// Arrow-down moves toward the anchor (newer = larger index in the
    /// reversed visible list); arrow-up moves away (older).
    private func moveSelection(_ delta: Int) {
        guard !filteredStacks.isEmpty else { return }
        let next = selectionIndex + delta
        selectionIndex = max(0, min(filteredStacks.count - 1, next))
    }

    private func submitSelection() {
        guard filteredStacks.indices.contains(selectionIndex) else { return }
        onPick(filteredStacks[selectionIndex])
    }

    // MARK: - Data

    private func reload() {
        allStacks = db.allStacks()
        if selectionIndex >= filteredStacks.count {
            selectionIndex = max(0, filteredStacks.count - 1)
        }
    }
}
