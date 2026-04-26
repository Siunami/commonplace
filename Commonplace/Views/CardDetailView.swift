import SwiftUI
import AVKit
import PDFKit
import Quartz
import Combine

/// One "filter the All view by this metadata value" intent surfaced by
/// the CardDetailView funnel buttons. Generic so adding more facets
/// (bundleId, document path, source-context entries) is just a new case.
enum CardDetailFilter {
    case app(String)
    case url(String)
}

/// Compact funnel button shared by every CardDetailView metadata chip
/// that supports "filter the All view by this value." Hover-revealed by
/// the parent so it doesn't sit as constant chrome on the chip; the
/// button itself stays styled identically across chip types so the
/// affordance reads as one consistent vocabulary.
struct FilterByFunnelButton: View {
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isHovered ? Color.accentColor : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.10)) { isHovered = hovering }
        }
    }
}

// MARK: - Card Detail View

struct CardDetailView: View {
    let highlight: Highlight
    var onDismiss: (() -> Void)?
    var onStackNavigation: ((Stack) -> Void)?
    var onImageFullscreen: ((NSImage) -> Void)?
    /// Ordered list of items the user can arrow through, in the context
    /// from which this detail was opened. When opened from a stack it's
    /// the stack's items in their user-ordered sequence; from the Browse
    /// archive it's the currently-filtered highlights in display order.
    /// Empty disables navigation.
    var siblings: [Highlight] = []
    /// Callback invoked when the user arrows to a sibling. The caller
    /// swaps `selectedHighlight`, preserving any origin context so back-
    /// navigation still works. If nil, arrow keys are inert.
    var onNavigate: ((Highlight) -> Void)?
    /// Callback invoked when the user taps a row in the "Captured N times"
    /// section to jump back to that moment in the archive. The host
    /// (BrowseView) dismisses the overlay and windows the stream around
    /// that highlight. Nil → capture-event rows render non-tappable.
    var onJumpTo: ((Highlight) -> Void)?
    /// Callback invoked when the user taps "Show in All" in the header.
    /// The host dismisses the overlay, switches the active pane to the
    /// All tab, and scroll-snaps the archive to this highlight's row.
    /// Nil → the affordance is hidden.
    var onRevealInAll: ((Highlight) -> Void)?
    /// Callback invoked when the user clicks a "filter All view by this
    /// attribute" funnel on a metadata chip in the Source section. The
    /// host adds the value to `activeFilters`, dismisses the modal, and
    /// brings the All tab forward. Nil → funnels are hidden.
    var onAddFilter: ((CardDetailFilter) -> Void)?
    /// Workspace id when this detail was opened from a workspace canvas.
    /// Threaded into `deriveFromSelection` so a derived card auto-places
    /// near the parent on the same canvas. Nil for non-workspace surfaces
    /// (the derivation still writes the highlight, just without a
    /// placement).
    var inWorkspaceId: String? = nil
    @State private var image: NSImage?
    @State private var screenshotHovered = false
    @State private var fileImageHovered = false
    @State private var notes: [HighlightNote] = []
    @State private var newNoteText = ""
    @State private var confirmationText: String?

    // Stack organization
    @State private var stacks: [Stack] = []

    /// All highlights that share identity (fileId or contentHash) with
    /// `highlight`, including `highlight` itself. Drives the "Captured N
    /// times" section. Cached so reload is cheap on data-change
    /// notifications.
    @State private var captureEvents: [Highlight] = []

    /// Gates the scroll body until every piece of data (image, notes,
    /// stacks, capture events) is in hand. Without this, each async load
    /// flips its own @State and each section pops in independently, which
    /// reads as flicker/reflow. Loading in parallel + committing in a
    /// single synchronous block collapses the arrival into one clean
    /// render. Reset on `.task` so arrow-key siblings start fresh.
    @State private var isReady = false

    /// Live selection range inside the prose body's NSTextView. Drives
    /// the enabled-state of the Derive shortcut + the range we hand to
    /// `HighlightCapture.deriveFromSelection` when the user invokes
    /// derive (floating button, right-click, or shortcut).
    @State private var selectedTextRange: NSRange = NSRange(location: 0, length: 0)
    /// Bounding rect of the current selection in the prose text view's
    /// local coordinates. Drives the floating "Create card" affordance
    /// that anchors above the selection. Nil when nothing is selected.
    @State private var selectedTextRect: CGRect? = nil

    // Video playback — controller is shared with whichever video player
    // renders (recording vs. file-video). Used to capture the current time
    // when composing a note and to seek when tapping a timestamped note.
    @StateObject private var videoController = VideoPlaybackController()

    private var isScreenshot: Bool { highlight.highlightType == "screenshot" }
    private var isRecording: Bool { highlight.highlightType == "recording" }
    private var isFile: Bool { highlight.highlightType == "file" }

