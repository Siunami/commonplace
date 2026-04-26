import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Body rendered for `WorkspaceTabContent.workspace(id:)`. The canvas is a
/// freeform spatial surface holding `Placement` rows.
///
/// **Architecture (post-revision):**
/// - **Infinite world** — placements live in unbounded world coordinates
///   (positive and negative). Camera (offset + zoom) transforms world to
///   screen. World origin (0,0) is centered on screen at first appearance,
///   matching TLDraw's "you start at the middle of nowhere" feel.
/// - **Pan** — single-finger click-drag on empty space updates the
///   camera offset (no inertia for V1).
/// - **Zoom** — pinch gesture (trackpad). Anchored at the layer's
///   top-left for math simplicity; recentering is a manual pan.
/// - **Snap-to-grid** — cards have a fixed width (`Self.cardWidth`).
///   The snap step is a quarter of that. Drag-end and drop-target
///   coordinates round to the nearest grid intersection so cards line
///   up automatically. Snap also applies to inline-note creation.
/// - **Single card width** — V1 enforces `Self.cardWidth` for every
///   placement on render (existing rows that were stored at smaller
///   widths render at the new uniform width). Heights default to
///   `Self.defaultCardHeight` and can be left per-row for future resize.
struct WorkspaceCanvasView: View {
    let workspaceId: String
    /// Card-detail open callback. The detail modal lives at the
    /// `BrowseView` level, so cards fire this rather than presenting
    /// locally.
    var onOpenHighlight: ((Highlight) -> Void)? = nil

    @State private var workspace: Workspace?
    @State private var workspaceVanished: Bool = false
    @State private var placements: [Placement] = []
    @State private var highlightsById: [String: Highlight] = [:]
    @State private var isEditingName: Bool = false
    @State private var nameDraft: String = ""
    @State private var isDropTargeted: Bool = false
    /// Inline note ghost card anchor in **world** coords (top-left).
    @State private var inlineNoteAnchor: CGPoint? = nil
    @State private var inlineNoteText: String = ""

    // Camera state — world->screen transform.
    // screen = world * cameraZoom + cameraOffset
    // world  = (screen - cameraOffset) / cameraZoom
    @State private var cameraOffset: CGSize = .zero
    @State private var cameraZoom: CGFloat = 1.0
    @State private var didInitCamera: Bool = false
    @GestureState private var panTranslation: CGSize = .zero
    /// Latest cursor location in canvas-local screen coords (top-left
    /// origin). Updated by `CanvasInputWrapper.onMouseMove`. The paste
    /// handler reads this to land a ⌘V paste under the cursor — keyboard
    /// events don't carry a cursor position, so we cache the latest.
    @State private var lastMousePosition: CGPoint? = nil
    // (No more `pinchMagnification` GestureState — pinch is captured at
    // the AppKit layer by `CanvasInputWrapper.magnify(with:)` and
    // mutates `cameraZoom` directly via `zoomBy(_:anchoredAt:)`. SwiftUI
    // `MagnificationGesture` was unreliable when the cursor landed on
    // a card with its own gestures.)

    // MARK: - Constants

    /// Fixed card width in world units. ~60 characters at the canvas
    /// body font (~8pt avg glyph width) + side padding lands at this
    /// value — a comfortable single-column reading measure for prose
    /// notes while still showing image/link previews legibly.
    static let cardWidth: CGFloat = 480

    /// Default card height. Two grid steps tall, a comfortable 2:1
    /// landscape ratio that suits both text and image cards.
    static let defaultCardHeight: CGFloat = 240

    /// Snap fidelity. A quarter of `cardWidth` — fine enough for tight
    /// arrangements, coarse enough that everything visibly aligns.
    static let gridStep: CGFloat = cardWidth / 4   // = 120

    /// Camera zoom limits. 25%–400% covers "see the whole pile" to
    /// "lean in on one card" without ever feeling broken.
    static let minZoom: CGFloat = 0.25
    static let maxZoom: CGFloat = 4.0

    // Drag payload type lives in `CanvasDragItem.swift`. Items arrive
    // here as `[CanvasDragItem]` via `.dropDestination`, paired with a
    // screen-local CGPoint that we convert to world coords before snap.

