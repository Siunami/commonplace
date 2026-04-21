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
                    exportButton
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

    private var exportButton: some View {
        Button(action: exportStack) {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 10))
                Text("Export")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .help("Export stack as markdown + media")
        .disabled(items.isEmpty)
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
                LazyVGrid(columns: gridColumns, spacing: 14) {
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
                        .aspectRatio(1, contentMode: .fit)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
    }

    /// Adaptive square cells — column count scales with the window,
    /// but every cell shares the same width and (via the aspectRatio
    /// modifier above) the same height, producing the clean uniform
    /// grid the stack view had originally.
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 14)]
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
        guard let refreshed = db.stack(byId: currentStack.id) else {
            DispatchQueue.main.async(execute: onDismiss)
            return
        }
        currentStack = refreshed
        items = db.highlightsForStack(stackId: currentStack.id)
        let ids = items.map(\.id)
        noteCounts = db.noteCountsForHighlights(ids: ids)
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

    private func exportStack() {
        let panel = NSOpenPanel()
        panel.title = "Export Stack"
        panel.message = "Choose a location to save the exported stack folder."
        panel.prompt = "Export Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }

        guard panel.runModal() == .OK, let parent = panel.url else { return }

        do {
            let result = try StackExporter.export(stack: currentStack, into: parent)
            NSWorkspace.shared.activateFileViewerSelecting([result.folderURL])
        } catch StackExporter.ExportError.targetExists(let existing) {
            let alert = NSAlert()
            alert.messageText = "Folder already exists"
            alert.informativeText = "A folder named “\(existing.lastPathComponent)” already exists in the chosen location. Move or rename it and try again."
            alert.alertStyle = .warning
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

// MARK: - Grid cell
//
// The justified grid assigns each cell a fixed (width × height) box —
// all cells in a row share the same height, widths flex with the
// per-item aspect ratio. The cell fills that box: image-like types
// use aspect-fill so the thumbnail covers the whole card, text-like
// types show inline readable text. No internal aspect constraint,
// because the Layout above has already picked the box.

private struct StackDetailItemCell: View {
    let highlight: Highlight
    var noteCount: Int = 0
    var onRemove: () -> Void
    var onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cellBackground
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    @ViewBuilder
    private var cellBackground: some View {
        if isMediaLike {
            Color.black.opacity(0.35)
        } else {
            UITokens.surfaceCard
        }
    }

    @ViewBuilder
    private var content: some View {
        switch highlight.highlightType {
        case "screenshot", "recording":
            ImageThumbnail(highlight: highlight)
        case "file":
            FileThumbnail(highlight: highlight)
        case "highlight":
            TextBody(highlight: highlight, accent: Color.orange.opacity(0.8))
        case "note":
            TextBody(highlight: highlight, accent: nil)
        default:
            if highlight.isURLCopy {
                LinkThumbnail(highlight: highlight)
            } else {
                TextBody(highlight: highlight, accent: Color.primary.opacity(0.14))
            }
        }
    }

    /// Footer row that floats over every card, with a subtle gradient
    /// scrim for media cards so the timestamp stays legible. Shows the
    /// most-recent userNote for any item that has one — media OR text —
    /// so a stack always surfaces whatever commentary the user attached.
    @ViewBuilder
    private var bottomOverlay: some View {
        VStack(spacing: 4) {
            if let annotation = highlight.userNote,
               !annotation.isEmpty,
               !annotationDuplicatesContent {
                Text(annotation)
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(annotationForeground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 6) {
                AddToStackButton(highlightId: highlight.id)
                    .colorScheme(isMediaLike ? .dark : .light)
                Spacer(minLength: 4)
                Text(CardMetadata.timeAgo(from: highlight.date))
                    .font(.caption2)
                    .foregroundStyle(isMediaLike ? Color.white.opacity(0.85) : Color.secondary.opacity(0.7))
                if noteCount > 1 {
                    Text("+\(noteCount - 1)")
                        .font(.caption2)
                        .foregroundStyle(isMediaLike ? .white.opacity(0.8) : .orange.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(footerBackground)
    }

    private var annotationForeground: Color {
        isMediaLike ? Color.white.opacity(0.95) : Color.primary.opacity(0.78)
    }

    /// For note/highlight/text captures the contentText IS the user's
    /// writing — we already render it in the body, so repeating it in
    /// the footer would just waste the whole bottom of the card.
    private var annotationDuplicatesContent: Bool {
        switch highlight.highlightType {
        case "highlight", "note":
            return true
        case "screenshot", "recording", "file":
            return false
        default:
            return !highlight.isURLCopy
        }
    }

    @ViewBuilder
    private var footerBackground: some View {
        if isMediaLike {
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Color.clear
        }
    }

    private var isMediaLike: Bool {
        switch highlight.highlightType {
        case "screenshot", "recording", "file":
            return true
        default:
            return highlight.isURLCopy
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

// MARK: - Per-type content (fill whatever cell the grid provides)

private struct ImageThumbnail: View {
    let highlight: Highlight
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.35)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(Rectangle())
                } else {
                    Image(systemName: highlight.highlightType == "recording" ? "video" : "photo")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white.opacity(0.65))
                }
                if highlight.highlightType == "recording" && image != nil {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(Rectangle())
        }
        .task(id: highlight.id) {
            let path = highlight.contentText
            if let direct = await Task.detached(priority: .utility, operation: {
                NSImage(contentsOfFile: path)
            }).value {
                image = direct
                return
            }
            // Recordings / PDFs don't decode via NSImage; fall through
            // to the shared loader used by the history timeline.
            image = await HighlightThumbnailLoader.load(for: highlight)
        }
    }
}

private struct FileThumbnail: View {
    let highlight: Highlight
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.35)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(Rectangle())
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "doc")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.white.opacity(0.65))
                        if let name = fileName {
                            Text(name)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(Rectangle())
        }
        .task(id: highlight.id) {
            image = await HighlightThumbnailLoader.load(for: highlight)
        }
    }

    private var fileName: String? {
        let name = (highlight.contentText as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }
}

/// Link preview: hero image fills the cell when available, falls back
/// to favicon + host label on a neutral background.
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
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.3)

                if let heroImage {
                    Image(nsImage: heroImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(Rectangle())
                        .overlay(alignment: .topLeading) { hostBadge }
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
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Text(host ?? fallbackHost)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(Rectangle())
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

/// Inline readable text for `highlight`, `note`, and text captures.
/// The card fills whatever box the grid gives it; the text fits as
/// many lines as will fit, truncating with an ellipsis. The leading
/// accent bar mirrors the mosaic TextCard / HighlightCard styling so
/// the two surfaces read as the same family.
private struct TextBody: View {
    let highlight: Highlight
    let accent: Color?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if let accent {
                RoundedRectangle(cornerRadius: 1)
                    .fill(accent)
                    .frame(width: 3)
            }
            Text(text)
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(.primary.opacity(0.88))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 38)  // leave room for footer overlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var text: String {
        let trimmed = highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(empty)" : trimmed
    }
}

