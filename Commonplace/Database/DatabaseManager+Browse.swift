import Foundation
import GRDB

extension DatabaseManager {
    func browseHighlights(_ request: BrowseLoadRequest, offset: Int, limit: Int) -> [Highlight] {
        if let query = request.normalizedSearchText {
            return searchedBrowseHighlights(request, query: query, offset: offset, limit: limit)
        }
        if let tagId = request.selectedTagId {
            return highlightsForTagPaginated(tagId: tagId, offset: offset, limit: limit)
        }
        if request.selectedFilter.isAnnotatedFilter {
            return annotatedHighlightsPaginated(offset: offset, limit: limit)
        }
        if request.selectedFilter.isLinksFilter {
            return linkHighlightsPaginated(offset: offset, limit: limit)
        }
        if request.selectedFilter.isVideosFilter {
            return videoHighlightsPaginated(offset: offset, limit: limit)
        }
        if request.selectedFilter.isFilesExcludingVideos {
            return fileExcludingVideoPaginated(offset: offset, limit: limit)
        }
        if let app = request.selectedApp {
            return highlightsForApp(sourceApp: app, offset: offset, limit: limit)
        }
        if let type = request.selectedFilter.highlightType {
            return highlightsByTypePaginated(type: type, offset: offset, limit: limit)
        }
        return allHighlightsPaginated(offset: offset, limit: limit)
    }

    private func searchedBrowseHighlights(
        _ request: BrowseLoadRequest,
        query: String,
        offset: Int,
        limit: Int
    ) -> [Highlight] {
        guard let dbQueue else { return [] }

        let search = BrowseSearchQuery(query: query, request: request)
        let sql = """
            SELECT h.* FROM highlight h
            WHERE \(search.whereClauses.joined(separator: " AND "))
            ORDER BY h.timestamp DESC
            LIMIT \(max(0, limit)) OFFSET \(max(0, offset))
            """

        return (try? dbQueue.read { db in
            try Highlight.fetchAll(db, sql: sql, arguments: StatementArguments(search.arguments))
        }) ?? []
    }
}

private struct BrowseSearchQuery {
    let whereClauses: [String]
    let arguments: [String]

    init(query: String, request: BrowseLoadRequest) {
        var whereClauses: [String] = []
        var arguments: [String] = []

        if let tagId = request.selectedTagId {
            whereClauses.append("""
                EXISTS (
                    SELECT 1 FROM highlight_tag scope_ht
                    WHERE scope_ht.highlightId = h.id AND scope_ht.tagId = ?
                )
                """)
            arguments.append(tagId)
        }

        if request.selectedFilter.isAnnotatedFilter {
            whereClauses.append("""
                (
                    EXISTS (SELECT 1 FROM highlight_note scope_hn WHERE scope_hn.highlightId = h.id)
                    OR (h.userNote IS NOT NULL AND h.userNote != '')
                )
                """)
        } else if request.selectedFilter.isLinksFilter {
            whereClauses.append("""
                (h.contentType = 'url'
                 OR (h.highlightType = 'copy' AND (h.contentText LIKE 'http://%' OR h.contentText LIKE 'https://%')))
                """)
        } else if request.selectedFilter.isVideosFilter {
            whereClauses.append("h.highlightType = 'file' AND h.contentType = 'video'")
        } else if request.selectedFilter.isFilesExcludingVideos {
            whereClauses.append("h.highlightType = 'file' AND (h.contentType IS NULL OR h.contentType != 'video')")
        } else if let type = request.selectedFilter.highlightType {
            whereClauses.append("h.highlightType = ?")
            arguments.append(type)
        }

        if let app = request.selectedApp, !app.isEmpty {
            whereClauses.append("h.sourceApp = ?")
            arguments.append(app)
        }

        let tokens = query.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        if tokens.isEmpty {
            whereClauses.append("1 = 0")
        }

        for token in tokens {
            var patterns = ["%\(token)%"]
            if token.count >= 4 {
                for index in token.indices {
                    var variant = token
                    variant.remove(at: index)
                    patterns.append("%\(variant)%")
                }
            }

            var tokenClauses: [String] = []
            for _ in patterns {
                tokenClauses.append("""
                    (h.contentText LIKE ? COLLATE NOCASE
                     OR h.userNote LIKE ? COLLATE NOCASE
                     OR h.sourceApp LIKE ? COLLATE NOCASE
                     OR h.sourceUrl LIKE ? COLLATE NOCASE
                     OR h.windowTitle LIKE ? COLLATE NOCASE
                     OR h.bundleId LIKE ? COLLATE NOCASE
                     OR h.documentPath LIKE ? COLLATE NOCASE
                     OR EXISTS (SELECT 1 FROM screenshot s WHERE s.id = h.screenshotId AND s.ocrText LIKE ? COLLATE NOCASE)
                     OR EXISTS (SELECT 1 FROM highlight_note hn WHERE hn.highlightId = h.id AND hn.body LIKE ? COLLATE NOCASE)
                     OR EXISTS (SELECT 1 FROM file_record f WHERE f.id = h.fileId AND f.fileName LIKE ? COLLATE NOCASE)
                     OR EXISTS (SELECT 1 FROM highlight_tag ht JOIN tag t ON t.id = ht.tagId WHERE ht.highlightId = h.id AND t.name LIKE ? COLLATE NOCASE))
                    """)
            }

            whereClauses.append("(" + tokenClauses.joined(separator: " OR ") + ")")
            for pattern in patterns {
                arguments.append(contentsOf: Array(repeating: pattern, count: 11))
            }
        }

        self.whereClauses = whereClauses
        self.arguments = arguments
    }
}