    // MARK: - Derived camera

    /// Composed pan = persistent + in-flight gesture delta.
    private var currentOffset: CGSize {
        CGSize(
            width: cameraOffset.width + panTranslation.width,
            height: cameraOffset.height + panTranslation.height
        )
    }

    /// Persistent zoom, clamped to limits. No longer composes an
    /// in-flight pinch state — `zoomBy(_:anchoredAt:)` writes
    /// `cameraZoom` directly on every magnify event from
    /// `CanvasInputWrapper`.
    private var currentZoom: CGFloat {
        min(Self.maxZoom, max(Self.minZoom, cameraZoom))
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let workspace {
                canvasBody(for: workspace)
            } else if workspaceVanished {
                missingWorkspaceMessage
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UITokens.surfaceBackground)
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: .workspaceDataDidChange)) { note in
            handleWorkspaceChange(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: .placementDataDidChange)) { note in
            handlePlacementChange(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: .highlightDataDidChange)) { _ in
            refreshHighlights()
        }
    }

    @ViewBuilder
    private func canvasBody(for workspace: Workspace) -> some View {
        GeometryReader { geo in
            // CanvasInputWrapper hosts the canvas content inside an NSView
            // that captures macOS scrollWheel + magnify events. Without
            // it, trackpad two-finger pan doesn't reach the canvas at all
            // and pinch dies whenever the cursor lands on a card (the
            // card's gestures eat the magnify event). Mouse clicks still
            // pass through to the SwiftUI views inside.
            CanvasInputWrapper(
                onScroll: { dx, dy, isCmd, location in
                    if isCmd {
                        // Cmd + two-finger scroll = zoom (Figma convention).
                        // 0.005 makes one full vertical swipe ≈ 50% zoom
                        // change, which feels close to TLDraw.
                        zoomBy(1.0 + dy * 0.005, anchoredAt: location)
                    } else {
                        // Two-finger pan. AppKit deltas already account
                        // for the user's natural-scrolling preference.
                        cameraOffset.width += dx
                        cameraOffset.height += dy
                    }
                },
                onMagnify: { magnification, location in
                    // event.magnification is per-event delta; convert to
                    // multiplicative factor and anchor at cursor.
                    zoomBy(1.0 + magnification, anchoredAt: location)
                },
                onMouseMove: { location in
                    // Cache cursor position so ⌘V can paste under the
                    // cursor (keyboard events don't carry a location).
                    lastMousePosition = location
                }
            ) {
                ZStack(alignment: .topLeading) {
                    // Catch-all hit surface: click-drag pan + double-click
                    // empty space. Pinch is handled by the wrapper above
                    // so it works regardless of cursor target.
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(panGesture)
                        .onTapGesture(count: 2, coordinateSpace: .local) { screenLocation in
                            openInlineNote(at: screenToWorld(screenLocation))
                        }

                    // Grid dots — drawn in screen space using camera state
                    // so density stays constant (no scaling artifacts).
                    gridLayer(in: geo.size)
                        .allowsHitTesting(false)

                    // World layer — placements + ghost note. Transformed
                    // by the camera.
                    worldLayer
                        .scaleEffect(currentZoom, anchor: .topLeading)
                        .offset(currentOffset)
                }
            }
            // Drop destination spans the entire canvas surface. `location`
            // is in this view's local coords; `screenToWorld` accounts
            // for the current camera transform.
            .dropDestination(for: CanvasDragItem.self) { items, screenLocation in
                handleCanvasDrop(items, atWorld: screenToWorld(screenLocation))
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
            // ⌘V on the canvas → land a card under the cursor. Skips
            // when an inline-note TextField has focus (the system's
            // responder chain delivers the paste to the field first,
            // which is the correct precedence).
            .onPasteCommand(of: [.text]) { providers in
                handlePaste(providers: providers)
            }
            .onAppear {
                if !didInitCamera {
                    cameraOffset = CGSize(
                        width: geo.size.width / 2,
                        height: geo.size.height / 2
                    )
                    didInitCamera = true
                }
            }
            .overlay(alignment: .topLeading) {
                header(for: workspace)
                    .padding(12)
            }
            .overlay(
                Rectangle()
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor.opacity(0.35) : Color.clear,
                        lineWidth: 2
                    )
                    .allowsHitTesting(false)
            )
            .overlay(alignment: .bottomTrailing) {
                cameraControls
                    .padding(12)
            }
        }
        // Clip the canvas to its pane frame so cards (or the empty hint
        // pinned at world origin, or the world layer at low zoom) can't
        // visually spill above into the tab strip or below into the
        // pane divider. The canvas is conceptually unbounded; only the
        // viewport renders.
        .clipped()
    }

    // MARK: - World layer

    @ViewBuilder
    private var worldLayer: some View {
        ZStack(alignment: .topLeading) {
            if placements.isEmpty && inlineNoteAnchor == nil {
                emptyHint
                    .position(x: 0, y: 0)
            }

            ForEach(placements) { placement in
                if let highlight = highlightsById[placement.cardId] {
                    // Respect each placement's stored width/height — the
                    // canvas now supports per-card resize via the bottom-
                    // right grip in CanvasCardView. Floor at one grid
                    // cell so legacy/zero-sized rows still render.
                    let cardW = max(Self.gridStep, placement.width)
                    let cardH = max(Self.gridStep, placement.height)
                    CanvasCardView(
                        highlight: highlight,
                        size: CGSize(width: cardW, height: cardH),
                        originX: placement.x,
                        originY: placement.y,
                        onOpen: { onOpenHighlight?(highlight) },
                        onMove: { translation in
                            commitMove(of: placement, by: translation)
                        },
                        onResize: { delta in
                            commitResize(of: placement, by: delta)
                        },
                        onDelete: {
                            DatabaseManager.shared.deletePlacement(id: placement.id)
                        }
                    )
                    .position(
                        x: placement.x + cardW / 2,
                        y: placement.y + cardH / 2
                    )
                }
            }

            if let anchor = inlineNoteAnchor {
                InlineNoteGhostCard(
                    text: $inlineNoteText,
                    size: CGSize(width: Self.cardWidth, height: Self.defaultCardHeight),
                    onSubmit: { commitInlineNote(at: anchor) },
                    onCancel: cancelInlineNote
                )
                .position(
                    x: anchor.x + Self.cardWidth / 2,
                    y: anchor.y + Self.defaultCardHeight / 2
                )
            }
        }
    }

    // MARK: - Grid

    /// Subtle dot grid drawn in screen coords so dot size and spacing
    /// stay constant as zoom changes. Skips when the on-screen step
    /// drops below ~10pt (too dense to read).
    private func gridLayer(in screenSize: CGSize) -> some View {
        Canvas { ctx, size in
            let z = currentZoom
            let step = Self.gridStep * z
            guard step >= 10 else { return }

            let off = currentOffset
            // First visible grid intersection in world coords (>= top-left
            // of viewport in world).
            let worldLeft = -off.width / z
            let worldTop = -off.height / z
            let worldRight = (size.width - off.width) / z
            let worldBottom = (size.height - off.height) / z

            let firstWorldX = (worldLeft / Self.gridStep).rounded(.up) * Self.gridStep
            let firstWorldY = (worldTop / Self.gridStep).rounded(.up) * Self.gridStep

            // Grid contrast bumped from 0.08 / 1.0pt to 0.18 / 1.25pt so
            // the dots actually read as a grid at default zoom. Still
            // muted enough that a dense canvas of cards reads as cards
            // first, grid second — Figma uses a similar weight.
            let dotColor = Color.primary.opacity(0.18)
            let dotRadius: CGFloat = 1.25

            var wx = firstWorldX
            while wx <= worldRight {
                var wy = firstWorldY
                while wy <= worldBottom {
                    let sx = wx * z + off.width
                    let sy = wy * z + off.height
                    let rect = CGRect(
                        x: sx - dotRadius,
                        y: sy - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                    ctx.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    wy += Self.gridStep
                }
                wx += Self.gridStep
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.split.3x3")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Empty workspace")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Drag cards in, or double-click to write a note")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Header

    @ViewBuilder
    private func header(for workspace: Workspace) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.split.3x3")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if isEditingName {
                TextField("Name this workspace", text: $nameDraft, onCommit: commitName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(minWidth: 200)
                    .onExitCommand(perform: cancelRename)
            } else {
                Text(workspace.isNamed ? (workspace.name ?? "Workspace") : "Unnamed workspace")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(workspace.isNamed ? .primary : .secondary)
                    .onTapGesture(perform: beginRename)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(UITokens.surfaceCard.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
        )
    }

    /// Bottom-right pill: zoom out, % readout, zoom in, recenter. Keeps
    /// camera state recoverable when pinch isn't available (mouse-only).
    private var cameraControls: some View {
        HStack(spacing: 4) {
            Button(action: { zoomOut() }) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Zoom out")

            Text("\(Int((currentZoom * 100).rounded()))%")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 36)

            Button(action: { zoomIn() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Zoom in")

            Divider().frame(height: 14)

            Button(action: recenter) {
                Image(systemName: "scope")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Recenter")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(UITokens.surfaceCard.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
        )
    }

    private var missingWorkspaceMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.split.3x3.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("This workspace is no longer available")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Camera math

    private func screenToWorld(_ p: CGPoint) -> CGPoint {
        let off = currentOffset
        let z = currentZoom
        return CGPoint(x: (p.x - off.width) / z, y: (p.y - off.height) / z)
    }

    private static func snap(_ value: CGFloat) -> CGFloat {
        (value / gridStep).rounded() * gridStep
    }

    private static func snapPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: snap(p.x), y: snap(p.y))
    }

    // MARK: - Camera gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($panTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                cameraOffset.width += value.translation.width
                cameraOffset.height += value.translation.height
            }
    }

    /// Cursor-anchored zoom (Figma / TLDraw style). Computes the world
    /// coordinate under `screenPoint` at the *current* zoom, then sets
    /// the new zoom and re-derives `cameraOffset` so the same world
    /// point lands on the same screen point. Without this, pinch zoom
    /// rooted at the world origin and the user had to chase content
    /// around with pan gestures.
    private func zoomBy(_ factor: CGFloat, anchoredAt screenPoint: CGPoint) {
        let oldZoom = currentZoom
        let newZoom = min(Self.maxZoom, max(Self.minZoom, oldZoom * factor))
        if newZoom == oldZoom { return }
        let off = currentOffset
        let worldX = (screenPoint.x - off.width) / oldZoom
        let worldY = (screenPoint.y - off.height) / oldZoom
        cameraZoom = newZoom
        cameraOffset.width = screenPoint.x - worldX * newZoom
        cameraOffset.height = screenPoint.y - worldY * newZoom
    }

    private func zoomIn() {
        // Anchor at viewport center so the on-screen camera button feels
        // predictable — content centers, doesn't drift toward a corner.
        cameraZoom = min(Self.maxZoom, cameraZoom * 1.25)
    }

    private func zoomOut() {
        cameraZoom = max(Self.minZoom, cameraZoom / 1.25)
    }

    /// Reset camera so world (0,0) lands at screen center and zoom = 1.
    private func recenter() {
        // Need geo size to recenter properly; without GeometryReader
        // access here, we approximate by computing from current offset
        // sign and magnitude. Simpler approach: re-trigger init.
        cameraZoom = 1.0
        // The next layout pass will preserve the previously-computed
        // half-screen offset (set on first appear). Force a fresh
        // centering by zeroing didInitCamera; .onAppear logic will
        // re-compute on the next render.
        didInitCamera = false
        cameraOffset = .zero
    }

    // MARK: - Inline rename

    private func beginRename() {
        nameDraft = workspace?.name ?? ""
        isEditingName = true
    }

    private func cancelRename() {
        nameDraft = workspace?.name ?? ""
        isEditingName = false
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        DatabaseManager.shared.renameWorkspace(
            id: workspaceId,
            name: trimmed.isEmpty ? nil : trimmed
        )
        isEditingName = false
        if var current = workspace {
            current.name = trimmed.isEmpty ? nil : trimmed
            workspace = current
        }
    }

    // MARK: - Drag-to-reposition (in-canvas)

    /// Apply a finished card drag. `translation` is already in **world
    /// units** — `DragGesture(coordinateSpace: .local)` reports
    /// translation in the receiving view's local point space, and the
    /// canvas card lives inside `.scaleEffect(zoom)`, so its local
    /// space and world space are the same coordinate system. No
    /// division by `currentZoom` (a previous version did, which
    /// double-compensated and made the card move at the wrong speed
    /// at any non-100% zoom). Optimistic in-memory write keeps the
    /// card pinned at the new spot when the gesture's `@GestureState`
    /// resets to `.zero`, avoiding flicker before the DB notification
    /// round-trips.
    private func commitMove(of placement: Placement, by translation: CGSize) {
        guard let idx = placements.firstIndex(where: { $0.id == placement.id }) else { return }
        let snapped = Self.snapPoint(CGPoint(
            x: placement.x + translation.width,
            y: placement.y + translation.height
        ))
        CaptureLog.info("[canvas drag] zoom=\(String(format: "%.2f", currentZoom)) translation=(\(Int(translation.width)),\(Int(translation.height))) → snapped=(\(Int(snapped.x)),\(Int(snapped.y)))")
        placements[idx].x = snapped.x
        placements[idx].y = snapped.y
        DatabaseManager.shared.updatePlacementPosition(id: placement.id, x: snapped.x, y: snapped.y)
    }

    /// Apply a finished resize handle drag. Same coord-space reasoning
    /// as `commitMove` — `delta` is in world units. Snap rounds size
    /// to the nearest grid step; floored at one grid cell so a card
    /// can never go below the minimum legible footprint.
    private func commitResize(of placement: Placement, by delta: CGSize) {
        guard let idx = placements.firstIndex(where: { $0.id == placement.id }) else { return }
        let rawW = placement.width + delta.width
        let rawH = placement.height + delta.height
        let snapW = max(Self.gridStep, (rawW / Self.gridStep).rounded() * Self.gridStep)
        let snapH = max(Self.gridStep, (rawH / Self.gridStep).rounded() * Self.gridStep)
        placements[idx].width = snapW
        placements[idx].height = snapH
        DatabaseManager.shared.updatePlacementSize(id: placement.id, width: snapW, height: snapH)
    }

    // MARK: - Drop handling

    /// Receives `Transferable` items decoded by `.dropDestination`.
    /// Always centers the dropped card under the cursor (top-left =
    /// world location − half the card size) and snaps to the grid so
    /// arrangements stay visually aligned. Returns true if any item
    /// was accepted, which SwiftUI uses to render the drop animation.
    private func handleCanvasDrop(_ items: [CanvasDragItem], atWorld worldLocation: CGPoint) -> Bool {
        // Diagnostic — surfaces in Console.app so the next test pass can
        // confirm the drop handler is firing at all (the prior bug was a
        // silent type-match miss before the closure ever ran).
        CaptureLog.info("[canvas drop] received \(items.count) item(s) at world (\(Int(worldLocation.x)), \(Int(worldLocation.y))) for workspace \(workspaceId)")
        guard !items.isEmpty else { return false }
        for item in items {
            placeDropped(item, atWorld: worldLocation)
        }
        return true
    }

    /// Move-or-create: if the dropped highlight already has a placement
    /// in this workspace, update its position (in-canvas drag = move).
    /// Otherwise create a new placement (cross-pane drag = add). This
    /// unification is what lets a single `.draggable` modifier on
    /// `CanvasCardView` cover both reposition AND drag-out semantics.
    private func placeDropped(_ item: CanvasDragItem, atWorld worldLocation: CGPoint) {
        switch item.kind {
        case .highlight:
            // Pick the size *before* computing top-left so an image
            // card anchors on its actual footprint, not on the text-
            // card default — otherwise a wide screenshot drops with its
            // center offset and lands askew of the cursor.
            let size = Self.defaultPlacementSize(forHighlightId: item.id)
            let topLeft = Self.snapPoint(CGPoint(
                x: worldLocation.x - size.width / 2,
                y: worldLocation.y - size.height / 2
            ))
            if let existing = DatabaseManager.shared.placement(workspaceId: workspaceId, cardId: item.id) {
                if let idx = placements.firstIndex(where: { $0.id == existing.id }) {
                    placements[idx].x = topLeft.x
                    placements[idx].y = topLeft.y
                }
                DatabaseManager.shared.updatePlacementPosition(
                    id: existing.id, x: topLeft.x, y: topLeft.y
                )
            } else {
                DatabaseManager.shared.createPlacement(
                    workspaceId: workspaceId,
                    cardId: item.id,
                    x: topLeft.x, y: topLeft.y,
                    width: size.width, height: size.height
                )
            }
        case .stack:
            let members = DatabaseManager.shared.highlightsForStack(stackId: item.id)
            let alreadyPlaced = DatabaseManager.shared.placedCardIds(
                in: workspaceId, from: members.map(\.id)
            )
            let newMembers = members.filter { !alreadyPlaced.contains($0.id) }
            // Cascade anchor uses the text-card default; per-member
            // size still honours each highlight's own type so images
            // in a stack land at their natural aspect.
            let anchorTopLeft = Self.snapPoint(CGPoint(
                x: worldLocation.x - Self.cardWidth / 2,
                y: worldLocation.y - Self.defaultCardHeight / 2
            ))
            for (i, h) in newMembers.enumerated() {
                let size = Self.defaultPlacementSize(forHighlightId: h.id)
                DatabaseManager.shared.createPlacement(
                    workspaceId: workspaceId,
                    cardId: h.id,
                    x: anchorTopLeft.x + Double(i) * Self.gridStep,
                    y: anchorTopLeft.y + Double(i) * Self.gridStep,
                    width: size.width, height: size.height
                )
            }
        }
    }

    /// Default size for a new placement, chosen by content type. Text
    /// rows take `cardWidth × defaultCardHeight`. Screenshot / file /
    /// link rows look up the source's intrinsic aspect ratio (via
    /// `aspectRatiosForHighlights`) and sit inside a `cardWidth`-wide
    /// (or tall, for portraits) box that preserves aspect, with both
    /// axes snapped to `gridStep`. Floors at one grid cell so an
    /// unknown ratio still yields something legible.
    static func defaultPlacementSize(forHighlightId id: String) -> CGSize {
        let textDefault = CGSize(width: cardWidth, height: defaultCardHeight)
        guard let highlight = DatabaseManager.shared.highlight(byId: id) else {
            return textDefault
        }
        let isMediaLike: Bool = {
            switch highlight.highlightType {
            case "screenshot", "recording", "file": return true
            default: return highlight.isURLCopy
            }
        }()
        guard isMediaLike else { return textDefault }
        let ratios = DatabaseManager.shared.aspectRatiosForHighlights(ids: [id])
        guard let ratio = ratios[id], ratio > 0 else { return textDefault }
        return mediaPlacementSize(forAspectRatio: ratio)
    }

    private static func mediaPlacementSize(forAspectRatio ratio: CGFloat) -> CGSize {
        let maxDim = cardWidth
        let rawW: CGFloat
        let rawH: CGFloat
        if ratio >= 1.0 {
            rawW = maxDim
            rawH = maxDim / ratio
        } else {
            rawH = maxDim
            rawW = maxDim * ratio
        }
        let snapW = max(gridStep, (rawW / gridStep).rounded() * gridStep)
        let snapH = max(gridStep, (rawH / gridStep).rounded() * gridStep)
        return CGSize(width: snapW, height: snapH)
    }

    // MARK: - Paste

    /// Routes a `⌘V` paste into a placement at the cursor's location.
    /// SwiftUI delivers `[NSItemProvider]` from the system pasteboard;
    /// the actual placement work runs on `MainActor` after the async
    /// load completes.
    private func handlePaste(providers: [NSItemProvider]) {
        guard let cursor = lastMousePosition else {
            CaptureLog.warning("[paste] ignored — no cursor position cached for workspace \(workspaceId)")
            return
        }
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { obj, _ in
                guard let str = obj as? String else { return }
                Task { @MainActor in
                    self.placePaste(text: str, atCanvasLocation: cursor)
                }
            }
        }
    }

    /// Hash-dedup pipeline: compute the SHA-256 of the trimmed text, look
    /// for an existing highlight with matching `contentHash`. If hit,
    /// reuse that `highlightId` (no new archive entry — the clipboard
    /// monitor likely captured this content already as a `copy`). If
    /// miss, fall through to `captureFromUserAdd` with a
    /// `.workspaceCreated` origin so the new card carries the
    /// authorship metadata. Either way, snap-place at the cursor.
    private func placePaste(text: String, atCanvasLocation screenLocation: CGPoint) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let hash = CaptureContext.contentHash(for: trimmed)
        let highlightId: String
        if let existing = DatabaseManager.shared.highlightByContentHash(hash) {
            highlightId = existing.id
            CaptureLog.info("[paste] dedup → existing highlight \(existing.id) (hash \(hash.prefix(8)))")
        } else {
            highlightId = HighlightCapture.shared.captureFromUserAdd(
                text: trimmed,
                origin: .workspaceCreated(workspaceId: workspaceId)
            )
            CaptureLog.info("[paste] no match for hash \(hash.prefix(8)) — created new highlight \(highlightId)")
        }

        let world = screenToWorld(screenLocation)
        let topLeft = Self.snapPoint(CGPoint(
            x: world.x - Self.cardWidth / 2,
            y: world.y - Self.defaultCardHeight / 2
        ))
        DatabaseManager.shared.createPlacement(
            workspaceId: workspaceId,
            cardId: highlightId,
            x: topLeft.x, y: topLeft.y,
            width: Self.cardWidth, height: Self.defaultCardHeight
        )
    }

    // MARK: - Inline note authoring

    private func openInlineNote(at worldLocation: CGPoint) {
        let topLeft = Self.snapPoint(CGPoint(
            x: worldLocation.x - Self.cardWidth / 2,
            y: worldLocation.y - Self.defaultCardHeight / 2
        ))
        inlineNoteText = ""
        inlineNoteAnchor = topLeft
    }

    private func commitInlineNote(at anchor: CGPoint) {
        let trimmed = inlineNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { cancelInlineNote(); return }
        let highlightId = HighlightCapture.shared.captureFromUserAdd(
            text: trimmed,
            origin: .workspaceCreated(workspaceId: workspaceId)
        )
        DatabaseManager.shared.createPlacement(
            workspaceId: workspaceId,
            cardId: highlightId,
            x: anchor.x, y: anchor.y,
            width: Self.cardWidth, height: Self.defaultCardHeight
        )
        inlineNoteText = ""
        inlineNoteAnchor = nil
    }

    private func cancelInlineNote() {
        inlineNoteText = ""
        inlineNoteAnchor = nil
    }

    // MARK: - Loading

    private func load() {
        guard let row = DatabaseManager.shared.workspace(byId: workspaceId) else {
            workspace = nil
            workspaceVanished = true
            return
        }
        workspace = row
        workspaceVanished = false
        loadPlacements()
    }

    private func loadPlacements() {
        let rows = DatabaseManager.shared.placementsForWorkspace(workspaceId: workspaceId)
        placements = rows
        refreshHighlights()
    }

    private func refreshHighlights() {
        var map: [String: Highlight] = [:]
        for placement in placements {
            if let h = DatabaseManager.shared.highlight(byId: placement.cardId) {
                map[placement.cardId] = h
            }
        }
        highlightsById = map
    }

    private func handleWorkspaceChange(_ note: Notification) {
        let changedId = note.userInfo?["workspaceId"] as? String
        if changedId == nil || changedId == workspaceId {
            load()
        }
    }

    private func handlePlacementChange(_ note: Notification) {
        let changedId = note.userInfo?["workspaceId"] as? String
        if changedId == nil || changedId == workspaceId {
            loadPlacements()
        }
    }
}

// MARK: - Inline Note Ghost Card

/// Card-shaped composer rendered in place when the user double-clicks
/// the empty canvas. Visually mirrors `CanvasCardView`'s chrome so the
/// authoring affordance reads as "what this card will look like." On
/// commit, the parent `WorkspaceCanvasView` writes a note + placement
/// at the same coordinates; on cancel the ghost just vanishes.
private struct InlineNoteGhostCard: View {
    @Binding var text: String
    let size: CGSize
    var onSubmit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            NoteComposerTextView(
                text: $text,
                onSubmit: onSubmit,
                onCancel: onCancel
            )
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(UITokens.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: UITokens.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: UITokens.radiusCard)
                .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.0)
        )
        .shadow(color: UITokens.shadowCard, radius: 12, y: 6)
    }
}
