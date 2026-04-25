import Foundation
import GRDB

extension DatabaseManager {
    func browseHighlights(_ request: BrowseLoadRequest, offset: Int, limit: Int) -> [Highlight] {
        if let query = request.normalizedSearchText {
            return searchedBrowseHighlights(request, query: query, offset: offset, limit: limit)
        }
        guard let dbQueue else { return [] }

        let filters = BrowseFilterSQL(request.activeFilters)
        let whereSQL = filters.whereClause.isEmpty ? "" : "WHERE \(filters.whereClause)"
        let sql = """
            SELECT h.* FROM highlight h
            \(whereSQL)
            ORDER BY h.timestamp DESC
            LIMIT \(max(0, limit)) OFFSET \(max(0, offset))
            """
        return (try? dbQueue.read { db in
            try Highlight.fetchAll(db, sql: sql, arguments: StatementArguments(filters.arguments))
        }) ?? []
    }

    /// Total row count matching `request` — mirrors `browseHighlights`
    /// exactly so the Browse footer shows the real dataset size, not the
    /// paginated subset currently on screen.
    func browseHighlightsCount(_ request: BrowseLoadRequest) -> Int {
        if let query = request.normalizedSearchText {
            return searchedBrowseHighlightsCount(request, query: query)
        }
        guard let dbQueue else { return 0 }

        let filters = BrowseFilterSQL(request.activeFilters)
        let whereSQL = filters.whereClause.isEmpty ? "" : "WHERE \(filters.whereClause)"
        let sql = "SELECT COUNT(*) FROM highlight h \(whereSQL)"
        return (try? dbQueue.read { db in
            try Int.fetchOne(db, sql: sql, arguments: StatementArguments(filters.arguments))
        } ?? 0) ?? 0
    }

    private func searchedBrowseHighlights(
        _ request: BrowseLoadRequest,
        query: String,
        offset: Int,
        limit: Int
    ) -> [Highlight] {
        guard let dbQueue else { return [] }

        guard let match = request.fts5MatchQuery else {
            // Trimmed input parsed to nothing usable (just punctuation).
            // Return empty rather than all-rows-match.
            return []
        }

        let filters = BrowseFilterSQL(request.activeFilters)
        let filterSQL = filters.whereClause.isEmpty ? "" : "AND \(filters.whereClause)"
        let sql = """
            SELECT h.* FROM highlight h
            JOIN highlight_search hs ON hs.highlightId = h.id
            WHERE hs.id IN (
                SELECT rowid FROM highlight_search_fts
                WHERE highlight_search_fts MATCH ?
            )
            \(filterSQL)
            ORDER BY h.timestamp DESC
            LIMIT \(max(0, limit)) OFFSET \(max(0, offset))
            """

        var args: [String] = [match]
        args.append(contentsOf: filters.arguments)

        let start = Date()
        let result = (try? dbQueue.read { db in
            try Highlight.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }) ?? []
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        CaptureLog.info("[search] FTS '\(match)' → \(result.count) rows in \(elapsed)ms")
        return result
    }

    private func searchedBrowseHighlightsCount(
        _ request: BrowseLoadRequest,
        query: String
    ) -> Int {
        guard let dbQueue else { return 0 }

        guard let match = request.fts5MatchQuery else { return 0 }

        let filters = BrowseFilterSQL(request.activeFilters)
        let filterSQL = filters.whereClause.isEmpty ? "" : "AND \(filters.whereClause)"
        let sql = """
            SELECT COUNT(*) FROM highlight h
            JOIN highlight_search hs ON hs.highlightId = h.id
            WHERE hs.id IN (
                SELECT rowid FROM highlight_search_fts
                WHERE highlight_search_fts MATCH ?
            )
            \(filterSQL)
            """

        var args: [String] = [match]
        args.append(contentsOf: filters.arguments)

        return (try? dbQueue.read { db in
            try Int.fetchOne(db, sql: sql, arguments: StatementArguments(args))
        } ?? 0) ?? 0
    }

