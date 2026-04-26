import Foundation
import GRDB

struct AppMigrations {
    static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_capture_tables") { db in
            try db.create(table: "screenshot") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .double).notNull()
                t.column("dayString", .text).notNull()
                t.column("filePath", .text).notNull()
                t.column("fileSize", .integer).notNull()
                t.column("displayId", .text).notNull().defaults(to: "1")
                t.column("ocrText", .text)
                t.column("captureType", .text).notNull().defaults(to: "full")
            }
            try db.create(index: "idx_screenshot_timestamp", on: "screenshot", columns: ["timestamp"])
            try db.create(index: "idx_screenshot_dayString", on: "screenshot", columns: ["dayString"])

            try db.create(table: "highlight") { t in
                t.primaryKey("id", .text)
                t.column("timestamp", .double).notNull()
                t.column("contentText", .text).notNull()
                t.column("sourceApp", .text)
                t.column("sourceUrl", .text)
                t.column("userNote", .text)
                t.column("highlightType", .text).notNull()
                t.column("screenshotId", .integer)
            }
            try db.create(index: "idx_highlight_timestamp", on: "highlight", columns: ["timestamp"])

            try db.create(table: "clipboard_entry") { t in
                t.primaryKey("id", .text)
                t.column("timestamp", .double).notNull()
                t.column("content", .text).notNull()
                t.column("sourceApp", .text)
            }
            try db.create(index: "idx_clipboard_entry_timestamp", on: "clipboard_entry", columns: ["timestamp"])
        }

        migrator.registerMigration("v2_metadata") { db in
            // Highlight metadata
            try db.alter(table: "highlight") { t in
                t.add(column: "windowTitle", .text)
                t.add(column: "bundleId", .text)
                t.add(column: "contentHash", .text)
                t.add(column: "documentPath", .text)
                t.add(column: "contentType", .text)
            }

            // Clipboard entry metadata
            try db.alter(table: "clipboard_entry") { t in
                t.add(column: "windowTitle", .text)
                t.add(column: "bundleId", .text)
                t.add(column: "sourceUrl", .text)
                t.add(column: "clipboardTypes", .text)
                t.add(column: "contentHash", .text)
                t.add(column: "documentPath", .text)
                t.add(column: "contentType", .text)
            }

            // Screenshot metadata
            try db.alter(table: "screenshot") { t in
                t.add(column: "windowTitle", .text)
                t.add(column: "bundleId", .text)
                t.add(column: "captureRect", .text)
                t.add(column: "scaleFactor", .double)
            }
        }

        migrator.registerMigration("v3_highlight_notes") { db in
            try db.create(table: "highlight_note") { t in
                t.primaryKey("id", .text)
                t.column("highlightId", .text).notNull()
                    .references("highlight", onDelete: .cascade)
                t.column("body", .text).notNull()
                t.column("createdAt", .double).notNull()
            }
            try db.create(index: "idx_highlight_note_highlightId", on: "highlight_note", columns: ["highlightId"])

            // Migrate existing non-empty userNote values into the new table
            try db.execute(sql: """
                INSERT INTO highlight_note (id, highlightId, body, createdAt)
                SELECT lower(hex(randomblob(16))), id, userNote, timestamp
                FROM highlight
                WHERE userNote IS NOT NULL AND userNote != ''
                """)
        }

        migrator.registerMigration("v4_pattern_indexes") { db in
            try db.create(index: "idx_highlight_sourceApp", on: "highlight", columns: ["sourceApp"])
            try db.create(index: "idx_highlight_sourceApp_timestamp", on: "highlight", columns: ["sourceApp", "timestamp"])
            try db.create(index: "idx_highlight_bundleId", on: "highlight", columns: ["bundleId"])
        }

        migrator.registerMigration("v5_recording") { db in
            try db.create(table: "recording") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .double).notNull()
                t.column("dayString", .text).notNull()
                t.column("filePath", .text).notNull()
                t.column("thumbnailPath", .text).notNull()
                t.column("fileSize", .integer).notNull()
                t.column("duration", .double).notNull()
                t.column("displayId", .text).notNull().defaults(to: "1")
                t.column("captureType", .text).notNull().defaults(to: "full")
                t.column("hasAudio", .boolean).notNull().defaults(to: false)
                t.column("windowTitle", .text)
                t.column("bundleId", .text)
            }
            try db.create(index: "idx_recording_timestamp", on: "recording", columns: ["timestamp"])
            try db.create(index: "idx_recording_dayString", on: "recording", columns: ["dayString"])

            try db.alter(table: "highlight") { t in
                t.add(column: "recordingId", .integer)
            }
        }

        migrator.registerMigration("v6_enriched_metadata") { db in
            // Environment metadata on highlights
            try db.alter(table: "highlight") { t in
                t.add(column: "displayName", .text)
                t.add(column: "displayResolution", .text)
                t.add(column: "appearanceMode", .text)
                t.add(column: "wifiNetwork", .text)
            }

            // Image dimensions on screenshots
            try db.alter(table: "screenshot") { t in
                t.add(column: "imageWidth", .integer)
                t.add(column: "imageHeight", .integer)
            }

            // Smart folders
            try db.create(table: "saved_filter") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("predicateJSON", .text).notNull()
                t.column("createdAt", .double).notNull()
                t.column("icon", .text).notNull().defaults(to: "folder")
            }
        }

        migrator.registerMigration("v7_page_visits") { db in
            try db.create(table: "page_visit") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("url", .text).notNull()
                t.column("title", .text)
                t.column("domain", .text)
                t.column("sourceApp", .text)
                t.column("bundleId", .text)
                t.column("startedAt", .double).notNull()
                t.column("endedAt", .double)
                t.column("duration", .double)
                t.column("isBookmarked", .boolean).notNull().defaults(to: false)
                t.column("captureCount", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "idx_page_visit_url", on: "page_visit", columns: ["url"])
            try db.create(index: "idx_page_visit_startedAt", on: "page_visit", columns: ["startedAt"])
            try db.create(index: "idx_page_visit_domain", on: "page_visit", columns: ["domain"])
        }
        migrator.registerMigration("v8_file_monitoring") { db in
            try db.create(table: "file_record") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .double).notNull()
                t.column("dayString", .text).notNull()
                t.column("filePath", .text).notNull()
                t.column("fileName", .text).notNull()
                t.column("fileSize", .integer).notNull()
                t.column("uti", .text)
                t.column("contentType", .text)
                t.column("thumbnailPath", .text)
                t.column("sourceFolder", .text).notNull()
                t.column("creationDate", .double)
                t.column("fileExtension", .text)
            }
            try db.create(index: "idx_file_record_timestamp", on: "file_record", columns: ["timestamp"])
            try db.create(index: "idx_file_record_dayString", on: "file_record", columns: ["dayString"])
            try db.create(index: "idx_file_record_filePath", on: "file_record", columns: ["filePath"])

            try db.alter(table: "highlight") { t in
                t.add(column: "fileId", .integer)
            }
        }

        migrator.registerMigration("v9_tags") { db in
            try db.create(table: "tag", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().unique()
                t.column("color", .text)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }

            try db.create(table: "highlight_tag", ifNotExists: true) { t in
                t.column("tagId", .text).notNull()
                    .references("tag", onDelete: .cascade)
                t.column("highlightId", .text).notNull()
                    .references("highlight", onDelete: .cascade)
                t.column("createdAt", .double).notNull()
                t.primaryKey(["tagId", "highlightId"])
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_highlight_tag_highlightId ON highlight_tag(highlightId)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_highlight_tag_tagId ON highlight_tag(tagId)")
        }

        migrator.registerMigration("v10_file_page_count") { db in
            try db.alter(table: "file_record") { t in
                t.add(column: "pageCount", .integer)
            }
        }

        migrator.registerMigration("v11_published_collections") { db in
            try db.alter(table: "tag") { t in
                t.add(column: "isPublished", .boolean).defaults(to: false)
            }
        }

        migrator.registerMigration("v12_link_preview") { db in
            try db.create(table: "link_preview") { t in
                t.primaryKey("url", .text)
                t.column("title", .text)
                t.column("siteName", .text)
                t.column("imagePath", .text)
                t.column("faviconPath", .text)
                t.column("fetchedAt", .double).notNull()
                t.column("fetchError", .text)
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_link_preview_fetchedAt ON link_preview(fetchedAt)")
        }

        migrator.registerMigration("v13_collections") { db in
            // Step 1 — Clipboard dedup cleanup pass.
            // Collapse rapid-fire duplicate clipboard captures where NSPasteboard.changeCount
            // fired multiple times for a single copy operation. Cluster rows with the same
            // contentHash where consecutive timestamps are within 60s; keep the earliest row
            // as the "keeper" and repoint downstream rows (highlight_note, highlight_tag) to it
            // before deleting the dupes. Rows more than 60s apart are treated as legitimate
            // separate captures and left alone.
            let clusterWindow: Double = 60.0

            // Helper: find duplicate clusters in a table and return mapping of
            // dupeId -> keeperId for each row that should be collapsed.
            func dedupMapping(
                table: String,
                typeFilter: String?
            ) throws -> [(dupeId: String, keeperId: String)] {
                var where_ = "contentHash IS NOT NULL AND contentHash != ''"
                if let tf = typeFilter {
                    where_ += " AND highlightType = '\(tf)'"
                }
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, contentHash, timestamp FROM \(table)
                    WHERE \(where_)
                    ORDER BY contentHash, timestamp ASC
                    """)

                var mapping: [(dupeId: String, keeperId: String)] = []
                var currentHash: String? = nil
                var keeperId: String? = nil
                var lastTimestamp: Double = 0

                for row in rows {
                    let id: String = row["id"]
                    let hash: String = row["contentHash"]
                    let ts: Double = row["timestamp"]

                    if hash != currentHash {
                        // New hash group — restart cluster tracking.
                        currentHash = hash
                        keeperId = id
                        lastTimestamp = ts
                        continue
                    }

                    if ts - lastTimestamp <= clusterWindow {
                        // Part of the same burst cluster — this row is a dupe of the keeper.
                        if let k = keeperId {
                            mapping.append((dupeId: id, keeperId: k))
                        }
                        lastTimestamp = ts
                    } else {
                        // Gap too wide — start a new cluster with this row as the keeper.
                        keeperId = id
                        lastTimestamp = ts
                    }
                }
                return mapping
            }

            // --- highlight table (only type == 'copy') ---
            let highlightDupes = try dedupMapping(table: "highlight", typeFilter: "copy")
            var highlightClusterCount = 0
            var lastKeeper = ""
            for (dupeId, keeperId) in highlightDupes {
                if keeperId != lastKeeper {
                    highlightClusterCount += 1
                    lastKeeper = keeperId
                }
                // Repoint any highlight_note rows pointing at the dupe to the keeper.
                try db.execute(
                    sql: "UPDATE highlight_note SET highlightId = ? WHERE highlightId = ?",
                    arguments: [keeperId, dupeId]
                )
                // Repoint any highlight_tag rows (will become highlight_collection later).
                // Use INSERT OR IGNORE semantics to avoid PK conflicts if keeper already has the tag.
                try db.execute(sql: """
                    INSERT OR IGNORE INTO highlight_tag (tagId, highlightId, createdAt)
                    SELECT tagId, ?, createdAt FROM highlight_tag WHERE highlightId = ?
                    """, arguments: [keeperId, dupeId])
                try db.execute(
                    sql: "DELETE FROM highlight_tag WHERE highlightId = ?",
                    arguments: [dupeId]
                )
                // Finally delete the dupe highlight row.
                try db.execute(
                    sql: "DELETE FROM highlight WHERE id = ?",
                    arguments: [dupeId]
                )
            }

            // --- clipboard_entry table (all rows have copy semantics) ---
            let clipDupes = try dedupMapping(table: "clipboard_entry", typeFilter: nil)
            var clipClusterCount = 0
            lastKeeper = ""
            for (dupeId, keeperId) in clipDupes {
                if keeperId != lastKeeper {
                    clipClusterCount += 1
                    lastKeeper = keeperId
                }
                try db.execute(
                    sql: "DELETE FROM clipboard_entry WHERE id = ?",
                    arguments: [dupeId]
                )
            }

            CaptureLog.info("v13 dedup cleanup: collapsed \(highlightDupes.count) highlight rows across \(highlightClusterCount) clusters, \(clipDupes.count) clipboard_entry rows across \(clipClusterCount) clusters")

            // Step 2 — Add highlight_note.updatedAt, backfill from createdAt.
            try db.alter(table: "highlight_note") { t in
                t.add(column: "updatedAt", .double)
            }
            try db.execute(sql: "UPDATE highlight_note SET updatedAt = createdAt WHERE updatedAt IS NULL")

            // Step 3 — Create collection + highlight_collection tables.
            try db.create(table: "collection") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            try db.execute(sql: "CREATE UNIQUE INDEX idx_collection_title_lower ON collection(LOWER(title))")

            try db.create(table: "highlight_collection") { t in
                t.column("highlightId", .text).notNull()
                    .references("highlight", onDelete: .cascade)
                t.column("collectionId", .text).notNull()
                    .references("collection", onDelete: .cascade)
                t.column("addedAt", .double).notNull()
                t.primaryKey(["highlightId", "collectionId"])
            }
            try db.execute(sql: "CREATE INDEX idx_highlight_collection_highlightId ON highlight_collection(highlightId)")
            try db.execute(sql: "CREATE INDEX idx_highlight_collection_collectionId ON highlight_collection(collectionId)")

            // Step 4 — Tags → collections data migration.
            // Only migrate tags that have ≥1 highlight_tag membership. Orphan tags
            // are dropped because empty collections do not exist in V1.
            let tagRows = try Row.fetchAll(db, sql: """
                SELECT t.id, t.name, t.createdAt, t.updatedAt
                FROM tag t
                WHERE EXISTS (SELECT 1 FROM highlight_tag ht WHERE ht.tagId = t.id)
                ORDER BY t.name
                """)
            var tagIdToCollectionId: [String: String] = [:]
            for row in tagRows {
                let tagId: String = row["id"]
                let tagName: String = row["name"]
                let tCreatedAt: Double = row["createdAt"]
                let tUpdatedAt: Double = row["updatedAt"]

                // Case-insensitive dedup against any pre-existing collection (shouldn't
                // exist on first migration, but safe defensively).
                if let existingId = try String.fetchOne(db,
                    sql: "SELECT id FROM collection WHERE LOWER(title) = LOWER(?)",
                    arguments: [tagName]
                ) {
                    tagIdToCollectionId[tagId] = existingId
                    continue
                }

                let newId = UUID().uuidString
                try db.execute(sql: """
                    INSERT INTO collection (id, title, description, createdAt, updatedAt, sortOrder)
                    VALUES (?, ?, NULL, ?, ?, 0)
                    """, arguments: [newId, tagName, tCreatedAt, tUpdatedAt])
                tagIdToCollectionId[tagId] = newId
            }

            // Migrate highlight_tag rows → highlight_collection rows.
            let htRows = try Row.fetchAll(db, sql: """
                SELECT tagId, highlightId, createdAt FROM highlight_tag
                """)
            var migratedMemberships = 0
            for row in htRows {
                let tagId: String = row["tagId"]
                let highlightId: String = row["highlightId"]
                let addedAt: Double = row["createdAt"]
                guard let collectionId = tagIdToCollectionId[tagId] else { continue }
                try db.execute(sql: """
                    INSERT OR IGNORE INTO highlight_collection (highlightId, collectionId, addedAt)
                    VALUES (?, ?, ?)
                    """, arguments: [highlightId, collectionId, addedAt])
                migratedMemberships += 1
            }
            CaptureLog.info("v13 tag→collection migration: \(tagRows.count) collections, \(migratedMemberships) memberships")

            // Step 5 — Rewrite saved_filter.predicateJSON: any .tag field becomes .collection.
            let savedFilterRows = try Row.fetchAll(db, sql: "SELECT id, predicateJSON FROM saved_filter")
            for row in savedFilterRows {
                let id: String = row["id"]
                let json: String = row["predicateJSON"]
                // Simple string replace is safe here — the predicate JSON uses the raw
                // enum value "tag" / "collection" as-is and there are no collisions with
                // other fields that contain the substring "tag".
                if json.contains("\"field\":\"tag\"") {
                    let rewritten = json.replacingOccurrences(of: "\"field\":\"tag\"", with: "\"field\":\"collection\"")
                    try db.execute(
                        sql: "UPDATE saved_filter SET predicateJSON = ? WHERE id = ?",
                        arguments: [rewritten, id]
                    )
                }
            }
        }

        migrator.registerMigration("v14_file_record_original_url") { db in
            // Source URL for files that came from a copied link, so
            // URLFileDownloader can dedup re-copies of the same URL.
            try db.alter(table: "file_record") { t in
                t.add(column: "originalUrl", .text)
            }
            try db.create(
                index: "idx_file_record_originalUrl",
                on: "file_record",
                columns: ["originalUrl"],
                ifNotExists: true
            )
        }

        migrator.registerMigration("v15_tag_emoji") { db in
            try db.alter(table: "tag") { t in
                t.add(column: "emoji", .text)
            }
        }

        migrator.registerMigration("v16_stacks") { db in
            try db.create(table: "stack", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("name", .text)
                t.column("description", .text)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
                t.column("isPinned", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "highlight_stack", ifNotExists: true) { t in
                t.column("stackId", .text).notNull()
                    .references("stack", onDelete: .cascade)
                t.column("highlightId", .text).notNull()
                    .references("highlight", onDelete: .cascade)
                t.column("addedAt", .double).notNull()
                t.primaryKey(["stackId", "highlightId"])
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_highlight_stack_highlightId ON highlight_stack(highlightId)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_highlight_stack_stackId ON highlight_stack(stackId)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_stack_updatedAt ON stack(updatedAt)")
            // Partial unique index: enforce the "only one pinned stack" invariant at the DB level
            try db.execute(sql: "CREATE UNIQUE INDEX IF NOT EXISTS idx_stack_single_pin ON stack(isPinned) WHERE isPinned = 1")
        }

        migrator.registerMigration("v17_note_video_timestamp") { db in
            try db.alter(table: "highlight_note") { t in
                t.add(column: "timestampSeconds", .double)
            }
        }

        migrator.registerMigration("v18_image_dimensions") { db in
            // Store intrinsic image dimensions on file_record (for image/video
            // thumbnails) and link_preview (hero images) so masonry cards can
            // reserve aspect-ratio space before the bitmap loads. Without
            // these, cards measure at a fallback ratio and resize when the
            // image arrives, cascading into masonry overlaps.
            try db.alter(table: "file_record") { t in
                t.add(column: "imageWidth", .integer)
                t.add(column: "imageHeight", .integer)
            }
            try db.alter(table: "link_preview") { t in
                t.add(column: "imageWidth", .integer)
                t.add(column: "imageHeight", .integer)
            }
        }

        migrator.registerMigration("v19_stack_item_position") { db in
            // User-driven ordering of items within a stack. Default ranks
            // match the historical "newest first" behavior, so nothing
            // visibly changes at first launch; drag-to-reorder overwrites
            // these values as the user arranges cells.
            try db.alter(table: "highlight_stack") { t in
                t.add(column: "position", .integer).notNull().defaults(to: 0)
            }
            try db.execute(sql: """
                UPDATE highlight_stack
                SET position = rowid_rank.rank
                FROM (
                    SELECT rowid,
                           (ROW_NUMBER() OVER (
                               PARTITION BY stackId
                               ORDER BY addedAt DESC
                           )) - 1 AS rank
                    FROM highlight_stack
                ) AS rowid_rank
                WHERE highlight_stack.rowid = rowid_rank.rowid
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_highlight_stack_stack_position
                ON highlight_stack(stackId, position)
                """)
        }

        migrator.registerMigration("v20_link_preview_og") { db in
            // Extended Open Graph fields beyond what `LPMetadataProvider`
            // exposes — description, author, publish date, and og:type —
            // scraped from the page's <head> in a supplementary fetch.
            try db.alter(table: "link_preview") { t in
                t.add(column: "ogDescription", .text)
                t.add(column: "ogAuthor", .text)
                t.add(column: "ogPublishedAt", .double)
                t.add(column: "ogType", .text)
            }
        }

        migrator.registerMigration("v21_source_context") { db in
            // JSON-encoded [SourceContextEntry] produced by per-app enrichers
            // at capture time (chat name, permalink, etc.). Nullable so
            // existing rows render unchanged; backfill handled separately.
            try db.alter(table: "highlight") { t in
                t.add(column: "sourceContext", .text)
            }
        }

        migrator.registerMigration("v22_capture_event_links") { db in
            // Bytes-level dedup key for files: SHA-256 of the file contents,
            // computed at ingest. Nullable so pre-existing rows simply don't
            // participate (a backfill can land later). The index enables
            // fileRecord(byHash:) lookups on a hot path at capture time.
            try db.alter(table: "file_record") { t in
                t.add(column: "fileHash", .text)
            }
            try db.create(
                index: "idx_file_record_fileHash",
                on: "file_record",
                columns: ["fileHash"],
                ifNotExists: true
            )

            // Sibling resolution in CardDetailView's "Captured N times"
            // section groups non-file highlights by contentHash. Without an
            // index, each detail-view open triggers a full table scan on a
            // growing archive.
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_highlight_contentHash
                ON highlight(contentHash)
                """)
        }

        migrator.registerMigration("v23_stack_stack") { db in
            // Nesting: a stack may contain other stacks. Kept separate from
            // `highlight_stack` so queries against either junction stay simple
            // and each has its own `position` column — StackDetailView renders
            // substacks and highlights in two independent sections. No cycle
            // check; traversals (export, counts) carry a visited set instead.
            try db.create(table: "stack_stack", ifNotExists: true) { t in
                t.column("parentStackId", .text).notNull()
                    .references("stack", onDelete: .cascade)
                t.column("childStackId", .text).notNull()
                    .references("stack", onDelete: .cascade)
                t.column("addedAt", .double).notNull()
                t.column("position", .integer).notNull().defaults(to: 0)
                t.primaryKey(["parentStackId", "childStackId"])
            }
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_stack_stack_parent_position
                ON stack_stack(parentStackId, position)
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_stack_stack_child
                ON stack_stack(childStackId)
                """)
        }

        // FTS5 full-text search. Pre-FTS, search was a 7-column LIKE
        // `%query%` with 4 EXISTS subqueries — a full table scan per
        // keystroke that fell over at archive sizes of more than a few
        // thousand rows. This migration replaces that with an FTS5
        // virtual table indexed on a denormalized `highlight_search`
        // mirror (contentText + userNote + sourceApp + sourceUrl +
        // windowTitle + documentPath + bundleId + ocrText + aggregated
        // note bodies + filename).
        //
        // Triggers keep the mirror in sync with every source table so
        // the app code doesn't need to manage it. The FTS5 side uses
        // `content='highlight_search'` + `content_rowid='id'` —
        // external-content form — so the index is built from the
        // mirror automatically.
        migrator.registerMigration("v24_search_fts") { db in
            // Denormalized mirror, one row per highlight, holding the
            // concatenated searchable text. `id INTEGER PRIMARY KEY
            // AUTOINCREMENT` gives us the integer rowid FTS5 needs —
            // since `highlight.id` is TEXT we can't use it directly.
            try db.execute(sql: """
                CREATE TABLE highlight_search (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    highlightId TEXT UNIQUE NOT NULL,
                    searchText TEXT NOT NULL DEFAULT ''
                )
                """)
            try db.execute(sql: """
                CREATE INDEX idx_highlight_search_highlightId
                ON highlight_search(highlightId)
                """)

            // FTS5 virtual table. `unicode61 remove_diacritics 2`:
            // case-insensitive by default, folds accents so "cafe"
            // matches "café". `content='highlight_search'` +
            // `content_rowid='id'` means the FTS index mirrors the
            // mirror — `snippet()` and column retrieval work out of
            // the box, and we don't pay double storage.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE highlight_search_fts USING fts5(
                    searchText,
                    content='highlight_search',
                    content_rowid='id',
                    tokenize='unicode61 remove_diacritics 2'
                )
                """)

            // Keep the FTS index in lockstep with `highlight_search`
            // inserts / updates / deletes. The `delete` command with
            // the old rowid is the canonical way to remove an entry
            // from an external-content FTS5 table.
            try db.execute(sql: """
                CREATE TRIGGER highlight_search_fts_ai AFTER INSERT ON highlight_search BEGIN
                    INSERT INTO highlight_search_fts(rowid, searchText)
                    VALUES (new.id, new.searchText);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER highlight_search_fts_ad AFTER DELETE ON highlight_search BEGIN
                    INSERT INTO highlight_search_fts(highlight_search_fts, rowid, searchText)
                    VALUES ('delete', old.id, old.searchText);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER highlight_search_fts_au AFTER UPDATE ON highlight_search BEGIN
                    INSERT INTO highlight_search_fts(highlight_search_fts, rowid, searchText)
                    VALUES ('delete', old.id, old.searchText);
                    INSERT INTO highlight_search_fts(rowid, searchText)
                    VALUES (new.id, new.searchText);
                END
                """)

            // Population triggers — when a highlight or any of its
            // related tables change, rewrite the highlight_search row
            // for that highlight id. The concat expression is verbose
            // but SQLite can't parameterize it via a view; inlined in
            // each trigger.
            //
            // Helper SQL fragment (duplicated below for each trigger):
            //   searchText for `h`:
            //   contentText || userNote || sourceApp || sourceUrl ||
            //   windowTitle || documentPath || bundleId ||
            //   screenshot.ocrText (where id = h.screenshotId) ||
            //   GROUP_CONCAT(highlight_note.body where highlightId = h.id) ||
            //   file_record.fileName (where id = h.fileId)

            // Highlight INSERT: insert a fresh mirror row.
            try db.execute(sql: """
                CREATE TRIGGER highlight_search_ai AFTER INSERT ON highlight BEGIN
                    INSERT INTO highlight_search (highlightId, searchText)
                    VALUES (
                        new.id,
                        COALESCE(new.contentText, '') || ' ' ||
                        COALESCE(new.userNote, '') || ' ' ||
                        COALESCE(new.sourceApp, '') || ' ' ||
                        COALESCE(new.sourceUrl, '') || ' ' ||
                        COALESCE(new.windowTitle, '') || ' ' ||
                        COALESCE(new.documentPath, '') || ' ' ||
                        COALESCE(new.bundleId, '') || ' ' ||
                        COALESCE((SELECT ocrText FROM screenshot WHERE id = new.screenshotId), '') || ' ' ||
                        COALESCE((SELECT GROUP_CONCAT(body, ' ') FROM highlight_note WHERE highlightId = new.id), '') || ' ' ||
                        COALESCE((SELECT fileName FROM file_record WHERE id = new.fileId), '')
                    );
                END
                """)

            // Highlight UPDATE: rebuild the searchText for this row.
            try db.execute(sql: """
                CREATE TRIGGER highlight_search_au AFTER UPDATE ON highlight BEGIN
                    UPDATE highlight_search SET searchText =
                        COALESCE(new.contentText, '') || ' ' ||
                        COALESCE(new.userNote, '') || ' ' ||
                        COALESCE(new.sourceApp, '') || ' ' ||
                        COALESCE(new.sourceUrl, '') || ' ' ||
                        COALESCE(new.windowTitle, '') || ' ' ||
                        COALESCE(new.documentPath, '') || ' ' ||
                        COALESCE(new.bundleId, '') || ' ' ||
                        COALESCE((SELECT ocrText FROM screenshot WHERE id = new.screenshotId), '') || ' ' ||
                        COALESCE((SELECT GROUP_CONCAT(body, ' ') FROM highlight_note WHERE highlightId = new.id), '') || ' ' ||
                        COALESCE((SELECT fileName FROM file_record WHERE id = new.fileId), '')
                    WHERE highlightId = new.id;
                END
                """)

            // Highlight DELETE: drop the mirror row (FTS5 delete fires
            // via the highlight_search_fts_ad trigger).
            try db.execute(sql: """
                CREATE TRIGGER highlight_search_ad AFTER DELETE ON highlight BEGIN
                    DELETE FROM highlight_search WHERE highlightId = old.id;
                END
                """)

            // highlight_note changes → refresh the parent's searchText.
            // Uses the same big concat, re-pulling from highlight for
            // the base columns since we only have note data in `new`.
            try db.execute(sql: """
                CREATE TRIGGER highlight_note_search_ai AFTER INSERT ON highlight_note BEGIN
                    UPDATE highlight_search SET searchText = (
                        SELECT
                            COALESCE(h.contentText, '') || ' ' ||
                            COALESCE(h.userNote, '') || ' ' ||
                            COALESCE(h.sourceApp, '') || ' ' ||
                            COALESCE(h.sourceUrl, '') || ' ' ||
                            COALESCE(h.windowTitle, '') || ' ' ||
                            COALESCE(h.documentPath, '') || ' ' ||
                            COALESCE(h.bundleId, '') || ' ' ||
                            COALESCE((SELECT ocrText FROM screenshot WHERE id = h.screenshotId), '') || ' ' ||
                            COALESCE((SELECT GROUP_CONCAT(body, ' ') FROM highlight_note WHERE highlightId = h.id), '') || ' ' ||
                            COALESCE((SELECT fileName FROM file_record WHERE id = h.fileId), '')
                        FROM highlight h WHERE h.id = new.highlightId
                    ) WHERE highlightId = new.highlightId;
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER highlight_note_search_au AFTER UPDATE ON highlight_note BEGIN
                    UPDATE highlight_search SET searchText = (
                        SELECT
                            COALESCE(h.contentText, '') || ' ' ||
                            COALESCE(h.userNote, '') || ' ' ||
                            COALESCE(h.sourceApp, '') || ' ' ||
                            COALESCE(h.sourceUrl, '') || ' ' ||
                            COALESCE(h.windowTitle, '') || ' ' ||
                            COALESCE(h.documentPath, '') || ' ' ||
                            COALESCE(h.bundleId, '') || ' ' ||
                            COALESCE((SELECT ocrText FROM screenshot WHERE id = h.screenshotId), '') || ' ' ||
                            COALESCE((SELECT GROUP_CONCAT(body, ' ') FROM highlight_note WHERE highlightId = h.id), '') || ' ' ||
                            COALESCE((SELECT fileName FROM file_record WHERE id = h.fileId), '')
                        FROM highlight h WHERE h.id = new.highlightId
                    ) WHERE highlightId = new.highlightId;
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER highlight_note_search_ad AFTER DELETE ON highlight_note BEGIN
                    UPDATE highlight_search SET searchText = (
                        SELECT
                            COALESCE(h.contentText, '') || ' ' ||
                            COALESCE(h.userNote, '') || ' ' ||
                            COALESCE(h.sourceApp, '') || ' ' ||
                            COALESCE(h.sourceUrl, '') || ' ' ||
                            COALESCE(h.windowTitle, '') || ' ' ||
                            COALESCE(h.documentPath, '') || ' ' ||
                            COALESCE(h.bundleId, '') || ' ' ||
                            COALESCE((SELECT ocrText FROM screenshot WHERE id = h.screenshotId), '') || ' ' ||
                            COALESCE((SELECT GROUP_CONCAT(body, ' ') FROM highlight_note WHERE highlightId = h.id), '') || ' ' ||
                            COALESCE((SELECT fileName FROM file_record WHERE id = h.fileId), '')
                        FROM highlight h WHERE h.id = old.highlightId
                    ) WHERE highlightId = old.highlightId;
                END
                """)

            // Screenshot.ocrText updates (async OCR completion after
            // the highlight already exists): refresh every highlight
            // that points at this screenshot.
            try db.execute(sql: """
                CREATE TRIGGER screenshot_ocr_search_au AFTER UPDATE OF ocrText ON screenshot BEGIN
                    UPDATE highlight_search SET searchText = (
                        SELECT
                            COALESCE(h.contentText, '') || ' ' ||
                            COALESCE(h.userNote, '') || ' ' ||
                            COALESCE(h.sourceApp, '') || ' ' ||
                            COALESCE(h.sourceUrl, '') || ' ' ||
                            COALESCE(h.windowTitle, '') || ' ' ||
                            COALESCE(h.documentPath, '') || ' ' ||
                            COALESCE(h.bundleId, '') || ' ' ||
                            COALESCE(new.ocrText, '') || ' ' ||
                            COALESCE((SELECT GROUP_CONCAT(body, ' ') FROM highlight_note WHERE highlightId = h.id), '') || ' ' ||
                            COALESCE((SELECT fileName FROM file_record WHERE id = h.fileId), '')
                        FROM highlight h WHERE h.id = highlight_search.highlightId
                    )
                    WHERE highlightId IN (SELECT id FROM highlight WHERE screenshotId = new.id);
                END
                """)

            // file_record.fileName updates (rare but possible on
            // rename): refresh the owning highlight's searchText.
            try db.execute(sql: """
                CREATE TRIGGER file_record_name_search_au AFTER UPDATE OF fileName ON file_record BEGIN
                    UPDATE highlight_search SET searchText = (
                        SELECT
                            COALESCE(h.contentText, '') || ' ' ||
                            COALESCE(h.userNote, '') || ' ' ||
                            COALESCE(h.sourceApp, '') || ' ' ||
                            COALESCE(h.sourceUrl, '') || ' ' ||
                            COALESCE(h.windowTitle, '') || ' ' ||
                            COALESCE(h.documentPath, '') || ' ' ||
                            COALESCE(h.bundleId, '') || ' ' ||
                            COALESCE((SELECT ocrText FROM screenshot WHERE id = h.screenshotId), '') || ' ' ||
                            COALESCE((SELECT GROUP_CONCAT(body, ' ') FROM highlight_note WHERE highlightId = h.id), '') || ' ' ||
                            COALESCE(new.fileName, '')
                        FROM highlight h WHERE h.id = highlight_search.highlightId
                    )
                    WHERE highlightId IN (SELECT id FROM highlight WHERE fileId = new.id);
                END
                """)

            // Backfill: one INSERT per existing highlight builds its
            // initial mirror row, and the `_ai` trigger on
            // highlight_search cascades into the FTS index. Runs once
            // at migration time.
            let backfillStart = Date()
            try db.execute(sql: """
                INSERT INTO highlight_search (highlightId, searchText)
                SELECT h.id,
                    COALESCE(h.contentText, '') || ' ' ||
                    COALESCE(h.userNote, '') || ' ' ||
                    COALESCE(h.sourceApp, '') || ' ' ||
                    COALESCE(h.sourceUrl, '') || ' ' ||
                    COALESCE(h.windowTitle, '') || ' ' ||
                    COALESCE(h.documentPath, '') || ' ' ||
                    COALESCE(h.bundleId, '') || ' ' ||
                    COALESCE((SELECT ocrText FROM screenshot WHERE id = h.screenshotId), '') || ' ' ||
                    COALESCE((SELECT GROUP_CONCAT(body, ' ') FROM highlight_note WHERE highlightId = h.id), '') || ' ' ||
                    COALESCE((SELECT fileName FROM file_record WHERE id = h.fileId), '')
                FROM highlight h
                """)
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM highlight_search") ?? 0
            let elapsed = Int(Date().timeIntervalSince(backfillStart) * 1000)
            CaptureLog.info("[migration v24] FTS5 backfill: \(count) highlights indexed in \(elapsed)ms")
        }

        // Per-column FTS5 — split the v24 monolithic `searchText`
        // into four columns so search results can show WHICH field
        // matched (badge + snippet). Enables FTS5's `snippet()` to
        // return a context window pointing at the match instead of
        // the whole haystack, which the sidebar UI uses to render
        // tight, interpretable results.
        migrator.registerMigration("v25_search_fts_split") { db in
            // Start fresh — v24 triggers + table go away and the
            // four-column form takes over. Order matters: drop FTS
            // first so its sync triggers are removed, then the mirror
            // + its triggers.
            try db.execute(sql: "DROP TABLE IF EXISTS highlight_search_fts")
            try db.execute(sql: "DROP TRIGGER IF EXISTS highlight_search_fts_ai")
            try db.execute(sql: "DROP TRIGGER IF EXISTS highlight_search_fts_ad")
            try db.execute(sql: "DROP TRIGGER IF EXISTS highlight_search_fts_au")
            try db.execute(sql: "DROP TRIGGER IF EXISTS highlight_search_ai")
            try db.execute(sql: "DROP TRIGGER IF EXISTS highlight_search_au")
            try db.execute(sql: "DROP TRIGGER IF EXISTS highlight_search_ad")
            try db.execute(sql: "DROP TRIGGER IF EXISTS highlight_note_search_ai")
            try db.execute(sql: "DROP TRIGGER IF EXISTS highlight_note_search_au")
            try db.execute(sql: "DROP TRIGGER IF EXISTS highlight_note_search_ad")
            try db.execute(sql: "DROP TRIGGER IF EXISTS screenshot_ocr_search_au")
            try db.execute(sql: "DROP TRIGGER IF EXISTS file_record_name_search_au")
            try db.execute(sql: "DROP TABLE IF EXISTS highlight_search")

            // New mirror: four text columns + id mapping. `id INTEGER
            // PRIMARY KEY AUTOINCREMENT` is the rowid FTS5 uses
            // (matching `content_rowid='id'` below).
            try db.execute(sql: """
                CREATE TABLE highlight_search (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    highlightId TEXT UNIQUE NOT NULL,
                    title TEXT NOT NULL DEFAULT '',
                    annotation TEXT NOT NULL DEFAULT '',
                    ocr_text TEXT NOT NULL DEFAULT '',
                    metadata TEXT NOT NULL DEFAULT ''
                )
                """)
            try db.execute(sql: """
                CREATE INDEX idx_highlight_search_highlightId
                ON highlight_search(highlightId)
                """)

            // Per-column FTS5 virtual table. Query with MATCH returns
            // every row hit; `snippet(<tbl>, <col>, ..., 12)` can
            // target any column to pull a ~12-token window around
            // the match. BM25 ranks relevance.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE highlight_search_fts USING fts5(
                    title,
                    annotation,
                    ocr_text,
                    metadata,
                    content='highlight_search',
                    content_rowid='id',
                    tokenize='unicode61 remove_diacritics 2'
                )
                """)

            // FTS5 sync triggers — mirror `highlight_search` changes
            // into the index. Canonical external-content form.
            try db.execute(sql: """
                CREATE TRIGGER highlight_search_fts_ai AFTER INSERT ON highlight_search BEGIN
                    INSERT INTO highlight_search_fts(rowid, title, annotation, ocr_text, metadata)
                    VALUES (new.id, new.title, new.annotation, new.ocr_text, new.metadata);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER highlight_search_fts_ad AFTER DELETE ON highlight_search BEGIN
                    INSERT INTO highlight_search_fts(highlight_search_fts, rowid, title, annotation, ocr_text, metadata)
                    VALUES ('delete', old.id, old.title, old.annotation, old.ocr_text, old.metadata);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER highlight_search_fts_au AFTER UPDATE ON highlight_search BEGIN
                    INSERT INTO highlight_search_fts(highlight_search_fts, rowid, title, annotation, ocr_text, metadata)
                    VALUES ('delete', old.id, old.title, old.annotation, old.ocr_text, old.metadata);
                    INSERT INTO highlight_search_fts(rowid, title, annotation, ocr_text, metadata)
                    VALUES (new.id, new.title, new.annotation, new.ocr_text, new.metadata);
                END
                """)

            // Population triggers — each source table mutation writes
            // into the corresponding column(s) of `highlight_search`.
            //
            // title: contentText for text-type rows, filename for
            //        file-type rows (file_record.fileName).
            // annotation: userNote + all highlight_note bodies.
            // ocr_text: screenshot.ocrText.
            // metadata: sourceApp, sourceUrl, windowTitle concat.

            try db.execute(sql: """
                CREATE TRIGGER highlight_search_ai AFTER INSERT ON highlight BEGIN
                    INSERT INTO highlight_search (highlightId, title, annotation, ocr_text, metadata)
                    VALUES (
                        new.id,
                        CASE
                            WHEN new.highlightType = 'file' THEN
                                COALESCE((SELECT fileName FROM file_record WHERE id = new.fileId), '')
                            ELSE COALESCE(new.contentText, '')
                        END,
                        COALESCE(new.userNote, '') || ' ' ||
                        COALESCE((SELECT GROUP_CONCAT(body, ' ') FROM highlight_note WHERE highlightId = new.id), ''),
                        COALESCE((SELECT ocrText FROM screenshot WHERE id = new.screenshotId), ''),
                        COALESCE(new.sourceApp, '') || ' ' ||
                        COALESCE(new.sourceUrl, '') || ' ' ||
                        COALESCE(new.windowTitle, '') || ' ' ||
                        COALESCE(new.documentPath, '') || ' ' ||
                        COALESCE(new.bundleId, '')
                    );
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER highlight_search_au AFTER UPDATE ON highlight BEGIN
                    UPDATE highlight_search SET
                        title = CASE
                            WHEN new.highlightType = 'file' THEN
                                COALESCE((SELECT fileName FROM file_record WHERE id = new.fileId), '')
                            ELSE COALESCE(new.contentText, '')
                        END,
                        annotation = COALESCE(new.userNote, '') || ' ' ||
                            COALESCE((SELECT GROUP_CONCAT(body, ' ') FROM highlight_note WHERE highlightId = new.id), ''),
                        ocr_text = COALESCE((SELECT ocrText FROM screenshot WHERE id = new.screenshotId), ''),
                        metadata = COALESCE(new.sourceApp, '') || ' ' ||
                            COALESCE(new.sourceUrl, '') || ' ' ||
                            COALESCE(new.windowTitle, '') || ' ' ||
                            COALESCE(new.documentPath, '') || ' ' ||
                            COALESCE(new.bundleId, '')
                    WHERE highlightId = new.id;
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER highlight_search_ad AFTER DELETE ON highlight BEGIN
                    DELETE FROM highlight_search WHERE highlightId = old.id;
                END
                """)

            // Note changes → refresh only the annotation column on
            // the parent highlight_search row.
            try db.execute(sql: """
                CREATE TRIGGER highlight_note_search_ai AFTER INSERT ON highlight_note BEGIN
                    UPDATE highlight_search SET annotation = (
                        SELECT COALESCE(h.userNote, '') || ' ' ||
                               COALESCE((SELECT GROUP_CONCAT(body, ' ') FROM highlight_note WHERE highlightId = h.id), '')
                        FROM highlight h WHERE h.id = new.highlightId
                    )
                    WHERE highlightId = new.highlightId;
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER highlight_note_search_au AFTER UPDATE ON highlight_note BEGIN
                    UPDATE highlight_search SET annotation = (
                        SELECT COALESCE(h.userNote, '') || ' ' ||
                               COALESCE((SELECT GROUP_CONCAT(body, ' ') FROM highlight_note WHERE highlightId = h.id), '')
                        FROM highlight h WHERE h.id = new.highlightId
                    )
                    WHERE highlightId = new.highlightId;
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER highlight_note_search_ad AFTER DELETE ON highlight_note BEGIN
                    UPDATE highlight_search SET annotation = (
                        SELECT COALESCE(h.userNote, '') || ' ' ||
                               COALESCE((SELECT GROUP_CONCAT(body, ' ') FROM highlight_note WHERE highlightId = h.id), '')
                        FROM highlight h WHERE h.id = old.highlightId
                    )
                    WHERE highlightId = old.highlightId;
                END
                """)

            // OCR landing after highlight creation — refresh only
            // the ocr_text column for every highlight pointing at
            // this screenshot.
            try db.execute(sql: """
                CREATE TRIGGER screenshot_ocr_search_au AFTER UPDATE OF ocrText ON screenshot BEGIN
                    UPDATE highlight_search SET ocr_text = COALESCE(new.ocrText, '')
                    WHERE highlightId IN (SELECT id FROM highlight WHERE screenshotId = new.id);
                END
                """)

            // File rename — refresh only the title column for file
            // highlights pointing at this file_record.
            try db.execute(sql: """
                CREATE TRIGGER file_record_name_search_au AFTER UPDATE OF fileName ON file_record BEGIN
                    UPDATE highlight_search SET title = COALESCE(new.fileName, '')
                    WHERE highlightId IN (
                        SELECT id FROM highlight
                        WHERE fileId = new.id AND highlightType = 'file'
                    );
                END
                """)

            // Backfill from the existing `highlight` table. Runs the
            // same assembly as the insert trigger, once per row.
            let backfillStart = Date()
            try db.execute(sql: """
                INSERT INTO highlight_search (highlightId, title, annotation, ocr_text, metadata)
                SELECT h.id,
                    CASE
                        WHEN h.highlightType = 'file' THEN
                            COALESCE((SELECT fileName FROM file_record WHERE id = h.fileId), '')
                        ELSE COALESCE(h.contentText, '')
                    END,
                    COALESCE(h.userNote, '') || ' ' ||
                        COALESCE((SELECT GROUP_CONCAT(body, ' ') FROM highlight_note WHERE highlightId = h.id), ''),
                    COALESCE((SELECT ocrText FROM screenshot WHERE id = h.screenshotId), ''),
                    COALESCE(h.sourceApp, '') || ' ' ||
                        COALESCE(h.sourceUrl, '') || ' ' ||
                        COALESCE(h.windowTitle, '') || ' ' ||
                        COALESCE(h.documentPath, '') || ' ' ||
                        COALESCE(h.bundleId, '')
                FROM highlight h
                """)
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM highlight_search") ?? 0
            let elapsed = Int(Date().timeIntervalSince(backfillStart) * 1000)
            CaptureLog.info("[migration v25] FTS5 per-column backfill: \(count) highlights indexed in \(elapsed)ms")
        }

        // V1 spec primitives: a Workspace is a spatial surface, a Placement
        // is a card's appearance inside one — both net-new at v26 (pre-v26
        // the app was archive + stacks only). The new columns on
        // highlight/stack capture Card.origin_type and Stack.origin_*
        // metadata so the system can answer "where did this come from /
        // where does it live now" without an expensive backfill — a
        // DEFAULT 'captured' on origin_type fills existing rows in-place
        // (ALTER TABLE ADD COLUMN does not fire AFTER UPDATE triggers,
        // so the v25 FTS5 mirror is untouched).
        migrator.registerMigration("v26_workspace_and_origin") { db in
            // Workspace — a named spatial surface. id is a UUID string so
            // it can be carried inside `case .workspace(id: String)` on
            // WorkspaceTabContent (Phase B) without a join.
            try db.create(table: "workspace", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("name", .text)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_workspace_updatedAt
                ON workspace(updatedAt)
                """)

            // Placement — one card's appearance in one workspace at given
            // coordinates. UNIQUE(workspaceId, cardId) enforces the V1
            // invariant that a card appears at most once per workspace
            // (the spec parks "cards appearing multiple times in same
            // workspace" as explicitly excluded). Cascading deletes from
            // both parents keep the table clean without app-side bookkeeping.
            try db.create(table: "placement", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("workspaceId", .text).notNull()
                    .references("workspace", onDelete: .cascade)
                t.column("cardId", .text).notNull()
                    .references("highlight", onDelete: .cascade)
                t.column("x", .double).notNull()
                t.column("y", .double).notNull()
                t.column("width", .double).notNull()
                t.column("height", .double).notNull()
                t.column("createdAt", .double).notNull()
            }
            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_placement_workspace_card
                ON placement(workspaceId, cardId)
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_placement_workspaceId
                ON placement(workspaceId)
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_placement_cardId
                ON placement(cardId)
                """)

            // Card.origin_type / parent_card_id / derivation columns.
            // origin_type is NOT NULL DEFAULT 'captured' so SQLite back-fills
            // every existing row in-place at ALTER time — no UPDATE sweep
            // is needed, and the v25 highlight_search_au trigger (which
            // fires on any UPDATE to highlight) stays quiet.
            try db.alter(table: "highlight") { t in
                t.add(column: "originType", .text).notNull().defaults(to: "captured")
                t.add(column: "originWorkspaceId", .text)
                t.add(column: "parentCardId", .text)
                t.add(column: "derivationType", .text)
                t.add(column: "derivationData", .text)
                t.add(column: "inheritedProvenance", .text)
            }
            // Reverse derivation lookup ("Derived from this" — Phase E).
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_highlight_parentCardId
                ON highlight(parentCardId)
                """)
            // Cards authored inside a given workspace.
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_highlight_originWorkspaceId
                ON highlight(originWorkspaceId)
                """)

            // Stack.origin_workspace_id + arrangement snapshot — populated
            // when a stack is created from a workspace canvas selection
            // (Phase F). Snapshot is JSON: [{cardId, x, y, w, h}] frozen
            // at create time. Both nullable so today's non-canvas creation
            // paths (AllStacksView "+ New stack", merge, etc.) leave them
            // null and don't gain a "View origin arrangement" link.
            try db.alter(table: "stack") { t in
                t.add(column: "originWorkspaceId", .text)
                t.add(column: "originArrangementSnapshot", .text)
            }
        }

        migrator.registerMigration("v27_screenshot_sources") { db in
            // Multi-source attribution for screenshots — JSON-encoded
            // [ScreenshotSource] computed at capture time by walking
            // the SCWindow z-order over the capture rect with
            // occlusion subtraction. Nullable so historical rows and
            // non-screenshot capture paths render unchanged.
            try db.alter(table: "highlight") { t in
                t.add(column: "sources", .text)
            }
            try db.alter(table: "screenshot") { t in
                t.add(column: "sources", .text)
            }
        }
    }
}
