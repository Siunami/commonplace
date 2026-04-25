import Foundation

/// Snapshot of everything that affects the All view's data fetch — search
/// text plus the active filter set. Equatable so the loader can short-
/// circuit redundant reloads.
struct BrowseLoadRequest: Equatable {
    let searchText: String
    let activeFilters: ActiveFilters

    var normalizedSearchText: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// FTS5 MATCH expression for `highlight_search_fts`. Strips syntax
    /// characters so user input can't accidentally invoke FTS5 operators
    /// (quoted phrases, NEAR, column filters) and appends `*` to each
    /// token for prefix matching — so "pret" matches "pretext" as the
    /// user types. Returns nil when the trimmed query has no usable
    /// tokens so callers can skip the MATCH join entirely.
    var fts5MatchQuery: String? {
        guard let trimmed = normalizedSearchText else { return nil }
        let stripped = trimmed
            .replacingOccurrences(of: "\"", with: " ")
            .replacingOccurrences(of: "*", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "^", with: " ")
        let tokens = stripped
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\($0)*" }.joined(separator: " ")
    }

    var hasActiveSearch: Bool {
        normalizedSearchText != nil
    }

    var hasActiveFilters: Bool {
        !activeFilters.isEmpty
    }

    func shouldReloadOnHighlightMutation(change: String) -> Bool {
        if hasActiveSearch {
            return change == "notes" || change == "userNote"
        }
        return false
    }
}

/// Compiled SQL fragment for the `WHERE` portion of a Browse query. Built
/// from `ActiveFilters` and reused by both the row fetcher and the count
/// query so paging + footer stay in lockstep. AND across every selected
/// filter (including within a facet) — "everything is AND" so the popover
/// pruning can hide any candidate that would zero out the result set.
struct BrowseFilterSQL {
    /// Composite WHERE expression already wrapped in parens. Empty string
    /// when no filters are active — caller short-circuits and skips the
    /// WHERE entirely (or appends `AND 1=1` if joining with other
    /// constraints).
    let whereClause: String
    let arguments: [String]

    init(_ filters: ActiveFilters) {
        var parts: [String] = []
        var args: [String] = []

        // Stable ordering keeps generated SQL deterministic — helps when
        // diffing query plans, and lets equality checks on the request
        // skip reloads when only the iteration order changes.
        let orderedTypes = filters.types.sorted(by: { $0.rawValue < $1.rawValue })
        for type in orderedTypes {
            let (clause, clauseArgs) = Self.typeClause(for: type)
            parts.append(clause)
            args.append(contentsOf: clauseArgs)
        }

        let orderedApps = filters.apps.sorted()
        for app in orderedApps {
            parts.append("h.sourceApp = ?")
            args.append(app)
        }

        self.whereClause = parts.joined(separator: " AND ")
        self.arguments = args
    }

    private static func typeClause(for filter: CaptureFilter) -> (String, [String]) {
        switch filter {
        case .all:
            // `.all` is the absence of a type filter — including it as a
            // pill is meaningless, but if it sneaks in we treat it as a
            // no-op so the OR-joined expression stays valid.
            return ("1=1", [])
        case .annotated:
            return (
                """
                (
                    EXISTS (SELECT 1 FROM highlight_note hn WHERE hn.highlightId = h.id)
                    OR (h.userNote IS NOT NULL AND h.userNote != '')
                )
                """,
                []
            )
        case .links:
            return (
                """
                (h.contentType = 'url'
                 OR (h.highlightType = 'copy' AND (h.contentText LIKE 'http://%' OR h.contentText LIKE 'https://%')))
                """,
                []
            )
        case .videos:
            return ("(h.highlightType = 'file' AND h.contentType = 'video')", [])
        case .files:
            return ("(h.highlightType = 'file' AND (h.contentType IS NULL OR h.contentType != 'video'))", [])
        case .screenshots, .copies:
            return ("h.highlightType = ?", [filter.highlightType ?? ""])
        }
    }
}

extension Dictionary where Key == String, Value == Int {
    var totalBrowseHighlights: Int {
        reduce(into: 0) { total, entry in
            guard !entry.key.hasPrefix("_") else { return }
            total += entry.value
        }
    }
}
