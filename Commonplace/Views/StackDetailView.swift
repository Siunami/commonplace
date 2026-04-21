import SwiftUI
import AppKit
import Combine

/// Detail view for a Stack. Presented as a modal overlay from BrowseView
/// and AllStacksView. Supports:
///   - Editing name + description
///   - Browsing all items in a responsive grid
///   - Removing items from the stack
///   - Pinning / unpinning the stack
struct StackDetailView: View {
    let stack: Stack
    var onDismiss: () -> Void
    var onOpenHighlight: (Highlight) -> Void = { _ in }

    @State private var currentStack: Stack
    @State private var items: [Highlight] = []
    @State private var noteCounts: [String: Int] = [:]
    @State private var nameDraft: String = ""
    @State private var descriptionDraft: String = ""
    @State private var isEditingName = false
    @State private var isEditingDescription = false

    init(stack: Stack, onDismiss: @escaping () -> Void, onOpenHighlight: @escaping (Highlight) -> Void = { _ in }) {
        self.stack = stack
        self.onDismiss = onDismiss
        self.onOpenHighlight = onOpenHighlight
        _currentStack = State(initialValue: stack)
        _nameDraft = State(initialValue: stack.name ?? "")
        _descriptionDraft = State(initialValue: stack.stackDescription ?? "")
    }

    private let db = DatabaseManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UITokens.surfaceBackground)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .stackDataDidChange).receive(on: DispatchQueue.main)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .highlightDataDidChange).receive(on: DispatchQueue.main)) { notification in
            let userInfo = notification.userInfo ?? [:]
            let change = userInfo["change"] as? String ?? ""
            guard let hid = userInfo["highlightId"] as? String,
                  items.contains(where: { $0.id == hid }) else { return }
            switch change {
            case "userNote":
                if let updated = db.highlight(byId: hid),
                   let idx = items.firstIndex(where: { $0.id == hid }) {
                    items[idx] = updated
                }
            case "notes":
                let counts = db.noteCountsForHighlights(ids: [hid])
                noteCounts[hid] = counts[hid] ?? 0
                if let updated = db.highlight(byId: hid),
                   let idx = items.firstIndex(where: { $0.id == hid }) {
                    items[idx] = updated
                }
            default:
                break
            }
        }
        .onExitCommand(perform: onDismiss)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    nameField
                    descriptionField
                    Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }

                Spacer()

                HStack(spacing: 8) {
                    pinToggleButton
                    closeButton
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var nameField: some View {
        if isEditingName {
            TextField("Name this stack", text: $nameDraft, onCommit: commitName)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
                .onExitCommand {
                    nameDraft = currentStack.name ?? ""
                    isEditingName = false
                }
        } else {
            Text(currentStack.isNamed ? (currentStack.name ?? "") : "Unnamed stack")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(currentStack.isNamed ? .primary : .secondary)
                .onTapGesture {
                    nameDraft = currentStack.name ?? ""
                    isEditingName = true
                }
        }
    }

    @ViewBuilder
    private var descriptionField: some View {
        if isEditingDescription {
            TextField("Add a description", text: $descriptionDraft, onCommit: commitDescription)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .onExitCommand {
                    descriptionDraft = currentStack.stackDescription ?? ""
                    isEditingDescription = false
                }
        } else {
            Text(currentStack.stackDescription?.isEmpty == false
                 ? (currentStack.stackDescription ?? "")
                 : "Add a description")
                .font(.system(size: 13))
                .foregroundStyle(currentStack.stackDescription?.isEmpty == false ? .secondary : .tertiary)
                .onTapGesture {
                    descriptionDraft = currentStack.stackDescription ?? ""
                    isEditingDescription = true
                }
        }
    }

    private var pinToggleButton: some View {
        Button(action: togglePin) {
            HStack(spacing: 4) {
                Image(systemName: currentStack.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10))
                Text(currentStack.isPinned ? "Pinned" : "Pin")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(currentStack.isPinned ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(currentStack.isPinned ? Color.accentColor : Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .help(currentStack.isPinned ? "Unpin stack" : "Pin stack")
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                    ForEach(items) { item in
                        StackDetailItemCell(
                            highlight: item,
                            noteCount: noteCounts[item.id] ?? 0,
                            onRemove: {
                                db.removeHighlight(item.id, fromStack: currentStack.id)
                            },
                            onOpen: {
                                onOpenHighlight(item)
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
    }

    /// Responsive grid: cells hold a minimum floor so thumbnails stay
    /// legible, and a ceiling so they don't balloon on wide windows.
    /// Columns flow to fill available width.
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)]
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "rectangle.stack")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("No items in this stack yet")
                .foregroundStyle(.secondary)
                .font(.callout)
            Text("Pin this stack and click the stack icon on any archive item to add it.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func reload() {
        if let refreshed = db.stack(byId: currentStack.id) {
            currentStack = refreshed
        }
        items = db.highlightsForStack(stackId: currentStack.id)
        noteCounts = db.noteCountsForHighlights(ids: items.map(\.id))
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        db.renameStack(id: currentStack.id, name: trimmed.isEmpty ? nil : trimmed)
        isEditingName = false
    }

    private func commitDescription() {
        let trimmed = descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        db.setStackDescription(id: currentStack.id, description: trimmed.isEmpty ? nil : trimmed)
        isEditingDescription = false
    }

    private func togglePin() {
        if currentStack.isPinned {
            db.setPinnedStack(id: nil)
        } else {
            db.setPinnedStack(id: currentStack.id)
        }
    }
}

// MARK: - Grid cell
//
// Mirrors MasonryCard from the archive: a single unified card surface
// (background + rounded corners + border + shadow) wraps a typed
// thumbnail and a CardFooterRow-style footer (AddToStackButton +
// timeAgo). Aspect-ratio thumbnail keeps the grid uniform; everything
// else matches the mosaic visual language.

private struct StackDetailItemCell: View {
    let highlight: Highlight
    var noteCount: Int = 0
    var onRemove: () -> Void
    var onOpen: () -> Void

    @State private var isHovered = false

    private var hasAnnotation: Bool {
        if let note = highlight.userNote, !note.isEmpty { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailArea
            footer
            if hasAnnotation {
                annotationBlock
            }
        }
        .background(UITokens.surfaceCard)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: UITokens.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: UITokens.radiusCard)
                .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
        )
        .shadow(color: UITokens.shadowCard, radius: isHovered ? 8 : 6, y: 2)
        .overlay(alignment: .topTrailing) {
            if isHovered {
                removeButton.padding(6).transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }

    private var annotationBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(highlight.userNote ?? "")
                .font(.system(.callout, design: .serif))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(4)

            if noteCount > 1 {
                Text("+\(noteCount - 1) more")
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.8))
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 0.5)
                .fill(Color.orange.opacity(0.7))
                .frame(width: 2)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var thumbnailArea: some View {
        Color.clear
            .aspectRatio(3.0 / 2.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                thumbnail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            AddToStackButton(highlightId: highlight.id)
            Spacer(minLength: 4)
            Text(CardMetadata.timeAgo(from: highlight.date))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch highlight.highlightType {
        case "screenshot", "recording":
            ImageThumbnail(highlight: highlight)
        case "file":
            FileThumbnail(highlight: highlight)
        case "highlight":
            TextThumbnail(highlight: highlight, accent: Color.orange.opacity(0.8))
        case "note":
            NoteThumbnail(highlight: highlight)
        default:
            if highlight.isURLCopy {
                LinkThumbnail(highlight: highlight)
            } else {
                TextThumbnail(highlight: highlight, accent: Color.primary.opacity(0.14))
            }
        }
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help("Remove from stack")
    }
}

// MARK: - Per-type thumbnails (grid scale)

private struct ImageThumbnail: View {
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
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: highlight.id) {
            let path = highlight.contentText
            image = await Task.detached { NSImage(contentsOfFile: path) }.value
        }
    }
}