    private func allHighlightsCount() -> Int {
        (try? dbQueue?.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM highlight")
        } ?? 0) ?? 0
    }

    private func highlightCountByType(type: String) -> Int {
        (try? dbQueue?.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM highlight WHERE highlightType = ?",
                arguments: [type]
            )
        } ?? 0) ?? 0
    }

    private func highlightCountForApp(sourceApp: String) -> Int {
        (try? dbQueue?.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM highlight WHERE sourceApp = ?",
                arguments: [sourceApp]
            )
        } ?? 0) ?? 0
    }

    // MARK: - Capture Event Siblings

    /// All highlights representing the same captured "thing" as `highlight`,
    /// ordered chronologically. Resolution order:
    ///   1. `fileId` — bytes-level dedup (files auto-watched then dragged
    ///      in manually produce distinct highlights sharing one FileRecord).
    ///   2. `contentHash` — URL recaptures, text reclippings.
    ///   3. `[highlight]` alone — screenshots, recordings, notes (no key).
    /// Used by CardDetailView to render the "Captured N times" section.
    func captureEvents(for highlight: Highlight) -> [Highlight] {
        if let fileId = highlight.fileId {
            return (try? dbQueue?.read { db in
                try Highlight.fetchAll(
                    db,
                    sql: "SELECT * FROM highlight WHERE fileId = ? ORDER BY timestamp ASC",
                    arguments: [fileId]
                )
            }) ?? [highlight]
        }
        if let hash = highlight.contentHash, !hash.isEmpty {
            return (try? dbQueue?.read { db in
                try Highlight.fetchAll(
                    db,
                    sql: "SELECT * FROM highlight WHERE contentHash = ? ORDER BY timestamp ASC",
                    arguments: [hash]
                )
            }) ?? [highlight]
        }
        return [highlight]
    }

    // MARK: - Windowed Stream (jump-to-moment)

    /// Fetch a window of highlights centered on `centerTimestamp` — `before`
    /// rows older (strictly less) and `after` rows newer (strictly greater),
    /// Fetch up to `limit` rows whose timestamp is strictly greater than
    /// `ts`, ordered newest-first. Backs the All view's upward pagination
    /// in windowed mode — once the user scrolls to the top of the
    /// 75-before/75-after slice, this is what loads the rows that exist
    /// between the window's top and the global newest. Honours no
    /// filters, mirroring `jumpToHighlight`'s "drop activeFilters" rule.
    func highlightsNewer(thanTimestamp ts: Double, limit: Int) -> [Highlight] {
        guard let dbQueue else { return [] }
        return (try? dbQueue.read { db in
            let newer = try Highlight.fetchAll(
                db,
                sql: "SELECT * FROM highlight WHERE timestamp > ? ORDER BY timestamp ASC LIMIT ?",
                arguments: [ts, max(0, limit)]
            )
            // SQL returns ASC so the freshest row is last; flip to match
            // the masonry's newest-first natural order.
            return newer.reversed()
        }) ?? []
    }

    /// plus the centered row when it exists. Returned newest-first to match
    /// the masonry stream's natural direction. Used by the "jump to stream"
    /// affordance in CardDetailView's capture-events section.
    func highlightsWindow(
        centerTimestamp: Double,
        before: Int = 75,
        after: Int = 75
    ) -> [Highlight] {
        guard let dbQueue else { return [] }
        let beforeLimit = max(0, before)
        let afterLimit = max(0, after)
        return (try? dbQueue.read { db in
            let newer = try Highlight.fetchAll(
                db,
                sql: "SELECT * FROM highlight WHERE timestamp > ? ORDER BY timestamp ASC LIMIT ?",
                arguments: [centerTimestamp, afterLimit]
            )
            let center = try Highlight.fetchAll(
                db,
                sql: "SELECT * FROM highlight WHERE timestamp = ? ORDER BY timestamp DESC",
                arguments: [centerTimestamp]
            )
            let older = try Highlight.fetchAll(
                db,
                sql: "SELECT * FROM highlight WHERE timestamp < ? ORDER BY timestamp DESC LIMIT ?",
                arguments: [centerTimestamp, beforeLimit]
            )
            // newer came back ASC so we can flip it to DESC; center is already DESC; older is DESC.
            return newer.reversed() + center + older
        }) ?? []
    }
}