    private var fileRecordIfAny: FileRecord? {
        if let fileId = highlight.fileId,
           let r = DatabaseManager.shared.fileRecord(byId: fileId) {
            return r
        }
        return DatabaseManager.shared.fileRecordByPath(highlight.contentText)
    }

    private var isVideoHighlight: Bool {
        if isRecording { return true }
        if isFile, fileRecordIfAny?.contentType == "video" { return true }
        return false
    }

    private func showConfirmation(_ text: String) {
        withAnimation(.easeInOut(duration: 0.15)) { confirmationText = text }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.3)) { confirmationText = nil }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider().opacity(0.5)

            ScrollView {
                if isReady {
                    readyContent
                } else {
                    // Blank until loadAllAndCommit finishes. Color.clear has
                    // no intrinsic height, so the scroll body is empty until
                    // every section is ready to render together.
                    Color.clear.frame(height: 1)
                }
            }

            Divider().opacity(0.5)

            noteInput
        }
        .frame(minWidth: 520, idealWidth: 740, maxWidth: .infinity, minHeight: 420, idealHeight: 720, maxHeight: .infinity)
        .background(arrowNavShortcuts)
        .background(deriveShortcut)
        .task(id: highlight.id) {
            await loadAllAndCommit()
        }
        .onReceive(NotificationCenter.default.publisher(for: .highlightDidSave).receive(on: DispatchQueue.main)) { _ in
            loadCaptureEvents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .highlightDataDidChange).receive(on: DispatchQueue.main)) { _ in
            loadCaptureEvents()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stackDataDidChange).receive(on: DispatchQueue.main)) { _ in
            reloadStacks()
        }
    }

    /// Loads image + notes + stacks + capture events in parallel and
    /// assigns them all in one synchronous block so SwiftUI renders the
    /// body exactly once with every section populated. Runs on the main
    /// actor; the image disk read is shunted to a detached task.
    private func loadAllAndCommit() async {
        // Kick off image load first (if applicable) in the background so
        // its latency runs alongside the synchronous DB reads below.
        let imageTask: Task<NSImage?, Never>? = {
            guard isScreenshot else { return nil }
            let path = highlight.contentText
            return Task.detached { NSImage(contentsOfFile: path) }
        }()

        let db = DatabaseManager.shared
        let loadedNotes = db.notesForHighlight(id: highlight.id)
        let loadedStacks = db.stacksForHighlight(id: highlight.id)
        let loadedEvents = db.captureEvents(for: highlight)
        let loadedImage = await imageTask?.value

        // Single batched commit: assigning these in sequence with no
        // intervening await lets SwiftUI coalesce them into one render.
        if let loadedImage { image = loadedImage }
        notes = loadedNotes
        stacks = loadedStacks
        captureEvents = loadedEvents
        isReady = true
    }

    /// Width cap for the reading column. Long-form prose past ~720pt
    /// becomes hard to track from line to line; capping here gives the
    /// detail view a consistent measure regardless of window width and
    /// echoes the masonry's column rhythm.
    private static let contentMaxWidth: CGFloat = 720

    /// Vertical breathing room between the primary content + notes
    /// (tight, since they're one unit of thought) and the reference
    /// sections below (loose, since they're ancillary metadata).
    private static let referenceSpacing: CGFloat = 40

    /// Extracted so the gating `if isReady { ... }` stays readable.
    @ViewBuilder
    private var readyContent: some View {
        // Two stacks: a tight primary stack (content + notes) and a
        // looser reference stack below. Both centered within the same
        // 720pt column — the eye reads top-to-bottom in one measure
        // without having to re-anchor when the window stretches wide.
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                primaryContent
                notesTimeline
            }

            ancillaryContent
                .padding(.top, Self.referenceSpacing)
        }
        .frame(maxWidth: Self.contentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private var primaryContent: some View {
        if isScreenshot {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if let onImageFullscreen {
                            ExpandImageButton(isHovered: screenshotHovered) {
                                onImageFullscreen(image)
                            }
                        }
                    }
                    .onHover { screenshotHovered = $0 }
                    .onTapGesture { onImageFullscreen?(image) }
            }
        } else if isRecording {
            recordingDetailContent
        } else if isFile {
            fileDetailContent
        } else if highlight.isURLCopy {
            if highlight.fileId != nil {
                downloadedFileLinkContent
            } else {
                linkDetailContent
            }
        } else {
            // Copied text — IS the primary content. Rendered as a
            // selectable NSTextView so the user can pick a passage and
            // derive a new card from it (Phase D). The serif/line-spacing
            // mirrors `.commonplace` so the visual reading rhythm stays
            // consistent with screenshot/file detail bodies.
            SelectableProseTextView(
                text: highlight.contentText,
                selectedRange: $selectedTextRange,
                selectedRect: $selectedTextRect,
                onDeriveSelection: { range in
                    deriveAndShowToast(range: range)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) { selectionDeriveButton }
        }
    }

    @ViewBuilder
    private var ancillaryContent: some View {
        VStack(alignment: .leading, spacing: UITokens.sectionSpacing) {
            if isScreenshot, let screenshotId = highlight.screenshotId,
               let screenshot = DatabaseManager.shared.screenshot(byId: screenshotId),
               let ocrText = screenshot.ocrText, !ocrText.isEmpty {
                OCRTextBlock(text: ocrText)
            }

            if !highlight.isURLCopy,
               !isFile, !isScreenshot, !isRecording,
               let embeddedURL = Self.firstEmbeddedURL(in: highlight.contentText) {
                embeddedLinkPreviewSection(url: embeddedURL.absoluteString)
            }

            stackSection

            captureEventsSection

            sourceSection
        }
    }

    /// ⌘⇧D — derive a new card from the currently-selected text. Only
    /// fires when the prose body has a non-empty selection; otherwise
    /// the button is disabled so the shortcut falls through to anything
    /// else that might want it.
    @ViewBuilder
    private var deriveShortcut: some View {
        Button("") {
            deriveAndShowToast(range: selectedTextRange)
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .disabled(selectedTextRange.length == 0)
        .opacity(0)
        .accessibilityHidden(true)
        .frame(width: 0, height: 0)
    }

    /// Floating affordance that hovers over the active selection in the
    /// prose body. Anchored to the top edge of the selection rect so it
    /// reads as "act on this passage" — the same convention browser
    /// translation/quote popovers use. Hidden when nothing is selected.
    @ViewBuilder
    private var selectionDeriveButton: some View {
        if selectedTextRange.length > 0, let rect = selectedTextRect {
            Button {
                deriveAndShowToast(range: selectedTextRange)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Create card")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color.accentColor)
                )
                .overlay(
                    Capsule().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .help("Create a new card from this excerpt (⌘⇧D)")
            .offset(
                x: max(0, rect.midX - 56),
                y: max(0, rect.minY - 30)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
        }
    }

    /// Write the derived card and surface the same copy-toast affordance
    /// the rest of the capture paths use, so deriving feels like any
    /// other capture event (with the bottom-right thumbnail + note
    /// composer). Provenance shown on the toast snapshots from the
    /// parent — the persisted highlight stores the same values in
    /// `inheritedProvenance` via `HighlightCapture.deriveFromSelection`.
    private func deriveAndShowToast(range: NSRange) {
        guard range.length > 0 else { return }
        guard let newId = HighlightCapture.shared.deriveFromSelection(
            parent: highlight,
            range: range,
            inWorkspaceId: inWorkspaceId
        ) else { return }

        let ns = highlight.contentText as NSString
        let safeEnd = min(range.location + range.length, ns.length)
        let safeStart = min(range.location, safeEnd)
        let safeRange = NSRange(location: safeStart, length: safeEnd - safeStart)
        let excerpt = ns.substring(with: safeRange) as String

        // Toast's annotation submit normally finds an existing
        // AnnotationStore entry — create one for the derived card so
        // notes typed in the toast persist alongside the highlight.
        AnnotationStore.shared.save(AnnotationEntry(
            id: newId,
            content: excerpt,
            timestamp: Date().timeIntervalSince1970,
            sourceApp: highlight.sourceApp,
            type: "note",
            annotation: nil
        ))

        CopyToastController.shared.show(
            content: excerpt,
            entryId: newId,
            sourceUrl: highlight.sourceUrl,
            sourceApp: highlight.sourceApp,
            windowTitle: highlight.windowTitle,
            onAnnotation: { id, note in
                AnnotationStore.shared.updateAnnotation(id: id, note: note)
                DatabaseManager.shared.addNoteToHighlight(highlightId: id, body: note)
            }
        )
    }

    /// Invisible keyboard-shortcut buttons for arrow-key gallery
    /// navigation. Rendered as a zero-size background so they
    /// participate in the window's command table but never show up
    /// visually or in accessibility. Disabled when there's no sibling
    /// list or only the current item exists.
    @ViewBuilder
    private var arrowNavShortcuts: some View {
        if let onNavigate, siblings.count > 1,
           let idx = siblings.firstIndex(where: { $0.id == highlight.id }) {
            ZStack {
                Button("") {
                    guard idx > 0 else { return }
                    onNavigate(siblings[idx - 1])
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .opacity(0)
                .accessibilityHidden(true)

                Button("") {
                    guard idx < siblings.count - 1 else { return }
                    onNavigate(siblings[idx + 1])
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .opacity(0)
                .accessibilityHidden(true)
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Header Bar (always visible)

    private var headerTitleText: String {
        if let wt = highlight.windowTitle, !wt.isEmpty { return wt }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: highlight.date)
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row — title on the left, bare-icon actions on the right
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(headerTitleText)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .layoutPriority(1)

                Spacer(minLength: 12)

                HStack(spacing: 4) {
                    InstantTooltipButton(icon: "rectangle.stack.badge.plus", label: "Add to stack") {
                        _ = DatabaseManager.shared.addHighlightToPinnedOrNewStack(highlight.id)
                        showConfirmation("Added to stack")
                    }
                    InstantTooltipButton(icon: "doc.on.doc", label: "Copy content") {
                        copyContent(); showConfirmation("Copied")
                    }
                    if isScreenshot || isFile {
                        InstantTooltipButton(icon: "folder", label: "Reveal in Finder") {
                            showInFinder(); showConfirmation("Revealed in Finder")
                        }
                    }
                    if isFile {
                        InstantTooltipButton(icon: "arrow.up.forward.app", label: "Open file") {
                            openFile(highlight.contentText); showConfirmation("Opened")
                        }
                    }
                    if let onRevealInAll {
                        InstantTooltipButton(icon: "square.grid.2x2", label: "Show in All") {
                            onRevealInAll(highlight)
                        }
                    }
                    InstantTooltipButton(icon: "xmark", label: "Close") {
                        onDismiss?()
                    }
                }
            }

            // Meta row — date/time (app + URL live in the Source card below)
            headerMetaLine
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var headerMetaLine: some View {
        let hasTitle = highlight.windowTitle?.isEmpty == false

        HStack(spacing: 0) {
            // Provenance group — just date/time. App + URL live in the Source card below.
            Group {
                if hasTitle {
                    Text(highlight.date, style: .date)
                    dot
                }
                Text(highlight.date, style: .time)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            // Inline confirmation — no pill, no background
            if let text = confirmationText {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .lineLimit(1)
    }

    private var dot: some View {
        Text(" · ")
            .font(.system(size: 12))
            .foregroundStyle(.quaternary)
    }

    // MARK: - Stacks

    /// Bottom-of-card section surfacing every stack this item belongs to.
    /// Each stack is rendered as a full StackCard — same 2x3 mosaic + label
    /// as the stacks list — so the user sees the actual state of each stack
    /// (not just a name). Hidden when the item isn't in any stacks — items
    /// get added from the stack surfaces themselves, not from this detail
    /// view.
    @ViewBuilder
    private var stackSection: some View {
        if !stacks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(
                    text: "In \(stacks.count) stack\(stacks.count == 1 ? "" : "s")"
                )

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(stacks) { stack in
                        StackCard(
                            stack: stack,
                            isPinned: stack.isPinned,
                            onTap: onStackNavigation.map { handler in
                                { handler(stack) }
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func removeStack(_ stack: Stack) {
        DatabaseManager.shared.removeHighlight(highlight.id, fromStack: stack.id)
    }

    // MARK: - Capture Events

    /// Timeline of prior/later captures of the same thing — same file
    /// bytes (fileId match) or same text/URL (contentHash match). Rendered
    /// between the stacks list and the source card, and hidden when the
    /// current highlight is the only event. Each row is tappable (via
    /// `onJumpTo`) to re-center the archive on that moment.
    @ViewBuilder
    private var captureEventsSection: some View {
        if captureEvents.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Captured \(captureEvents.count) times")

                VStack(spacing: 6) {
                    ForEach(captureEvents) { event in
                        CaptureEventRow(
                            event: event,
                            isCurrent: event.id == highlight.id,
                            onJumpTo: event.id == highlight.id ? nil : onJumpTo
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadCaptureEvents() {
        let events = DatabaseManager.shared.captureEvents(for: highlight)
        captureEvents = events
    }

    // MARK: - Source

    /// Renders the page this item was captured from, when there's a
    /// sourceUrl to surface. Hidden for URL copies (the URL is already
    /// the main content) and for items captured outside the browser.
    @ViewBuilder
    private var sourceSection: some View {
        let sanitize: (String?) -> String? = { raw in
            guard let raw, !raw.isEmpty, URL(string: raw) != nil else { return nil }
            return raw
        }
        // Fall back to the enricher-recorded page_url when sourceUrl
        // didn't land (e.g., Chrome AppleScript was slow at capture but
        // the enricher eventually succeeded and got stored in context).
        let contextPageUrl = sanitize(
            highlight.decodedSourceContext.first(where: { $0.key == "page_url" })?.url
        )
        let url = sanitize(highlight.sourceUrl) ?? contextPageUrl
        let showURL = url != nil && !highlight.isURLCopy
        let app = highlight.sourceApp
        let showApp = (app?.isEmpty == false)
        // `page_url` is already rendered via EmbeddedLinkPreview.
        let contextEntries = highlight.decodedSourceContext.filter { $0.key != "page_url" }
        // Extra sources (everything beyond the primary). The primary is
        // already covered by `AppSourceBadge` above — we're filling in
        // the other apps that contributed visible pixels to this
        // screenshot's region.
        let extraSources = highlight.decodedSources.dropFirst()

        if showURL || showApp || !contextEntries.isEmpty || !extraSources.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Source")
                VStack(alignment: .leading, spacing: 8) {
                    if showURL, let url {
                        EmbeddedLinkPreview(
                            urlString: url,
                            onAddFilter: onAddFilter.map { handler in
                                { handler(.url(url)) }
                            }
                        )
                    }
                    if showApp, let app {
                        AppSourceBadge(
                            appName: app,
                            bundleId: highlight.bundleId,
                            onAddFilter: onAddFilter.map { handler in
                                { handler(.app(app)) }
                            }
                        )
                    }
                    ForEach(Array(extraSources.enumerated()), id: \.offset) { _, source in
                        AppSourceBadge(
                            appName: source.name ?? "Unknown",
                            bundleId: source.bundleId,
                            onAddFilter: onAddFilter.flatMap { handler in
                                source.name.map { name in { handler(.app(name)) } }
                            }
                        )
                    }
                    ForEach(contextEntries, id: \.key) { entry in
                        ContextualSourceRow(entry: entry)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reloadStacks() {
        stacks = DatabaseManager.shared.stacksForHighlight(id: highlight.id)
    }

    // MARK: - Notes

    /// Notes attached to this highlight. Sit visually flush with the
    /// primary content (no SectionLabel, tight top spacing) — they're a
    /// continuation of the same unit of thought, not a sibling section.
    /// Each note carries the marginalia treatment used elsewhere in the
    /// app: thin neutral left rule, italic serif body at 0.7 opacity.
    @ViewBuilder
    private var notesTimeline: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(notes) { note in
                    NoteRow(
                        note: note,
                        onDelete: { deleteNote(note) },
                        onTimestampTap: isVideoHighlight ? { seconds in
                            videoController.seek(to: seconds)
                        } : nil
                    )
                }
            }
            .padding(.top, 4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Footer composer for adding a new note. Sits visually below the
    /// reading column at the same width so the input lines up with the
    /// notes above it. Buttons are quieter than before — small, idle
    /// tertiary, accent only when there's content to send.
    private var noteInput: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("Add a note…", text: $newNoteText, axis: .vertical)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.vertical, 6)
                .onKeyPress(.return) {
                    // Shift+Return inserts a newline (default TextField behavior).
                    // Plain Return submits.
                    if NSEvent.modifierFlags.contains(.shift) { return .ignored }
                    if noteIsEmpty { return .ignored }
                    submitNote()
                    return .handled
                }

            if !noteIsEmpty {
                Button(action: clearNote) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Clear")
                .transition(.opacity)
            }

            Button(action: submitNote) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(noteIsEmpty ? Color.secondary.opacity(0.4) : Color.white)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(noteIsEmpty ? Color.primary.opacity(0.06) : Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .disabled(noteIsEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Add note (⌘↵)")
        }
        .animation(.easeInOut(duration: 0.12), value: noteIsEmpty)
        .frame(maxWidth: Self.contentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func clearNote() {
        newNoteText = ""
    }

    private var noteIsEmpty: Bool {
        newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    private func loadNotes() {
        notes = DatabaseManager.shared.notesForHighlight(id: highlight.id)
    }

    private func submitNote() {
        let body = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let timestamp: Double? = isVideoHighlight ? videoController.currentTime : nil
        DatabaseManager.shared.addNoteToHighlight(
            highlightId: highlight.id,
            body: body,
            timestampSeconds: timestamp
        )
        newNoteText = ""
        loadNotes()
        NotificationCenter.default.post(name: .highlightDidSave, object: nil)
    }

    private func deleteNote(_ note: HighlightNote) {
        DatabaseManager.shared.deleteNote(id: note.id, highlightId: highlight.id)
        loadNotes()
    }

    private func copyContent() {
        let pb = NSPasteboard.general
        pb.clearContents()
        if isScreenshot {
            if let image { pb.writeObjects([image]) }
        } else {
            pb.setString(highlight.contentText, forType: .string)
        }
    }

    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: highlight.contentText)])
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Recording Detail

    @ViewBuilder
    private var recordingDetailContent: some View {
        let filePath = highlight.contentText
        let fileURL = URL(fileURLWithPath: filePath)
        let exists = FileManager.default.fileExists(atPath: filePath)

        VStack(alignment: .leading, spacing: 12) {
            if exists {
                InlineVideoPlayer(url: fileURL, controller: videoController)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 16) {
                    Button(action: {
                        NSWorkspace.shared.open(fileURL)
                    }) {
                        Label("Open in QuickTime", systemImage: "play.rectangle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }) {
                        Label("Show in Finder", systemImage: "folder")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Recording file not found")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Recording metadata
            if let recordingId = highlight.recordingId,
               let rec = DatabaseManager.shared.recording(byId: recordingId) {
                HStack(spacing: 16) {
                    Label(rec.formattedDuration, systemImage: "clock")
                    Label(rec.formattedFileSize, systemImage: "internaldrive")
                    if rec.hasAudio {
                        Label("Audio", systemImage: "waveform")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Link detail (full-size preview for URL copies)

    private var linkDetailContent: some View {
        DetailLinkPreview(urlString: highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Downloaded file link (URL-copy whose target file was auto-downloaded)

    @ViewBuilder
    private var downloadedFileLinkContent: some View {
        if let fileId = highlight.fileId,
           let fileRec = DatabaseManager.shared.fileRecord(byId: fileId) {
            VStack(alignment: .leading, spacing: 12) {
                filePreview(fileRec)

                HStack(spacing: 12) {
                    fileInfoRow("File", fileRec.fileName, "doc")
                    fileInfoRow("Size", fileRec.formattedFileSize, "externaldrive")
                    if let ct = fileRec.contentType {
                        fileInfoRow("Type", ct, "tag")
                    }
                }

                // Source-link row — keeps the "this was a copied link" affordance.
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    InlineLink(
                        text: highlight.contentText,
                        url: highlight.contentText
                    ) {
                        openURL(highlight.contentText)
                        showConfirmation("Opened")
                    }
                    .font(.caption)
                }
            }
        } else {
            // Download still in flight or failed — fall back to link preview.
            linkDetailContent
        }
    }

    // MARK: - Embedded link preview (URLs inside non-URL text)

    private static let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func firstEmbeddedURL(in text: String) -> URL? {
        guard let detector = urlDetector else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range),
              let url = match.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    @ViewBuilder
    private func embeddedLinkPreviewSection(url: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Link in this note")
            EmbeddedLinkPreview(urlString: url)
        }
    }

    @ViewBuilder
    private var fileDetailContent: some View {
        let fileRec: FileRecord? = {
            if let fileId = highlight.fileId,
               let r = DatabaseManager.shared.fileRecord(byId: fileId) {
                return r
            }
            return DatabaseManager.shared.fileRecordByPath(highlight.contentText)
        }()
        if let fileRec {
            VStack(alignment: .leading, spacing: 12) {
                // Inline preview based on content type
                filePreview(fileRec)

                // File info
                HStack(spacing: 12) {
                    fileInfoRow("File", fileRec.fileName, "doc")
                    fileInfoRow("Size", fileRec.formattedFileSize, "externaldrive")
                    if let ct = fileRec.contentType {
                        fileInfoRow("Type", ct, "tag")
                    }
                }

                // File existence check
                if !FileManager.default.fileExists(atPath: fileRec.filePath) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("File has been moved or deleted")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    @ViewBuilder
    private func filePreview(_ fileRec: FileRecord) -> some View {
        let ct = fileRec.contentType ?? ""
        let url = URL(fileURLWithPath: fileRec.filePath)

        let ext = url.pathExtension.lowercased()

        if ct == "pdf" {
            // Interactive PDF viewer — NSViewRepresentable has no intrinsic
            // size, so give it an explicit frame or it collapses to 0 height.
            PDFPreviewView(url: url)
                .frame(maxWidth: .infinity, minHeight: 400, idealHeight: 500, maxHeight: 600)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        } else if ct == "ebook" || ext == "epub" {
            // Full EPUB reader via Quick Look — paginated, scrollable, selectable.
            QuickLookPreviewView(url: url)
                .frame(maxWidth: .infinity, minHeight: 400, idealHeight: 520, maxHeight: 640)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        } else if ct == "image", let img = NSImage(contentsOfFile: fileRec.filePath) {
            // Full image
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxHeight: 400)
                .overlay(alignment: .topTrailing) {
                    if let onImageFullscreen {
                        ExpandImageButton(isHovered: fileImageHovered) {
                            onImageFullscreen(img)
                        }
                    }
                }
                .onHover { fileImageHovered = $0 }
                .onTapGesture { onImageFullscreen?(img) }
        } else if ct == "video" {
            // Owns its AVPlayer in @State so typing in the note field (which
            // re-runs CardDetailView.body) doesn't rebuild the player and blink.
            StableVideoPlayer(url: url, controller: videoController)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let thumbPath = fileRec.thumbnailPath,
                  let thumbImage = NSImage(contentsOfFile: thumbPath) {
            // QL thumbnail for documents etc.
            Image(nsImage: thumbImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxHeight: 300)
        } else {
            // System file icon
            HStack {
                Spacer()
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileRec.filePath))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 64)
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private func fileInfoRow(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

}

// MARK: - Stable Video Player

struct StableVideoPlayer: View {
    let url: URL
    var controller: VideoPlaybackController?
    @State private var player: AVPlayer
    @State private var timeObserverToken: Any?

    init(url: URL, controller: VideoPlaybackController? = nil) {
        self.url = url
        self.controller = controller
        self._player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                attachController()
            }
            .onDisappear {
                removeTimeObserver()
            }
            .onChange(of: url) { _, newURL in
                player.replaceCurrentItem(with: AVPlayerItem(url: newURL))
            }
    }

    private func attachController() {
        guard let controller else { return }
        controller.attach(player)
        removeTimeObserver()
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in
                controller.updateCurrentTime(time.seconds)
            }
        }
    }

    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }
}

/// Compact "from AppName" badge in the Source card. Mirrors the visual
/// treatment of EmbeddedLinkPreview so both source types compose into a
/// cohesive stack in the Source section.
private struct AppSourceBadge: View {
    let appName: String
    let bundleId: String?
    /// Optional "filter the All view by this app" affordance. When
    /// supplied, a hover-revealed funnel button appears at the trailing
    /// edge of the badge — clicking it adds an `apps` constraint to
    /// `ActiveFilters` and dismisses the detail modal.
    var onAddFilter: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            appIcon
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text("App")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(appName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if onAddFilter != nil {
                FilterByFunnelButton(help: "Filter All view by \(appName)") {
                    onAddFilter?()
                }
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let bundleId,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.15))
                .overlay {
                    Image(systemName: "app")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
        }
    }
}

/// Per-app provenance row — chat name, permalink, channel, etc. —
/// produced by a SourceEnricher at capture time. Mirrors AppSourceBadge so
/// rows compose cohesively in the Source stack.
private struct ContextualSourceRow: View {
    let entry: SourceContextEntry
    @State private var isHovered = false

    private var isTappable: Bool {
        guard let urlString = entry.url, let _ = URL(string: urlString) else { return false }
        return true
    }

    var body: some View {
        Group {
            if isTappable {
                Button(action: openURL) {
                    rowContent
                }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: entry.icon ?? "info.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if isTappable {
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(isHovered ? 0.1 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }

    private func openURL() {
        guard let urlString = entry.url, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Row in the "Captured N times" section — one per capture event for the
/// same piece of content. The current event is rendered non-tappable with
/// a filled dot; siblings act as jump-to-stream handles.
private struct CaptureEventRow: View {
    let event: Highlight
    let isCurrent: Bool
    let onJumpTo: ((Highlight) -> Void)?
    @State private var isHovered = false

    private var isTappable: Bool { !isCurrent && onJumpTo != nil }

    var body: some View {
        Group {
            if isTappable {
                Button(action: { onJumpTo?(event) }) {
                    rowContent
                }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isCurrent ? "circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(timestampLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isTappable {
                Image(systemName: "arrow.up.left.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(isCurrent ? 0.12 : (isHovered ? 0.1 : 0.06)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }

    private var timestampLabel: String {
        let base = formattedAbsolute(event.date)
        if isCurrent { return "\(base) · this one" }
        return "\(base) · \(CardMetadata.timeAgo(from: event.date))"
    }

    private var subtitle: String? {
        if isCurrent { return nil }
        if let app = event.sourceApp, !app.isEmpty { return app }
        return nil
    }

    private func formattedAbsolute(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f.string(from: date)
    }
}

/// Row in the card-detail Stacks section. Wraps a compact StackCard (same
/// visual treatment as the bottom-center pinned floater in BrowseView)
/// with a framed container + hover-to-remove affordance.
private struct StackDetailRow: View {
    let stack: Stack
    var onTap: (() -> Void)?
    var onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            StackCard(
                stack: stack,
                isPinned: stack.isPinned,
                onTap: onTap
            )

            Spacer(minLength: 0)

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove from this stack")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(isHovered ? 0.05 : 0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

/// Inline chip rendering a stack's identity in the item detail view.
/// Stack icon + name; hover reveals an X for removing the item from the stack.
struct StackChip: View {
    let stack: Stack
    var onRemove: (() -> Void)?
    var onTap: (() -> Void)?
    @State private var isHovered = false

    private var labelColor: Color {
        if onTap != nil && isHovered { return Color.accentColor }
        return isHovered ? Color.primary.opacity(0.85) : Color.primary.opacity(0.55)
    }

    private var displayName: String {
        stack.isNamed ? (stack.name ?? "Unnamed") : "Unnamed stack"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: stack.isPinned ? "pin.fill" : "rectangle.stack")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(stack.isPinned ? Color.accentColor : labelColor)
            Text(displayName)
                .font(.system(size: 12, weight: stack.isNamed ? .medium : .regular))
                .foregroundStyle(labelColor)
                .italic(!stack.isNamed)
            if isHovered, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(isHovered && onTap != nil ? 0.06 : 0.03))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
            guard onTap != nil else { return }
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

// MARK: - Derive-from-selection support

/// Selectable prose body for `CardDetailView`. Wraps an `NSTextView` so
/// the user's selection is observable (SwiftUI's `.textSelection(.enabled)`
/// hides the range from us) — derive-from-selection needs the live
/// (location, length) tuple. Inline markdown (bold/italic/links) is
/// rendered via `NSAttributedString.markdown`; block-level features the
/// MarkdownUI theme used to render are flattened to plain serif body
/// since this is the surface we need selection access on.
struct SelectableProseTextView: NSViewRepresentable {
    let text: String
    @Binding var selectedRange: NSRange
    @Binding var selectedRect: CGRect?
    var onDeriveSelection: (NSRange) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> SelectableProseNSTextView {
        let textView = SelectableProseNSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.onDeriveSelection = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return }
            coordinator.parent.onDeriveSelection(textView.selectedRange())
        }
        textView.textStorage?.setAttributedString(Self.attributed(from: text))
        return textView
    }

    func updateNSView(_ textView: SelectableProseNSTextView, context: Context) {
        // Keep a reference back to the latest parent so the closure
        // captured at make-time still hits the current SwiftUI state.
        context.coordinator.parent = self
        textView.onDeriveSelection = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return }
            coordinator.parent.onDeriveSelection(textView.selectedRange())
        }
        if textView.string != text {
            textView.textStorage?.setAttributedString(Self.attributed(from: text))
            textView.invalidateIntrinsicContentSize()
        }
    }

    static func attributed(from text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 6
        let serifDescriptor = NSFont.systemFont(ofSize: 18)
            .fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: 18).fontDescriptor
        let serifFont = NSFont(descriptor: serifDescriptor, size: 18)
            ?? NSFont.systemFont(ofSize: 18)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: serifFont,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.92),
            .paragraphStyle: paragraph
        ]
        // Inline-only markdown so newlines stay newlines (otherwise the
        // markdown parser collapses them into prose paragraphs and the
        // user sees their copied bullets and line breaks merged together).
        let parsed: NSAttributedString
        if let attr = try? NSAttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            parsed = attr
        } else {
            parsed = NSAttributedString(string: text)
        }
        let mutable = NSMutableAttributedString(attributedString: parsed)
        mutable.addAttributes(
            baseAttrs,
            range: NSRange(location: 0, length: mutable.length)
        )
        return mutable
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableProseTextView
        init(parent: SelectableProseTextView) { self.parent = parent }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let rect: CGRect? = {
                guard range.length > 0,
                      let layoutManager = textView.layoutManager,
                      let textContainer = textView.textContainer else { return nil }
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: range, actualCharacterRange: nil
                )
                let bounding = layoutManager.boundingRect(
                    forGlyphRange: glyphRange, in: textContainer
                )
                let origin = textView.textContainerOrigin
                return bounding.offsetBy(dx: origin.x, dy: origin.y)
            }()
            // SwiftUI state mutations during the AppKit selection
            // callback occasionally trigger a "modifying state during
            // view update" warning — bouncing through the main queue
            // defers the write to the next runloop tick.
            DispatchQueue.main.async {
                self.parent.selectedRange = range
                self.parent.selectedRect = rect
            }
        }

        func textView(
            _ view: NSTextView,
            menu: NSMenu,
            for event: NSEvent,
            at charIndex: Int
        ) -> NSMenu? {
            guard view.selectedRange().length > 0 else { return menu }
            let item = NSMenuItem(
                title: "Create card from selection",
                action: #selector(SelectableProseNSTextView.deriveFromSelectionAction(_:)),
                keyEquivalent: "d"
            )
            item.keyEquivalentModifierMask = [.command, .shift]
            item.target = view
            menu.insertItem(item, at: 0)
            menu.insertItem(NSMenuItem.separator(), at: 1)
            return menu
        }
    }
}

/// `NSTextView` subclass that exposes its intrinsic content size so
/// SwiftUI can lay it out in the scroll body, and routes the derive
/// menu item back through a closure to the SwiftUI parent.
final class SelectableProseNSTextView: NSTextView {
    var onDeriveSelection: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        guard let textContainer, let layoutManager else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer).size
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(used.height))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateIntrinsicContentSize()
    }

    @objc func deriveFromSelectionAction(_ sender: Any?) {
        onDeriveSelection?()
    }
}

