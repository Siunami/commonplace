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
    }
}
