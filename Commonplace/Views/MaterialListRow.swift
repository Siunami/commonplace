import SwiftUI
import AppKit

/// A single captured-material row used by both the unnamed-stack list
/// and the All-view archive list. The row treats the underlying capture
/// as the atomic element of a document: full text without truncation,
/// an 80pt leading thumbnail for media so screenshots/recordings/files
/// read as visual breakpoints, blockquoted user note, marginalia notes,
/// and a small `timeAgo` footer. Stack-only affordances (remove) are
/// opt-in via callbacks — pass nil to hide them. The drag handle was
/// retired in V1's drag unification; rows are draggable as a whole via
/// `.draggable(...)` applied by the parent.
struct MaterialListRow: View {
    let highlight: Highlight
    var noteCount: Int = 0
    /// Full bodies of every note attached to this item, oldest → newest.
    /// Rendered as a column of indented serif paragraphs beneath the
    /// primary content so the list reads as a document — every annotation
    /// is in view, never collapsed behind a count badge.
    var notes: [HighlightNote] = []
    var isSelected: Bool = false
    /// Stack-only: callback to remove this item from its parent stack.
    /// Nil hides the trailing remove affordance entirely (All-view archive).
    var onRemove: (() -> Void)? = nil
    var onOpen: () -> Void
    /// Max lines for the primary text. `nil` (default) renders full text
    /// — used by the stack list view where every row is treated as a
    /// document. The All-view archive passes a cap so really long
    /// copy-and-pastes don't dominate the vertical scroll.
    var maxPrimaryLines: Int? = nil
    /// Render the small `timeAgo` footer under the row. Defaults to true
    /// so the stack list keeps its per-item timestamp; the All-view
    /// archive turns it off because each row already lives under a
    /// time-chunk header that carries the temporal cue at a coarser,
    /// less repetitive granularity.
    var showsTimestamp: Bool = true
    /// When true, the inline notes block starts collapsed behind a
    /// "{count} notes" disclosure pill. Stack list passes true so a
    /// long-annotated highlight doesn't dominate the column; the
    /// archive keeps the default (false) so its document-style reading
    /// surfaces every annotation in view.
    var collapseNotes: Bool = false

    /// Membership of the currently-pinned stack — used to draw the
    /// leading accent bar. Sourced from `BrowseView`'s pinned-stack
    /// roster injected at the workspace root, so every row across
    /// archive + stack list + canvas reads from the same source.
    @Environment(\.pinnedStackMembers) private var pinnedStackMembers

    @State private var isHovered = false
    @State private var notesExpanded = false

    /// True when this row's highlight is in the currently-pinned stack.
    /// Drives the colored leading bar — the one place we still use
    /// colour, and only to communicate this membership relationship.
    private var isInPinnedStack: Bool {
        pinnedStackMembers.contains(highlight.id)
    }

    /// Leading thumbnail for media-type captures. Larger than a chip so
    /// screenshots/recordings/files anchor a long document visually.
    private let mediaSize: CGFloat = 80

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Pinned-stack membership bar — 3pt vertical strip on the
            // leading edge, accent-coloured when this row's highlight
            // belongs to the currently-pinned stack, transparent
            // otherwise. The slot stays present (frame width 3) either
            // way so toggling the pinned stack doesn't reflow rows.
            // This is the ONE place colour is allowed in row chrome —
            // it earns its keep by carrying a single semantic
            // (pinned-stack membership) used consistently across the
            // archive, stack list, and workspace canvas.
            Rectangle()
                .fill(isInPinnedStack ? Color.accentColor : Color.clear)
                .frame(width: 3)

