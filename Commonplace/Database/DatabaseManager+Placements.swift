import Foundation
import GRDB

extension Notification.Name {
    /// Posted when a placement is created, moved, resized, or deleted.
    /// userInfo may include "workspaceId" and "placementId".
    static let placementDataDidChange = Notification.Name("placementDataDidChange")
}

extension DatabaseManager {
    // MARK: - Placement reads

    func placement(byId id: String) -> Placement? {
        try? dbQueue?.read { db in
            try Placement.fetchOne(db, key: id)
        }
    }

    /// Every placement in `workspaceId`, ordered by `createdAt` ascending —
    /// callers render in array order, so the latest-placed card lands on
    /// top of the canvas z-stack.
    func placementsForWorkspace(workspaceId: String) -> [Placement] {
        (try? dbQueue?.read { db in
            try Placement.fetchAll(db, sql: """
                SELECT * FROM placement
                WHERE workspaceId = ?
                ORDER BY createdAt ASC
                """, arguments: [workspaceId])
        }) ?? []
    }

    /// Existing placement of `cardId` in `workspaceId`, if any. Used to
    /// honour the V1 invariant of one appearance per (workspace, card) —
    /// callers can no-op or move the existing placement instead of trying
    /// to insert a duplicate.
    func placement(workspaceId: String, cardId: String) -> Placement? {
        try? dbQueue?.read { db in
            try Placement.fetchOne(db, sql: """
                SELECT * FROM placement
                WHERE workspaceId = ? AND cardId = ?
                """, arguments: [workspaceId, cardId])
        }
    }

    /// Lightweight placement snapshot for the workspace card miniature —
    /// world-coord rectangle plus highlight type for color tinting. Joins
    /// to highlight in a single query so the card avoids N+1 fetches.
    struct PlacementMiniature {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var highlightType: String
    }

    func placementsForWorkspaceMiniature(workspaceId: String) -> [PlacementMiniature] {
        (try? dbQueue?.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT p.x, p.y, p.width, p.height, h.highlightType
                FROM placement p
                JOIN highlight h ON h.id = p.cardId
                WHERE p.workspaceId = ?
                """, arguments: [workspaceId])
            return rows.map { row in
                PlacementMiniature(
                    x: row["x"] ?? 0,
                    y: row["y"] ?? 0,
                    width: row["width"] ?? 0,
                    height: row["height"] ?? 0,
                    highlightType: row["highlightType"] ?? "highlight"
                )
            }
        }) ?? []
    }

    func placementCountForWorkspace(workspaceId: String) -> Int {
        (try? dbQueue?.read { db in
            try Int.fetchOne(db,
                sql: "SELECT COUNT(*) FROM placement WHERE workspaceId = ?",
                arguments: [workspaceId]) ?? 0
        }) ?? 0
    }

    /// Subset of `cardIds` that already have a placement in `workspaceId`.
    /// Backs the lens path's "n visible / total" badge and lets drop
    /// handlers skip cards that are already on the canvas.
    func placedCardIds(in workspaceId: String, from cardIds: [String]) -> Set<String> {
        guard let dbQueue, !cardIds.isEmpty else { return [] }
        let placeholders = cardIds.map { _ in "?" }.joined(separator: ",")
        var args: [DatabaseValueConvertible] = [workspaceId]
        args.append(contentsOf: cardIds)
        let ids: [String] = (try? dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT cardId FROM placement
                WHERE workspaceId = ? AND cardId IN (\(placeholders))
                """, arguments: StatementArguments(args))
        }) ?? []
        return Set(ids)
    }

    // MARK: - Placement writes

    /// Insert a placement at the given coordinates. Returns the new
    /// placement, or the existing one if (workspaceId, cardId) already
    /// has a placement (the UNIQUE index enforces the invariant at the DB
    /// level — this is the app-side fast path that avoids the constraint
    /// failure round trip).
    @discardableResult
    func createPlacement(
        workspaceId: String,
        cardId: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> Placement? {
        if let existing = placement(workspaceId: workspaceId, cardId: cardId) {
            return existing
        }
        guard let dbQueue else { return nil }
        let placement = Placement(
            id: UUID().uuidString,
            workspaceId: workspaceId,
            cardId: cardId,
            x: x,
            y: y,
            width: width,
            height: height,
            createdAt: Date().timeIntervalSince1970
        )
        do {
            try dbQueue.write { db in
                try placement.insert(db)
                try db.execute(
                    sql: "UPDATE workspace SET updatedAt = ? WHERE id = ?",
                    arguments: [placement.createdAt, workspaceId]
                )
            }
            NotificationCenter.default.post(
                name: .placementDataDidChange, object: nil,
                userInfo: ["workspaceId": workspaceId, "placementId": placement.id]
            )
            return placement
        } catch {
            CaptureLog.error("Failed to create placement: \(error.localizedDescription)")
            return nil
        }
    }

    /// Commit a finished move. Does not bump `workspace.updatedAt` so a
    /// continuous drag gesture doesn't keep re-sorting the workspace
    /// listing — call `touchWorkspace(id:)` once at gesture end if needed.
    func updatePlacementPosition(id: String, x: Double, y: Double) {
        guard let dbQueue else { return }
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE placement SET x = ?, y = ? WHERE id = ?",
                    arguments: [x, y, id]
                )
            }
        } catch {
            CaptureLog.error("Failed to update placement position: \(error.localizedDescription)")
        }
    }

    /// Commit a finished resize. Pairs with `updatePlacementPosition` —
    /// resize handles are an optional Phase B affordance; canvases that
    /// don't expose them ignore this entry point.
    func updatePlacementSize(id: String, width: Double, height: Double) {
        guard let dbQueue else { return }
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE placement SET width = ?, height = ? WHERE id = ?",
                    arguments: [width, height, id]
                )
            }
        } catch {
            CaptureLog.error("Failed to update placement size: \(error.localizedDescription)")
        }
    }

    func deletePlacement(id: String) {
        guard let dbQueue else { return }
        let workspaceId: String? = try? dbQueue.read { db in
            try Row.fetchOne(db,
                sql: "SELECT workspaceId FROM placement WHERE id = ?",
                arguments: [id])?["workspaceId"]
        }
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM placement WHERE id = ?", arguments: [id])
            }
            var info: [String: String] = ["placementId": id]
            if let wid = workspaceId { info["workspaceId"] = wid }
            NotificationCenter.default.post(
                name: .placementDataDidChange, object: nil,
                userInfo: info
            )
        } catch {
            CaptureLog.error("Failed to delete placement: \(error.localizedDescription)")
        }
    }
}
