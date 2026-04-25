import SwiftUI
import AppKit
import Combine

/// A tile representing a Stack. Intrinsic-sized so every card looks
/// identical regardless of where it's rendered (pinned floater, all-stacks
/// grid, card-detail pivot). 58pt square cells in a 3-column fill order
/// (1→2→3 across, then 4→5→6), with a label row below. The unpin
/// affordance lives outside this view — callers attach `StackUnpinBadge`
/// to whichever container is meaningful in their context.
struct StackCard: View {
    let stack: Stack
    var isPinned: Bool = false
    var onTap: (() -> Void)? = nil

    @State private var slots: [MosaicSlot] = []
    @State private var totalCount: Int = 0
    @State private var substackCount: Int = 0

    private let db = DatabaseManager.shared
    private let cellSize: CGFloat = 58

    /// Mosaic positions can hold either a highlight or a substack. The
    /// mosaic renders both as full-fidelity previews so a stack tile
    /// truthfully reflects "what's inside" even when some of the recent
    /// children are themselves stacks.
    enum MosaicSlot: Identifiable {
        case highlight(Highlight)
        case substack(Stack)

        var id: String {
            switch self {
            case .highlight(let h): return "h-\(h.id)"
            case .substack(let s): return "s-\(s.id)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Center the mosaic horizontally within the card so single-item
            // stacks aren't left-shoved when the label text makes the card
            // wider than the mosaic itself.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                mosaic
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Spacer(minLength: 0)
            }

            labelRow
        }
        .padding(12)
        .frame(width: 220)
        .background(UITokens.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: UITokens.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: UITokens.radiusCard)
                .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
        )
        .shadow(color: UITokens.shadowCard, radius: isPinned ? 14 : 6, y: isPinned ? 5 : 2)
        .contentShape(RoundedRectangle(cornerRadius: UITokens.radiusCard))
        .onTapGesture { onTap?() }
        .task(id: stack.id) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .stackDataDidChange)) { note in
            let changed = note.userInfo?["stackId"] as? String
            if changed == nil || changed == stack.id {
                reload()
            }
        }
    }

    private var labelRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stack.isNamed ? (stack.name ?? "") : "Unnamed stack")
                .font(.system(size: 12, weight: stack.isNamed ? .semibold : .regular))
                .foregroundStyle(stack.isNamed ? .primary : .secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            Text(countsSummary)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    /// Shows substack count alongside item count when a stack has any
    /// substacks, so a nested container reads as "3 stacks · 8 items"
    /// rather than hiding the tree depth behind a single number.
    private var countsSummary: String {
        if substackCount > 0 {
            return "\(substackCount) stack\(substackCount == 1 ? "" : "s") · \(totalCount) item\(totalCount == 1 ? "" : "s")"
        }
        return "\(totalCount) item\(totalCount == 1 ? "" : "s")"
    }

    // MARK: - Mosaic

    @ViewBuilder
    private var mosaic: some View {
        Group {
            if slots.isEmpty {
                emptyStackPlaceholder
            } else {
                adaptiveGrid
                    .padding(mosaicPadding)
            }
        }
        .background(backgroundFill)
    }

    /// Mosaic fills left-to-right in rows of three: 1→2→3 across row 1,
    /// then 4→5→6 across row 2. 1–3 slots render as a single row sized
    /// to the count; 4–6 slots always produce a 2-row, 3-column grid
    /// with invisible slots in unfilled positions.
    @ViewBuilder
    private var adaptiveGrid: some View {
        switch slots.count {
        case 1:
            cell(for: slots[0])
        case 2:
            HStack(spacing: mosaicSpacing) {
                cell(for: slots[0])
                cell(for: slots[1])
            }
        case 3:
            HStack(spacing: mosaicSpacing) {
                cell(for: slots[0])
                cell(for: slots[1])
                cell(for: slots[2])
            }
        default:
            VStack(spacing: mosaicSpacing) {
                HStack(spacing: mosaicSpacing) {
                    cell(for: slots[safe: 0])
                    cell(for: slots[safe: 1])
                    cell(for: slots[safe: 2])
                }
                HStack(spacing: mosaicSpacing) {
                    cell(for: slots[safe: 3])
                    cell(for: slots[safe: 4])
                    cell(for: slots[safe: 5])
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for slot: MosaicSlot?) -> some View {
        Group {
            switch slot {
            case .highlight(let h):
                StackItemPreview(highlight: h)
            case .substack(let child):
                SubstackMosaicSlot(child: child)
            case nil:
                Color.clear
            }
        }
        .frame(width: cellSize, height: cellSize)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            Group {
                if slot != nil {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
            }
        )
    }

    private var emptyStackPlaceholder: some View {
        VStack(spacing: 4) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(.tertiary)
        }
        .frame(width: cellSize, height: cellSize, alignment: .center)
    }

    /// Uses the archive floor color as the mosaic's fill so the mosaic
    /// reads as a recessed panel sitting INSIDE the card surface — same
    /// visual relationship the user has with the archive itself.
    private var backgroundFill: some View {
        UITokens.surfaceBackground
    }

    private var mosaicSpacing: CGFloat { 5 }
    private var mosaicPadding: CGFloat { 6 }

    // MARK: - Data

    private func reload() {
        // Substacks land in the mosaic first so the tile communicates the
        // tree structure — a stack with 2 substacks and 10 items reads as
        // "those 2 substacks + 4 recent items," not "10 random items."
        let substacks = db.recentSubstacksForStack(stackId: stack.id, limit: 6)
        let remaining = max(0, 6 - substacks.count)
        let highlights = remaining > 0
            ? db.recentHighlightsForStack(stackId: stack.id, limit: remaining)
            : []
        slots = substacks.map(MosaicSlot.substack)
            + highlights.map(MosaicSlot.highlight)
        totalCount = db.itemCountForStack(stackId: stack.id)
        substackCount = db.substackCountForStack(stackId: stack.id)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Compact icon-only unpin button. Designed to overlay the top-trailing
/// corner of whichever container makes sense for the caller (the glass
/// floater in BrowseView, or the StackCard itself in AllStacksView).
struct StackUnpinBadge: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "pin.slash.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isHovered ? Color.white : Color.white.opacity(0.92))
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(
                        isHovered
                            ? Color.red.opacity(0.9)
                            : Color.black.opacity(0.55)
                    )
                )
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help("Unpin this stack")
    }
}

/// Compact icon-only pin button for stacks that aren't currently pinned.
/// Paired with StackUnpinBadge so every stack card can be pinned/unpinned
/// in place without opening the detail view.
struct StackPinBadge: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "pin.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isHovered ? Color.white : Color.white.opacity(0.85))
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(
                        isHovered
                            ? Color.accentColor
                            : Color.black.opacity(0.45)
                    )
                )
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help("Pin this stack")
    }
}

