import SwiftUI
import AppKit

/// A single captured-material row used by both the unnamed-stack list
/// and the All-view archive list. The row treats the underlying capture
/// as the atomic element of a document: full text without truncation,
/// an 80pt leading thumbnail for media so screenshots/recordings/files
/// read as visual breakpoints, blockquoted user note, marginalia notes,
/// and a small `timeAgo` footer. Stack-only affordances (remove, drag
/// handle) are opt-in via callbacks — pass nil to hide them.
struct MaterialListRow: View {
    let highlight: Highlight
    var noteCount: Int = 0
    /// Full bodies of every note attached to this item, oldest → newest.
    /// Rendered as a column of indented serif paragraphs beneath the
    /// primary content so the list reads as a document — every annotation
    /// is in view, never collapsed behind a count badge.
    var notes: [HighlightNote] = []
    var isSelected: Bool = false
    var isBeingDragged: Bool = false
    var didJustDrag: Bool = false
    /// Stack-only: callback to remove this item from its parent stack.
    /// Nil hides the trailing remove affordance entirely (All-view archive).
    var onRemove: (() -> Void)? = nil
    var onOpen: () -> Void
    /// Parent-supplied callbacks so the row's drag handle can drive
    /// reorder state that lives in the host view. Nil hides the handle
    /// (the All-view archive doesn't reorder).
    var onHandleDragChanged: ((CGPoint) -> Void)? = nil
    var onHandleDragEnded: (() -> Void)? = nil

    @State private var isHovered = false

    /// Reserved leading gutter where the drag handle appears on hover.
    /// Fixed width so the row's content never reflows when the handle
    /// shows up.
    private let handleGutterWidth: CGFloat = 20

    /// Leading thumbnail for media-type captures. Larger than a chip so
    /// screenshots/recordings/files anchor a long document visually.
    private let mediaSize: CGFloat = 80

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Color.clear
                .frame(width: handleGutterWidth)

            if hasLeadingMedia {
                leadingMedia
                    .frame(width: mediaSize, height: mediaSize)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 6) {
                primaryText
                userNoteBlock
                inlineNotesBlock
                metadataRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .overlay(alignment: .leading) {
            dragHandle
                .opacity(isHovered && onHandleDragChanged != nil ? 1 : 0)
                .allowsHitTesting(isHovered && onHandleDragChanged != nil)
        }
        .overlay(alignment: .topTrailing) {
            removeAffordance
                .opacity(isHovered && !isSelected && onRemove != nil ? 1 : 0)
                .allowsHitTesting(isHovered && !isSelected && onRemove != nil)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: isSelected ? 1.5 : 0)
        )
        .onTapGesture {
            guard !isBeingDragged, !didJustDrag else { return }
            onOpen()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: handleGutterWidth, height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named("stackList"))
                    .onChanged { value in onHandleDragChanged?(value.location) }
                    .onEnded { _ in onHandleDragEnded?() }
            )
            .onHover { hovering in
                if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .help("Drag to reorder")
    }

    @ViewBuilder
    private var removeAffordance: some View {
        Button(action: { onRemove?() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Remove from stack")
    }

    private var hasLeadingMedia: Bool {
        switch highlight.highlightType {
        case "screenshot", "recording", "file":
            return true
        default:
            return highlight.isURLCopy
        }
    }

    @ViewBuilder
    private var leadingMedia: some View {
        switch highlight.highlightType {
        case "screenshot", "recording":
            ImageThumbnail(highlight: highlight)
        case "file":
            FileThumbnail(highlight: highlight)
        default:
            if highlight.isURLCopy {
                LinkThumbnail(highlight: highlight)
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private var primaryText: some View {
        Text(displayText)
            .font(primaryFont)
            .foregroundStyle(.primary.opacity(0.92))
            .lineLimit(primaryLineLimit)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var userNoteBlock: some View {
        if let note = highlight.userNote?.nonEmpty {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.orange.opacity(0.5))
                    .frame(width: 2)
                Text(note)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    private var displayText: String {
        switch highlight.highlightType {
        case "screenshot":
            return "Screenshot"
        case "recording":
            return "Recording"
        case "file":
            let name = (highlight.contentText as NSString).lastPathComponent
            return name.isEmpty ? highlight.contentText : name
        default:
            let trimmed = highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "(empty)" : trimmed
        }
    }

    private var primaryFont: Font {
        switch highlight.highlightType {
        case "highlight", "note":
            return .system(size: 15, design: .serif)
        default:
            return .system(size: 13, weight: .medium)
        }
    }

    private var primaryLineLimit: Int? { nil }

    @ViewBuilder
    private var inlineNotesBlock: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(notes) { note in
                    Text(note.body)
                        .font(.system(.callout, design: .serif).italic())
                        .foregroundStyle(.primary.opacity(0.7))
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.18))
                                .frame(width: 1)
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var metadataRow: some View {
        Text(CardMetadata.timeAgo(from: highlight.date))
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}

// MARK: - Per-type thumbnails

struct ImageThumbnail: View {
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
            image = await HighlightThumbnailLoader.load(for: highlight)
        }
    }
}

struct FileThumbnail: View {
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
struct LinkThumbnail: View {
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
