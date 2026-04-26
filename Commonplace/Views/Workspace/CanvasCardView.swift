import SwiftUI
import AppKit

/// Slim canvas-side renderer for one `Placement`. V1's spec calls for
/// freeform sizing (each card has its own width/height) so we can't reuse
/// `BrowseView.MasonryCard` directly — masonry assumes column-balanced
/// auto-sizing. This view does a similar type switch (screenshot / file /
/// link / text-or-note) but renders into the exact `size` the placement
/// asks for, clipping content that overflows.
///
/// Interaction:
/// - **Tap** → `onOpen` (parent routes to the existing `CardDetailView`
///   modal owned by `BrowseView`)
/// - **Drag** → `onMove(translation)` fired on gesture end so the parent
///   can apply both an optimistic in-memory update and a DB write
/// - **Right-click** → context menu with Open / Remove
struct CanvasCardView: View {
    let highlight: Highlight
    let size: CGSize
    /// World-coord top-left of this placement. Needed by the live-snap
    /// math so the card lands at the *absolute* snapped grid position,
    /// matching `WorkspaceCanvasView.commitMove`. Without this, an
    /// off-grid initial origin (legacy placements, future free-form
    /// modifier-drag) makes the visual disagree with the committed
    /// position and the card twitches at release.
    let originX: CGFloat
    let originY: CGFloat
    var onOpen: () -> Void = {}
    /// Drag-end translation. Already in **world units** (= the card's
    /// local point space, which is the world layer's local space because
    /// the world layer is what gets scaled by the camera). The parent
    /// adds it to the placement's stored x/y and snaps to grid.
    var onMove: (CGSize) -> Void = { _ in }
    /// Resize-end size delta in world units (same reasoning as `onMove`).
    var onResize: (CGSize) -> Void = { _ in }
    var onDelete: () -> Void = {}

    @Environment(\.pinnedStackMembers) private var pinnedStackMembers
    @State private var isHovered: Bool = false
    /// In-flight drag translation in **world units**. SwiftUI's
    /// `DragGesture(coordinateSpace: .local)` reports translation in
    /// the receiving view's local point space — for a view inside
    /// `.scaleEffect(zoom)`, those local points are pre-multiplied by
    /// the inverse of zoom (a 100-screen-pixel cursor drag reports as
    /// 100/zoom local points). That means `.offset(dragOffset)` applied
    /// to this view, when scaled back up by the parent's zoom, lands
    /// at exactly cursor speed: no manual division needed.
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var resizeDelta: CGSize = .zero

    private static let minDimension: CGFloat = 120
    /// Same as `WorkspaceCanvasView.gridStep`. Live-snapping needs it
    /// inline so the card can compute its own snapped offset/size
    /// without round-tripping through the parent on every drag tick.
    private static let gridStep: CGFloat = 120

    private var isInPinnedStack: Bool {
        pinnedStackMembers.contains(highlight.id)
    }

    /// Live-snapped drag offset. Card visually jumps between grid
    /// intersections as the user drags. Critical: snaps the **absolute
    /// world position** (origin + delta), not the delta alone, so the
    /// in-flight visual matches what `commitMove` will write on release.
    /// Without this alignment, an off-grid `origin` makes the card
    /// twitch on release as the visual "drag offset" zeroes out and the
    /// stored position takes over with a different value.
    private var snappedDragOffset: CGSize {
        guard dragOffset != .zero else { return .zero }
        let absX = originX + dragOffset.width
        let absY = originY + dragOffset.height
        let snapAbsX = (absX / Self.gridStep).rounded() * Self.gridStep
        let snapAbsY = (absY / Self.gridStep).rounded() * Self.gridStep
        return CGSize(
            width: snapAbsX - originX,
            height: snapAbsY - originY
        )
    }

    /// Card size during in-flight resize. `resizeDelta` is in world
    /// units; snap to the nearest grid step so the card grows in
    /// discrete cells (matches the live-snap drag behavior). Floored
    /// at `minDimension` so the card can't shrink past one grid cell.
    private var effectiveSize: CGSize {
        let snapW: CGFloat
        let snapH: CGFloat
        if resizeDelta == .zero {
            snapW = size.width
            snapH = size.height
        } else {
            let rawW = size.width + resizeDelta.width
            let rawH = size.height + resizeDelta.height
            snapW = (rawW / Self.gridStep).rounded() * Self.gridStep
            snapH = (rawH / Self.gridStep).rounded() * Self.gridStep
        }
        return CGSize(
            width: max(Self.minDimension, snapW),
            height: max(Self.minDimension, snapH)
        )
    }

    private var isInteracting: Bool {
        dragOffset != .zero || resizeDelta != .zero
    }

