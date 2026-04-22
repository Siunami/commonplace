import Foundation
import GRDB

extension DatabaseManager {
    /// One-shot, idempotent backfill of `sourceContext` for highlights
    /// captured before the enricher shipped. Reconstructs a minimal
    /// `RawCaptureInputs` from stored `bundleId` / `windowTitle`; pasteboard
    /// fields are intentionally nil since we can't recover them after the
    /// fact. Rows where the registry returns empty stay NULL so a later app
    /// version (with a smarter enricher) gets another shot.
    func backfillSourceContextIfNeeded() {
        guard let dbQueue else { return }

        do {
            let rows = try dbQueue.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, bundleId, sourceApp, windowTitle
                    FROM highlight
                    WHERE sourceContext IS NULL
                      AND bundleId IS NOT NULL
                    LIMIT 5000
                    """)
            }

            guard !rows.isEmpty else { return }

            var updated = 0
            try dbQueue.write { db in
                for row in rows {
                    let id: String = row["id"]
                    let bundleId: String? = row["bundleId"]
                    let appName: String? = row["sourceApp"]
                    let windowTitle: String? = row["windowTitle"]

                    let inputs = RawCaptureInputs(
                        bundleId: bundleId,
                        appName: appName,
                        windowTitle: windowTitle,
                        pid: nil,
                        pasteboardTypes: [],
                        pasteboardHTML: nil,
                        pasteboardRTF: nil,
                        pasteboardText: nil
                    )

                    let entries = SourceEnricherRegistry.shared.enrich(inputs: inputs)
                    guard !entries.isEmpty,
                          let data = try? JSONEncoder().encode(entries),
                          let json = String(data: data, encoding: .utf8) else {
                        continue
                    }

                    try db.execute(
                        sql: "UPDATE highlight SET sourceContext = ? WHERE id = ?",
                        arguments: [json, id]
                    )
                    updated += 1
                }
            }

            if updated > 0 {
                CaptureLog.info("sourceContext backfill: enriched \(updated) of \(rows.count) historical rows")
            }
        } catch {
            CaptureLog.warning("sourceContext backfill failed: \(error.localizedDescription)")
        }
    }
}
