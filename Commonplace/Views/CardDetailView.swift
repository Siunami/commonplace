import SwiftUI
import AVKit
import PDFKit
import Quartz
import Combine

// MARK: - Card Detail View

struct CardDetailView: View {
    let highlight: Highlight
    var onDismiss: (() -> Void)?
    var onStackNavigation: ((Stack) -> Void)?
    var onImageFullscreen: ((NSImage) -> Void)?
    @State private var image: NSImage?
    @State private var screenshotHovered = false
    @State private var fileImageHovered = false
    @State private var notes: [HighlightNote] = []
    @State private var newNoteText = ""
    @State private var confirmationText: String?

    // Stack organization
    @State private var stacks: [Stack] = []

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
                VStack(alignment: .leading, spacing: UITokens.sectionSpacing) {
                    // Content preview
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
                        // Copied text — styled as a clipping, sized to read as
                        // the primary content. Everything else on the page is
                        // deliberately quieter so this stays center stage.
                        HStack(alignment: .top, spacing: 14) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.primary.opacity(0.15))
                                .frame(width: 3)

                            Text(highlight.contentText)
                                .font(.system(size: 18, design: .serif))
                                .lineSpacing(4)
                                .foregroundStyle(.primary.opacity(0.92))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    notesTimeline

                    // OCR text — collapsed metadata, full-width
                    if isScreenshot, let screenshotId = highlight.screenshotId,
                       let screenshot = DatabaseManager.shared.screenshot(byId: screenshotId),
                       let ocrText = screenshot.ocrText, !ocrText.isEmpty {
                        OCRTextBlock(text: ocrText)
                    }

                    // Auxiliary preview for URLs embedded inside text copies.
                    if !highlight.isURLCopy,
                       !isFile, !isScreenshot, !isRecording,
                       let embeddedURL = Self.firstEmbeddedURL(in: highlight.contentText) {
                        embeddedLinkPreviewSection(url: embeddedURL.absoluteString)
                    }

                    stackSection

                    sourceSection
                }
                .padding(20)
            }

            Divider().opacity(0.5)

            noteInput
        }
        .frame(minWidth: 520, idealWidth: 740, maxWidth: .infinity, minHeight: 420, idealHeight: 720, maxHeight: .infinity)
        .task {
            if isScreenshot && image == nil {
                let path = highlight.contentText
                image = await Task.detached {
                    NSImage(contentsOfFile: path)
                }.value
            }
            loadNotes()
            reloadStacks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stackDataDidChange).receive(on: DispatchQueue.main)) { _ in
            reloadStacks()
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

                HStack(spacing: 16) {
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
    /// Hidden when the item isn't in any stacks — items get added from the
    /// stack surfaces themselves (pinned stacks or newly created ones), not
    /// from this detail view.
    @ViewBuilder
    private var stackSection: some View {
        if !stacks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(
                    text: "In \(stacks.count) stack\(stacks.count == 1 ? "" : "s")"
                )

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(stacks) { stack in
                        StackChip(
                            stack: stack,
                            onTap: onStackNavigation.map { handler in
                                { handler(stack) }
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func removeStack(_ stack: Stack) {
        DatabaseManager.shared.removeHighlight(highlight.id, fromStack: stack.id)
    }

    // MARK: - Source

    /// Renders the page this item was captured from, when there's a
    /// sourceUrl to surface. Hidden for URL copies (the URL is already
    /// the main content) and for items captured outside the browser.
    @ViewBuilder
    private var sourceSection: some View {
        let url = highlight.sourceUrl.flatMap { raw -> String? in
            guard !raw.isEmpty, URL(string: raw) != nil else { return nil }
            return raw
        }
        let showURL = url != nil && !highlight.isURLCopy
        let app = highlight.sourceApp
        let showApp = (app?.isEmpty == false)
        // `page_url` is already rendered via EmbeddedLinkPreview.
        let contextEntries = highlight.decodedSourceContext.filter { $0.key != "page_url" }

        if showURL || showApp || !contextEntries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Source")
                VStack(alignment: .leading, spacing: 8) {
                    if showURL, let url {
                        EmbeddedLinkPreview(urlString: url)
                    }
                    if showApp, let app {
                        AppSourceBadge(appName: app, bundleId: highlight.bundleId)
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

    @ViewBuilder
    private var notesTimeline: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Notes")

                VStack(alignment: .leading, spacing: 10) {
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
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var noteInput: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("Add a note...", text: $newNoteText, axis: .vertical)
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

            Button(action: clearNote) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(noteIsEmpty ? Color.gray.opacity(0.25) : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(noteIsEmpty)
            .help("Clear")

            Button(action: submitNote) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(noteIsEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(noteIsEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Add")
        }
        .padding(.horizontal, 14)
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
