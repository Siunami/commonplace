import Foundation
import GRDB

/// Which column inside `highlight_search_fts` produced the match.
/// Drives the row badge ("image text", "note", etc.) and the row
/// layout (OCR rows get a larger thumbnail presentation).
enum MatchedColumn: Int, Equatable {
    case title = 0
    case annotation = 1
    case ocrText = 2
    case metadata = 3

    /// Short human label shown next to the source/time row.
    var badge: String {
        switch self {
        case .title: return ""           // no badge — the title IS the match
        case .annotation: return "note"
        case .ocrText: return "image text"
        case .metadata: return "source"
        }
    }

    /// Whether this match type should render the richer OCR-style
    /// row with a larger thumbnail + captioned snippet.
    var isOCR: Bool { self == .ocrText }
}

/// Sort order the sidebar passes in. Relevance uses FTS5's `bm25`
/// scoring (lower = more relevant); recency falls back to
/// `highlight.timestamp DESC`.
enum SearchSort: Equatable {
    case relevance
    case recency
}

/// One row in the search result list. Carries enough to render the
/// row without a second DB round trip per card.
struct SearchResult: Identifiable {
    let highlight: Highlight
    let matchedColumn: MatchedColumn
    let snippet: String      // text with the FTS5 `[` / `]` delimiters in place
    let score: Double        // BM25 (lower = better)

    var id: String { highlight.id }
}

extension DatabaseManager {
    /// Run an FTS5 search against `highlight_search_fts`, returning
    /// snippet + match-column info per row. One query round-trip;
    /// Swift-side picks the primary matched column via a priority
    /// order (title → annotation → ocr → metadata) based on which
    /// snippet() column returns a non-empty result.
    func searchResults(
        request: BrowseLoadRequest,
        limit: Int = 50,
        sortBy: SearchSort = .relevance
    ) -> [SearchResult] {
        guard let dbQueue else { return [] }
        guard let match = request.fts5MatchQuery else { return [] }

        let filters = BrowseFilterSQL(request.activeFilters)
        let filterSQL = filters.whereClause.isEmpty ? "" : "AND \(filters.whereClause)"

        // BM25 ranks relevance; recency sort orders by the joined
        // highlight.timestamp so the same query can serve either
        // mode without a second index path.
        let orderClause: String
        switch sortBy {
        case .relevance:
            orderClause = "ORDER BY bm25(highlight_search_fts)"
        case .recency:
            orderClause = "ORDER BY h.timestamp DESC"
        }

        // snippet()'s delimiters echo back in the result text as
        // literal `[match]` pairs so the sidebar can re-render them
        // via `SearchHighlight.render` using the same yellow bg the
        // rest of the app uses. `12` is the token-window size around
        // the match; `'…'` is the ellipsis used on either side.
        let sql = """
            SELECT
                h.id, h.timestamp, h.contentText, h.sourceApp, h.sourceUrl,
                h.userNote, h.highlightType, h.screenshotId,
                h.windowTitle, h.bundleId, h.contentHash, h.documentPath, h.contentType,
                h.recordingId, h.fileId, h.sourceContext,
                snippet(highlight_search_fts, 0, '[', ']', '…', 12) AS snippet_title,
                snippet(highlight_search_fts, 1, '[', ']', '…', 12) AS snippet_annotation,
                snippet(highlight_search_fts, 2, '[', ']', '…', 12) AS snippet_ocr,
                snippet(highlight_search_fts, 3, '[', ']', '…', 12) AS snippet_metadata,
                bm25(highlight_search_fts) AS score
            FROM highlight_search_fts
            JOIN highlight_search hs ON hs.id = highlight_search_fts.rowid
            JOIN highlight h ON h.id = hs.highlightId
            WHERE highlight_search_fts MATCH ?
            \(filterSQL)
            \(orderClause)
            LIMIT \(max(0, limit))
            """

        var args: [String] = [match]
        args.append(contentsOf: filters.arguments)

        let start = Date()
        let rows: [Row] = (try? dbQueue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }) ?? []

        var results: [SearchResult] = []
        results.reserveCapacity(rows.count)
        for row in rows {
            guard let highlight = try? Highlight(row: row) else { continue }
            let snippetTitle: String = row["snippet_title"] ?? ""
            let snippetAnnotation: String = row["snippet_annotation"] ?? ""
            let snippetOcr: String = row["snippet_ocr"] ?? ""
            let snippetMetadata: String = row["snippet_metadata"] ?? ""
            let score: Double = row["score"] ?? 0

            // Priority pick: the first column with a snippet that
            // actually contains `[` (our match delimiter). If none
            // do — can happen for exotic cases — fall back to title.
            let (column, snippet): (MatchedColumn, String)
            if snippetTitle.contains("[") {
                (column, snippet) = (.title, snippetTitle)
            } else if snippetAnnotation.contains("[") {
                (column, snippet) = (.annotation, snippetAnnotation)
            } else if snippetOcr.contains("[") {
                (column, snippet) = (.ocrText, snippetOcr)
            } else if snippetMetadata.contains("[") {
                (column, snippet) = (.metadata, snippetMetadata)
            } else {
                (column, snippet) = (.title, snippetTitle.isEmpty ? highlight.contentText : snippetTitle)
            }

            results.append(SearchResult(
                highlight: highlight,
                matchedColumn: column,
                snippet: snippet,
                score: score
            ))
        }
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        CaptureLog.info("[search-v2] '\(match)' → \(results.count) rows in \(elapsed)ms")
        return results
    }
}
