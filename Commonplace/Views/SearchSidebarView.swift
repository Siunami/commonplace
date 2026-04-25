import SwiftUI
import AppKit

extension Notification.Name {
    /// Posted when the user clicks a search result. BrowseView listens
    /// and routes through its existing `jumpToHighlight` machinery so
    /// the mosaic centers + flashes the target highlight.
    static let searchSidebarJumpToHighlight = Notification.Name("searchSidebarJumpToHighlight")
    /// Posted from the `Find` menu command (Cmd+F). `WorkspaceView`
    /// listens and toggles sidebar visibility.
    static let toggleSearchSidebar = Notification.Name("toggleSearchSidebar")
}

/// Per-instance state for the search sidebar. `@Observable` so only
/// the views actually reading a field re-evaluate on change —
/// typing in the search input doesn't invalidate the surrounding
/// workspace layout.
@Observable
final class SearchSidebarModel {
    var query: String = ""
    var sortBy: SearchSort = .relevance
    var results: [SearchResult] = []
    var isSearching: Bool = false
    var selectedIndex: Int = 0

    private var debounceTask: Task<Void, Never>?

    /// Kick off a debounced search. The previous in-flight query is
    /// cancelled on every keystroke; only the settled query lands.
    @MainActor
    func runSearch(query: String) {
        self.query = query
        debounceTask?.cancel()
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = []
            isSearching = false
            selectedIndex = 0
            return
        }
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(75))
            guard !Task.isCancelled else { return }
            await self.performSearch()
        }
    }

    @MainActor
    func setSort(_ sort: SearchSort) {
        guard sort != sortBy else { return }
        sortBy = sort
        // Re-run with the new sort — no debounce, the user explicitly
        // asked for the change.
        Task { @MainActor in await self.performSearch() }
    }

    @MainActor
    private func performSearch() async {
        let q = query
        let sort = sortBy
        isSearching = true
        defer { isSearching = false }

        let request = BrowseLoadRequest(searchText: q, activeFilters: .init())
        let fetched = await Task.detached(priority: .userInitiated) {
            DatabaseManager.shared.searchResults(
                request: request,
                limit: 100,
                sortBy: sort
            )
        }.value
        // Guard against stale arrival if the user kept typing while
        // this was in-flight (the debounceTask cancellation handles
        // most cases, but the DB read runs synchronously inside the
        // detached block and can't be cancelled mid-query).
        guard !Task.isCancelled, q == query, sort == sortBy else { return }
        results = fetched
        selectedIndex = 0
    }
}

/// Dedicated search surface that lives alongside the workspace panes.
/// List-based — uniform (or OCR-taller) row heights mean SwiftUI can
/// virtualize via `LazyVStack` and never pay the measurement cost the
/// mosaic pays. Typing here does zero work on the mosaic.
struct SearchSidebarView: View {
    var onClose: () -> Void
    @State private var model = SearchSidebarModel()
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchInput
            Divider()
            if model.query.isEmpty {
                emptyStateHint
            } else if model.isSearching && model.results.isEmpty {
                loadingState
            } else if model.results.isEmpty {
                noResultsState
            } else {
                resultsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UITokens.surfaceCard)
        .onAppear { queryFocused = true }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress(.upArrow) {
            if !model.results.isEmpty {
                model.selectedIndex = max(0, model.selectedIndex - 1)
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if !model.results.isEmpty {
                model.selectedIndex = min(model.results.count - 1, model.selectedIndex + 1)
            }
            return .handled
        }
        .onKeyPress(.return) {
            if model.results.indices.contains(model.selectedIndex) {
                jump(to: model.results[model.selectedIndex])
            }
            return .handled
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Text("Search")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            sortMenu
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Close search")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            Button(action: { model.setSort(.relevance) }) {
                Label("Relevance", systemImage: model.sortBy == .relevance ? "checkmark" : "")
            }
            Button(action: { model.setSort(.recency) }) {
                Label("Most recent", systemImage: model.sortBy == .recency ? "checkmark" : "")
            }
        } label: {
            HStack(spacing: 3) {
                Text(model.sortBy == .relevance ? "Relevance" : "Recent")
                    .font(.system(size: 11))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var searchInput: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Search everything...", text: Binding(
                get: { model.query },
                set: { model.runSearch(query: $0) }
            ))
            .textFieldStyle(.plain)
            .focused($queryFocused)
            .font(.system(size: 13))
            if !model.query.isEmpty {
                Button(action: { model.runSearch(query: "") }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var emptyStateHint: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.quaternary)
            Text("Start typing to search")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Searches text, annotations, image OCR, filenames, and sources.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var loadingState: some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text("Searching...")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var noResultsState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No matches for \"\(model.query)\"")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Try a different term.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var resultsList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.results.count) result\(model.results.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { idx, result in
                        SearchResultRow(
                            result: result,
                            query: model.query,
                            isSelected: idx == model.selectedIndex
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.selectedIndex = idx
                            jump(to: result)
                        }
                        Divider().opacity(0.5)
                    }
                }
            }
        }
    }

    private func jump(to result: SearchResult) {
        NotificationCenter.default.post(
            name: .searchSidebarJumpToHighlight,
            object: nil,
            userInfo: ["highlightId": result.highlight.id]
        )
        onClose()
    }
}

