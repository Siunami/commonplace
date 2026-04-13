import SwiftUI

struct TagInputView: View {
    let highlightId: String
    @Binding var tags: [Tag]
    var compact: Bool = false
    var onTagAdded: ((Tag) -> Void)?
    var onTagRemoved: ((Tag) -> Void)?

    @State private var inputText = ""
    @State private var suggestions: [Tag] = []
    @State private var popularTagsList: [Tag] = []

    var body: some View {
        if compact {
            compactMode
        } else {
            fullMode
        }
    }

    // MARK: - Full Mode (CardDetailView)

    private var fullMode: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Current tags as removable capsules
            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags) { tag in
                        TagChip(name: tag.name, onRemove: { removeTag(tag) })
                    }
                }
            }

            // Input field with autocomplete
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("Add to collection...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .onSubmit { addCurrentTag() }
                        .onChange(of: inputText) { _, newValue in
                            if newValue.count >= 1 {
                                suggestions = DatabaseManager.shared.tagsMatching(prefix: newValue, limit: 5)
                                    .filter { suggestion in !tags.contains(where: { $0.id == suggestion.id }) }
                            } else {
                                suggestions = []
                            }
                        }
                }

                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions) { tag in
                            Button(action: { applyTag(tag) }) {
                                Text(tag.name)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Compact Mode (Toast)

    private var compactMode: some View {
        HStack(spacing: 6) {
            ForEach(popularTagsList) { tag in
                let isApplied = tags.contains(where: { $0.id == tag.id })
                Button(action: { toggleTag(tag) }) {
                    HStack(spacing: 4) {
                        if isApplied {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        Text(tag.name)
                            .font(UITokens.tagFont)
                            .foregroundStyle(isApplied ? .primary : .secondary)
                    }
                    .padding(.horizontal, UITokens.tagHPad)
                    .padding(.vertical, UITokens.tagVPad)
                    .background(Capsule().fill(isApplied ? Color.primary.opacity(0.1) : UITokens.chipFill))
                    .overlay(Capsule().strokeBorder(UITokens.chipBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            popularTagsList = DatabaseManager.shared.popularTags(limit: 5)
        }
    }

    // MARK: - Actions

    private func addCurrentTag() {
        let name = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let tag = DatabaseManager.shared.findOrCreateTag(name: name) {
            applyTag(tag)
        }
    }

    private func applyTag(_ tag: Tag) {
        guard !tags.contains(where: { $0.id == tag.id }) else { return }
        DatabaseManager.shared.addTag(tag.id, toHighlight: highlightId)
        tags.append(tag)
        inputText = ""
        suggestions = []
        onTagAdded?(tag)
    }

    private func removeTag(_ tag: Tag) {
        DatabaseManager.shared.removeTag(tag.id, fromHighlight: highlightId)
        tags.removeAll { $0.id == tag.id }
        onTagRemoved?(tag)
    }

    private func toggleTag(_ tag: Tag) {
        if tags.contains(where: { $0.id == tag.id }) {
            removeTag(tag)
        } else {
            applyTag(tag)
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .init(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