            HStack(alignment: .top, spacing: 10) {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // Always-on card chrome: subtle fill + hairline border + small
        // radius. The hover state strengthens the fill and lifts the
        // border to accent — the row reads as a card at rest, then as a
        // hovered card when the cursor enters. Selection promotes the
        // border to a 1.5pt accent.
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(UITokens.surfaceCard.opacity(isHovered ? 1.0 : 0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isSelected ? Color.accentColor :
                        (isHovered ? Color.accentColor.opacity(0.3) : UITokens.surfaceBorder),
                    lineWidth: isSelected ? 1.5 : (isHovered ? 1.0 : 0.5)
                )
        )
        .overlay(alignment: .topTrailing) {
            removeAffordance
                .opacity(isHovered && !isSelected && onRemove != nil ? 1 : 0)
                .allowsHitTesting(isHovered && !isSelected && onRemove != nil)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { onOpen() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
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
        // `highlight.userNote` is a denormalized mirror of the most
        // recent `highlight_note` row's body (see
        // DatabaseManager.addNoteToHighlight). When `notes` is non-empty
        // it already contains that same row, so rendering userNote here
        // would duplicate the latest note in the row. Fall back to
        // userNote only when no structured notes exist (legacy data /
        // imports written before the highlight_note table was used).
        if notes.isEmpty, let note = highlight.userNote?.nonEmpty {
            // Same neutral marginalia treatment as `inlineNotesBlock` and
            // the timeline / detail view's NoteRow — italic serif, thin
            // primary-0.18 left rule. One vocabulary across surfaces, no
            // type-coloured chrome competing for attention.
            Text(note)
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

    private var primaryLineLimit: Int? { maxPrimaryLines }

    @ViewBuilder
    private var inlineNotesBlock: some View {
        if !notes.isEmpty {
            if collapseNotes && !notesExpanded {
                notesDisclosurePill(expanded: false)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if collapseNotes {
                        notesDisclosurePill(expanded: true)
                    }
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
    }

    /// Toggle button used in collapse mode. Tapping flips `notesExpanded`
    /// without bubbling the tap to the row's primary `onTapGesture` —
    /// users expand/collapse annotations without opening the detail.
    private func notesDisclosurePill(expanded: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                notesExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                Text("\(notes.count) note\(notes.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var metadataRow: some View {
        if showsTimestamp {
            Text(CardMetadata.timeAgo(from: highlight.date))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}

// MARK: - Per-type thumbnails

/// Neutral surface tint used as the fallback fill behind every
/// thumbnail. Replaces the old dark-on-white stack of dark fills +
/// white icons that read as a coloured chip; this is just a quiet
/// recess in the row's surface, the same vocabulary as a hover
/// background — present but uncoloured.
private let thumbnailFallbackFill: Color = Color.primary.opacity(0.05)

struct ImageThumbnail: View {
    let highlight: Highlight
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                thumbnailFallbackFill
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(Rectangle())
                } else {
                    Image(systemName: highlight.highlightType == "recording" ? "video" : "photo")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                }
                if highlight.highlightType == "recording" && image != nil {
                    // Quieter play indicator — outlined glyph, no fill,
                    // no white-on-black contrast bombing the row.
                    Image(systemName: "play.circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
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
                thumbnailFallbackFill
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(Rectangle())
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(Rectangle())
        }
        .task(id: highlight.id) {
            image = await HighlightThumbnailLoader.load(for: highlight)
        }
    }
}

/// Link preview: hero image fills the cell when available, falls back
/// to a small monochrome icon on the same neutral surface used by every
/// other thumbnail. No coloured host badge — the row body already
/// carries the URL meta line.
struct LinkThumbnail: View {
    let highlight: Highlight
    @State private var heroImage: NSImage?
    @State private var favicon: NSImage?
    @State private var didLoad = false

    private var urlString: String {
        highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                thumbnailFallbackFill

                if let heroImage {
                    Image(nsImage: heroImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(Rectangle())
                } else if let favicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(Rectangle())
        }
        .task(id: highlight.id) {
            guard !didLoad else { return }
            didLoad = true
            let fetched = await LinkPreviewStore.shared.preview(for: urlString)
            if let path = fetched?.imagePath {
                self.heroImage = await Task.detached { NSImage(contentsOfFile: path) }.value
            }
            if let path = fetched?.faviconPath {
                self.favicon = await Task.detached { NSImage(contentsOfFile: path) }.value
            }
        }
    }
}