/// A single row in the results list. Two layouts: standard (thumb +
/// text column) for most matches, and a taller OCR-style layout for
/// matches that landed in an image's `ocr_text` column — those get a
/// wider thumbnail up top and the snippet captioned below.
private struct SearchResultRow: View {
    let result: SearchResult
    let query: String
    let isSelected: Bool

    var body: some View {
        Group {
            if result.matchedColumn.isOCR {
                ocrLayout
            } else {
                standardLayout
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    @ViewBuilder
    private var standardLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            thumbnail(size: 44)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(renderSnippet())
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    if let app = result.highlight.sourceApp, !app.isEmpty {
                        Text(app)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text("·").foregroundStyle(.tertiary).font(.system(size: 10))
                    Text(relativeDate)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    if !result.matchedColumn.badge.isEmpty {
                        Text("·").foregroundStyle(.tertiary).font(.system(size: 10))
                        Text(result.matchedColumn.badge)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.accentColor.opacity(0.85))
                    }
                }
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var ocrLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail(size: 120)
                .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 140)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
                )
            Text(renderSnippet())
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                if let app = result.highlight.sourceApp, !app.isEmpty {
                    Text(app)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("·").foregroundStyle(.tertiary).font(.system(size: 10))
                Text(relativeDate)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("·").foregroundStyle(.tertiary).font(.system(size: 10))
                Text("image text")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
            }
        }
    }

    /// Convert the FTS5 snippet (text with literal `[` and `]`
    /// match delimiters) into an AttributedString where the matches
    /// show the same yellow highlight as the rest of the app.
    private func renderSnippet() -> AttributedString {
        let raw = result.snippet
        var out = AttributedString()
        var cursor = raw.startIndex
        while cursor < raw.endIndex {
            if let openIdx = raw[cursor...].firstIndex(of: "["),
               let closeIdx = raw[openIdx...].firstIndex(of: "]"),
               openIdx < closeIdx {
                // Plain text before the match.
                if openIdx > cursor {
                    out.append(AttributedString(String(raw[cursor..<openIdx])))
                }
                // Matched span.
                let matchStart = raw.index(after: openIdx)
                let matched = String(raw[matchStart..<closeIdx])
                var matchedAttr = AttributedString(matched)
                matchedAttr.backgroundColor = Color.yellow.opacity(0.55)
                matchedAttr.foregroundColor = .primary
                out.append(matchedAttr)
                cursor = raw.index(after: closeIdx)
            } else {
                // No more matches — append the remainder and stop.
                out.append(AttributedString(String(raw[cursor...])))
                break
            }
        }
        return out
    }

    @ViewBuilder
    private func thumbnail(size: CGFloat) -> some View {
        SearchResultThumbnail(highlight: result.highlight, size: size)
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: result.highlight.date, relativeTo: Date())
    }
}

/// Thumbnail that shares the existing `CardImageCache` + thumbnail
/// loader, so sidebar rows don't re-decode images the mosaic already
/// has in memory. Falls back to a type glyph if no image is
/// available.
private struct SearchResultThumbnail: View {
    let highlight: Highlight
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary.opacity(0.25))
                    .overlay {
                        Image(systemName: typeGlyph)
                            .font(.system(size: size * 0.35, weight: .light))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .task { await loadThumbnail() }
    }

    private var typeGlyph: String {
        switch highlight.highlightType {
        case "screenshot": return "photo"
        case "recording": return "video"
        case "highlight": return "quote.opening"
        case "note": return "square.and.pencil"
        case "file": return "doc"
        default: return highlight.isURLCopy ? "link" : "text.alignleft"
        }
    }

    private func loadThumbnail() async {
        guard image == nil else { return }
        image = await HighlightThumbnailLoader.load(for: highlight)
    }
}