// MARK: - Mini full-fidelity preview per highlight type
//
// Each branch mirrors the corresponding archive card so the stack tile
// clearly shows the items that were added. Link highlights surface the
// hero image + favicon + host so they're recognizable at mosaic scale.

/// Visually distinct slot used when one of a stack's recent children is
/// itself a substack. Fills with a faint accent so it reads as
/// "this is a stack inside another stack" at mosaic scale — differentiated
/// from highlights without requiring a recursive mini-mosaic (which would
/// be unreadable at 58pt).
private struct SubstackMosaicSlot: View {
    let child: Stack

    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.14)
            VStack(spacing: 3) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.accentColor.opacity(0.75))
                if let name = displayName {
                    Text(name)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 3)
                }
            }
        }
    }

    private var displayName: String? {
        guard child.isNamed, let name = child.name else { return nil }
        return name
    }
}

private struct StackItemPreview: View {
    let highlight: Highlight

    var body: some View {
        switch highlight.highlightType {
        case "screenshot", "recording":
            ImageCell(highlight: highlight)
        case "file":
            FileCell(highlight: highlight)
        case "highlight":
            TextSnippetCell(highlight: highlight, accent: Color.orange.opacity(0.8))
        case "note":
            NoteSnippetCell(highlight: highlight)
        default:
            if highlight.isURLCopy {
                LinkCell(highlight: highlight)
            } else {
                TextSnippetCell(highlight: highlight, accent: Color.primary.opacity(0.14))
            }
        }
    }
}

private struct ImageCell: View {
    let highlight: Highlight
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.primary.opacity(0.05)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: highlight.highlightType == "recording" ? "video" : "photo")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
        }
        .clipped()
        .task(id: highlight.id) {
            let path = highlight.contentText
            image = await Task.detached { NSImage(contentsOfFile: path) }.value
        }
    }
}

private struct FileCell: View {
    let highlight: Highlight
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.primary.opacity(0.05)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
        }
        .clipped()
        .task(id: highlight.id) {
            guard let fileId = highlight.fileId,
                  let rec = DatabaseManager.shared.fileRecord(byId: fileId) else { return }
            if let thumbPath = rec.thumbnailPath {
                image = await Task.detached { NSImage(contentsOfFile: thumbPath) }.value
            }
        }
    }
}

/// Compact link preview that mirrors the archive LinkCard's recognizable
/// elements: hero image if available, otherwise favicon + host.
private struct LinkCell: View {
    let highlight: Highlight
    @State private var heroImage: NSImage?
    @State private var favicon: NSImage?
    @State private var host: String?
    @State private var didLoad = false

    private var urlString: String {
        highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var fallbackHost: String {
        URL(string: urlString)?.host?.replacingOccurrences(of: "www.", with: "") ?? urlString
    }

    var body: some View {
        ZStack {
            Color.primary.opacity(0.05)

            if let heroImage {
                Image(nsImage: heroImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                VStack(spacing: 3) {
                    if let favicon {
                        Image(nsImage: favicon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text(host ?? fallbackHost)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 3)
                }
            }
        }
        .clipped()
        .task(id: highlight.id) {
            guard !didLoad else { return }
            didLoad = true
            let fetched = await LinkPreviewStore.shared.preview(for: urlString)
            self.host = fetched?.siteName
            if let path = fetched?.imagePath {
                self.heroImage = await Task.detached { NSImage(contentsOfFile: path) }.value
            }
            if let path = fetched?.faviconPath {
                self.favicon = await Task.detached { NSImage(contentsOfFile: path) }.value
            }
        }
    }
}

/// Snippet with a colored accent bar — mirrors HighlightCard / TextCard.
private struct TextSnippetCell: View {
    let highlight: Highlight
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 0.5)
                .fill(accent)
                .frame(width: 2)

            Text(highlight.contentText)
                .font(.system(size: 8, design: .serif))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(5)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(UITokens.surfaceCard)
    }
}

/// NoteCard mirror — no accent bar, padded text, serif body.
private struct NoteSnippetCell: View {
    let highlight: Highlight

    var body: some View {
        Text(highlight.contentText)
            .font(.system(size: 8, design: .serif))
            .foregroundStyle(.primary.opacity(0.85))
            .lineLimit(5)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(UITokens.surfaceCard)
    }
}
