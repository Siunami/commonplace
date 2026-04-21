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
                StackCard(
                    stack: stack,
                    isPinned: stack.isPinned,
                    onTap: { onOpenStack(stack) }
                )
                .overlay(alignment: .topTrailing) {
                    if stack.isPinned {
                        StackUnpinBadge {
                            db.setPinnedStack(id: nil)
                        }
                        .offset(x: 6, y: -6)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 210), spacing: 20, alignment: .center)]
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "rectangle.stack")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("No stacks yet")
                .foregroundStyle(.secondary)
                .font(.callout)
            Text("In the archive, hover any item and tap the stack icon to gather related items together.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func reload() {
        stacks = db.allStacks()
    }
}
