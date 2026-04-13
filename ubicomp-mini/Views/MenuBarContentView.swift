import SwiftUI

struct MenuBarContentView: View {
    @State private var searchText = ""
    @State private var highlights: [Highlight] = []
    @State private var selectedHighlight: Highlight?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Commonplace")
                    .font(.headline)
                Spacer()
                Button(action: { NoteInputController.shared.show() }) {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Button(action: { BrowseWindowController.shared.show() }) {
                    Image(systemName: "rectangle.stack")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Button(action: { BrowseWindowController.shared.showSettings() }) {
                    Image(systemName: "gear")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Search
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Search captures...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .onSubmit { performSearch() }
                        .onChange(of: searchText) { _, newValue in
                            if newValue.isEmpty { loadRecent() }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5))

                Divider()

                // Timeline
                if highlights.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "camera.viewfinder")
                            .font(.largeTitle)
                            .foregroundStyle(.quaternary)
                        Text("No captures yet")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .padding(.top, 4)
                        Text("Cmd+Shift+3 for full screen")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Cmd+Shift+4 for region")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Cmd+Shift+5 for recording")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(highlights) { highlight in
                                HighlightRow(highlight: highlight, selectedId: selectedHighlight?.id) {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        if selectedHighlight?.id == highlight.id {
                                            selectedHighlight = nil
                                        } else {
                                            selectedHighlight = highlight
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Divider()

                // Footer
                HStack {
                    Text("\(highlights.count) items")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(width: 340, height: 480)
        .onAppear { loadRecent() }
    }

    private func loadRecent() {
        highlights = DatabaseManager.shared.recentHighlights(limit: 50)
    }

    private func performSearch() {
        if searchText.isEmpty {
            loadRecent()
        } else {
            highlights = DatabaseManager.shared.searchAll(query: searchText)
        }
    }
}

// MARK: - Highlight Row

private struct HighlightRow: View {
    let highlight: Highlight
    let selectedId: String?
    let onTap: () -> Void

    private var isSelected: Bool { selectedId == highlight.id }
    private var isScreenshot: Bool { highlight.highlightType == "screenshot" }
    private var isRecording: Bool { highlight.highlightType == "recording" }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .frame(width: 14)
                        .foregroundStyle(iconColor)
                        .font(.caption)

                    if isScreenshot {
                        Text("Screenshot")
                            .font(.caption)
                            .lineLimit(1)
                    } else if isRecording {
                        Text("Recording")
                            .font(.caption)
                            .lineLimit(1)
                    } else {
                        Text(highlight.contentText.prefix(100))
                            .font(.caption)
                            .lineLimit(isSelected ? 5 : 2)
                            .truncationMode(.tail)
                    }

                    Spacer()
                }

                HStack(spacing: 4) {
                    Text(highlight.date, style: .time)
                    if let app = highlight.sourceApp {
                        Text("·")
                        Text(app)
                    }
                    if let note = highlight.userNote, !note.isEmpty {
                        Text("·")
                        Image(systemName: "note.text")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                if isSelected {
                    expandedDetail
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.001))
    }

    @ViewBuilder
    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isScreenshot {
                if let image = NSImage(contentsOfFile: highlight.contentText) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 300, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // Show OCR text if available
                if let screenshotId = highlight.screenshotId,
                   let screenshot = DatabaseManager.shared.screenshot(byId: screenshotId),
                   let ocrText = screenshot.ocrText, !ocrText.isEmpty {
                    Text(ocrText.prefix(300))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } else if isRecording {
                if let recordingId = highlight.recordingId,
                   let recording = DatabaseManager.shared.recording(byId: recordingId) {
                    if let thumb = NSImage(contentsOfFile: recording.thumbnailPath) {
                        ZStack {
                            Image(nsImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 300, maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Image(systemName: "play.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .onTapGesture {
                            NSWorkspace.shared.open(URL(fileURLWithPath: recording.filePath))
                        }
                    }
                    HStack(spacing: 8) {
                        Text(recording.formattedDuration)
                        Text(recording.formattedFileSize)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text(highlight.contentText)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }

            // Source URL
            if let url = highlight.sourceUrl, !url.isEmpty {
                if let parsed = URL(string: url) {
                    Button(action: { NSWorkspace.shared.open(parsed) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption2)
                            Text(CardMetadata.shortURL(from: url) ?? url)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Window title
            if let wt = highlight.windowTitle, !wt.isEmpty {
                Text(wt.count > 50 ? String(wt.prefix(47)) + "..." : wt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let note = highlight.userNote, !note.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.caption2)
                    Text(note)
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(.top, 2)
    }

    private var iconName: String {
        switch highlight.highlightType {
        case "screenshot": return "camera.viewfinder"
        case "recording": return "video.fill"
        case "copy": return "doc.on.clipboard"
        case "highlight": return "text.cursor"
        case "note": return "note.text"
        default: return "circle"
        }
    }

    private var iconColor: Color {
        switch highlight.highlightType {
        case "screenshot": return .blue
        case "recording": return .purple
        case "copy": return .green
        case "highlight": return .orange
        case "note": return .yellow
        default: return .secondary
        }
    }
}
