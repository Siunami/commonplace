import SwiftUI
import Combine

/// Browseable list of every stack in the database, rendered as a single
/// clean grid of stack previews ordered by most-recent activity.
/// Empty stacks are pruned automatically so this view only shows stacks
/// that currently contain at least one item.
struct AllStacksView: View {
    var onOpenStack: (Stack) -> Void

    @State private var stacks: [Stack] = []

    private let db = DatabaseManager.shared

    var body: some View {
        Group {
            if stacks.isEmpty {
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
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .stackDataDidChange).receive(on: DispatchQueue.main)) { _ in
            reload()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Stacks")
                .font(.system(size: 20, weight: .semibold))
            Text("\(stacks.count)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(columns: gridColumns, alignment: .center, spacing: 20) {
            ForEach(stacks) { stack in
                StackGridCell(stack: stack, onOpen: { onOpenStack(stack) })
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 210), spacing: 20, alignment: .center)]
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "rectangle.stack")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.quaternary)

            VStack(spacing: 6) {
                Text("No stacks yet")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Little collections you build as you go.")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 10) {
                howToRow(number: "1", text: "Pin a stack to make it active.")
                howToRow(number: "2", text: "Tap the + on any archive item to drop it in.")
                howToRow(number: "3", text: "Revisit your stack anytime to see it all together.")
            }
            .padding(.top, 6)

            Text("Great for moodboards, research threads, or anything that belongs together.")
                .font(.system(size: 12))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func howToRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.primary.opacity(0.05)))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data

    private func reload() {
        stacks = db.allStacks()
    }
}

/// Grid cell that owns its own hover state so the pin badge can appear
/// on hover for unpinned stacks. Pinned stacks always show the unpin
/// badge (it doubles as a pinned-state indicator).
private struct StackGridCell: View {
    let stack: Stack
    let onOpen: () -> Void

    @State private var isHovered = false
    private let db = DatabaseManager.shared

    var body: some View {
        StackCard(
            stack: stack,
            isPinned: stack.isPinned,
            onTap: onOpen
        )
        .overlay(alignment: .topTrailing) {
            Group {
                if stack.isPinned {
                    StackUnpinBadge { db.setPinnedStack(id: nil) }
                } else if isHovered {
                    StackPinBadge { db.setPinnedStack(id: stack.id) }
                        .transition(.opacity)
                }
            }
            .offset(x: 6, y: -6)
        }
        .frame(maxWidth: .infinity)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}