    var body: some View {
        content
            .frame(width: effectiveSize.width, height: effectiveSize.height, alignment: .topLeading)
            .background(UITokens.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: UITokens.radiusCard))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isInPinnedStack ? Color.accentColor : Color.clear)
                    .frame(width: 3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: UITokens.radiusCard)
                    .strokeBorder(
                        isHovered ? Color.accentColor.opacity(0.35) : UITokens.surfaceBorder,
                        lineWidth: isHovered ? 1.0 : 0.5
                    )
            )
            .overlay(alignment: .bottomTrailing) {
                resizeHandle
            }
            .shadow(
                color: UITokens.shadowCard,
                radius: isInteracting ? 14 : 6,
                y: isInteracting ? 6 : 2
            )
            .contentShape(RoundedRectangle(cornerRadius: UITokens.radiusCard))
            // Live-snapped offset — card jumps directly between grid
            // intersections, no animation. The animation that used to
            // be here (`spring(response: 0.18)`) caused a visible
            // twitch on release: as `dragOffset` reset to .zero, the
            // spring animated the offset back to 0 over 180ms while
            // the stored `originX/Y` simultaneously updated to the
            // snapped position — net result was a diagonal flash.
            // Dropping the animation makes the snap instant and
            // matches Figma/TLDraw's grid behaviour.
            .offset(snappedDragOffset)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
            }
            .onTapGesture { onOpen() }
            // Smooth in-canvas drag (Figma / Figjam style). The card
            // tracks the cursor 1:1 because `DragGesture.translation` in
            // the local coord space is already in world units (parent
            // scaleEffect collapses screen pixels to local points at
            // 1/zoom rate). On release the parent snaps to grid and
            // writes to DB.
            .gesture(
                DragGesture(minimumDistance: 4)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        onMove(value.translation)
                    }
            )
            .contextMenu {
                Button("Open card", action: onOpen)
                Divider()
                Button("Remove from workspace", role: .destructive, action: onDelete)
            }
    }

    /// Bottom-right grip that the user drags to resize. Visible on
    /// hover only; gets its own `DragGesture` so the resize drag
    /// doesn't conflict with the card's main move gesture (the handle
    /// area consumes events first).
    @ViewBuilder
    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 16)
            .background(
                Circle()
                    .fill(UITokens.surfaceCard)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            )
            .overlay(Circle().strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5))
            .padding(6)
            .opacity(isHovered || resizeDelta != .zero ? 1 : 0)
            .allowsHitTesting(isHovered || resizeDelta != .zero)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .updating($resizeDelta) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        onResize(value.translation)
                    }
            )
    }

    @ViewBuilder
    private var content: some View {
        switch highlight.highlightType {
        case "screenshot", "recording":
            mediaPreview
        case "file":
            filePreview
        case "note", "highlight":
            textPreview(serif: false)
        default:
            if highlight.isURLCopy {
                linkPreview
            } else {
                textPreview(serif: true)
            }
        }
    }

    // MARK: - Type renderers

    @ViewBuilder
    private var mediaPreview: some View {
        if let id = highlight.screenshotId,
           let record = DatabaseManager.shared.screenshot(byId: id),
           let image = NSImage(contentsOfFile: record.filePath) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: effectiveSize.width, height: effectiveSize.height)
                .clipped()
        } else {
            placeholderIcon("photo")
        }
    }

    @ViewBuilder
    private var filePreview: some View {
        if let id = highlight.fileId,
           let file = DatabaseManager.shared.fileRecord(byId: id) {
            VStack(alignment: .leading, spacing: 0) {
                if let thumbPath = file.thumbnailPath,
                   let img = NSImage(contentsOfFile: thumbPath) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: effectiveSize.width, height: max(40, effectiveSize.height - 36))
                        .clipped()
                } else {
                    Image(systemName: fileSymbol(for: file))
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: max(40, effectiveSize.height - 36))
                }
                Text(file.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            placeholderIcon("doc")
        }
    }

    @ViewBuilder
    private var linkPreview: some View {
        let preview = DatabaseManager.shared.linkPreview(forURL: highlight.contentText)
        VStack(alignment: .leading, spacing: 0) {
            if let imagePath = preview?.imagePath,
               let img = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: effectiveSize.width, height: max(40, effectiveSize.height - 60))
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(preview?.title ?? highlight.contentText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(preview?.siteName ?? URL(string: highlight.contentText)?.host ?? highlight.contentText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func textPreview(serif: Bool) -> some View {
        Text(highlight.contentText)
            .font(.system(size: 12, design: serif ? .serif : .default))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(max(1, Int(effectiveSize.height / 16)))
            .padding(10)
            .frame(width: effectiveSize.width, height: effectiveSize.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func placeholderIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 28))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileSymbol(for record: FileRecord) -> String {
        switch record.contentType {
        case "video": return "play.rectangle"
        case "image": return "photo"
        case "audio": return "waveform"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }
}