private struct FileThumbnail: View {
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
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: highlight.id) {
            guard let fileId = highlight.fileId,
                  let rec = DatabaseManager.shared.fileRecord(byId: fileId),
                  let thumbPath = rec.thumbnailPath else { return }
            image = await Task.detached { NSImage(contentsOfFile: thumbPath) }.value
        }
    }
}

/// Mirrors LinkCard from the archive: hero image if available, otherwise
/// a favicon + host fallback on a neutral background.
private struct LinkThumbnail: View {
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
                    .overlay(alignment: .bottomLeading) { hostBadge }
            } else {
                VStack(spacing: 8) {
                    if let favicon {
                        Image(nsImage: favicon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "link")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                    Text(host ?? fallbackHost)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                }
            }
        }
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

    @ViewBuilder
    private var hostBadge: some View {
        HStack(spacing: 4) {
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11, height: 11)
            }
            Text(host ?? fallbackHost)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(.black.opacity(0.6)))
        .padding(6)
    }
}

/// Mirrors HighlightCard / TextCard: serif text with a colored accent
/// bar on the leading edge.
private struct TextThumbnail: View {
    let highlight: Highlight
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(accent)
                .frame(width: 3)

            Text(highlight.contentText)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(9)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(UITokens.surfaceCard)
    }
}

/// Mirrors NoteCard: serif text, no accent bar.
private struct NoteThumbnail: View {
    let highlight: Highlight

    var body: some View {
        Text(highlight.contentText)
            .font(.system(size: 12, design: .serif))
            .foregroundStyle(.primary.opacity(0.9))
            .lineLimit(9)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(UITokens.surfaceCard)
    }
}
