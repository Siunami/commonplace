import Foundation
import GRDB

extension Notification.Name {
    /// Posted when a workspace is created, renamed, touched, or deleted.
    /// userInfo may include "workspaceId".
    static let workspaceDataDidChange = Notification.Name("workspaceDataDidChange")
}

extension DatabaseManager {
    // MARK: - Workspace reads

    func workspace(byId id: String) -> Workspace? {
        try? dbQueue?.read { db in
            try Workspace.fetchOne(db, key: id)
        }
    }

    /// All workspaces ordered by most-recent activity. `updatedAt` is
    /// bumped via `touchWorkspace` whenever a placement lands or moves
    /// so the listing reflects actual recent attention.
    func allWorkspaces() -> [Workspace] {
        (try? dbQueue?.read { db in
            try Workspace.fetchAll(db, sql: """
                SELECT * FROM workspace
                ORDER BY updatedAt DESC
                """)
        }) ?? []
    }

    /// Distinct workspaces this card appears in (via its placements).
    /// Backs the `CardDetailView` "Appears in workspaces" pivot section.
    func workspacesContaining(cardId: String) -> [Workspace] {
        (try? dbQueue?.read { db in
            try Workspace.fetchAll(db, sql: """
                SELECT w.* FROM workspace w
                JOIN placement p ON p.workspaceId = w.id
                WHERE p.cardId = ?
                GROUP BY w.id
                ORDER BY w.updatedAt DESC
                """, arguments: [cardId])
        }) ?? []
    }

    // MARK: - Workspace writes

    @discardableResult
    func createWorkspace(name: String? = nil) -> Workspace? {
        guard let dbQueue else { return nil }
        let now = Date().timeIntervalSince1970
        let workspace = Workspace(
            id: UUID().uuidString,
            name: name,
            createdAt: now,
            updatedAt: now
        )
        do {
            try dbQueue.write { db in
                try workspace.insert(db)
            }
            NotificationCenter.default.post(
                name: .workspaceDataDidChange, object: nil,
                userInfo: ["workspaceId": workspace.id]
            )
            return workspace
        } catch {
            CaptureLog.error("Failed to create workspace: \(error.localizedDescription)")
            return nil
        }
    }

    func renameWorkspace(id: String, name: String?) {
        guard let dbQueue else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = (trimmed?.isEmpty ?? true) ? nil : trimmed
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE workspace SET name = ?, updatedAt = ? WHERE id = ?",
                    arguments: [stored, Date().timeIntervalSince1970, id]
                )
            }
            NotificationCenter.default.post(
                name: .workspaceDataDidChange, object: nil,
                userInfo: ["workspaceId": id]
            )
        } catch {
            CaptureLog.error("Failed to rename workspace: \(error.localizedDescription)")
        }
    }

    /// Bumps `updatedAt` so the workspace floats to the top of
    /// `allWorkspaces()`. Called when a placement lands, moves, or is
    /// removed so listings reflect the user's actual recent attention.
    func touchWorkspace(id: String) {
        guard let dbQueue else { return }
        try? dbQueue.write { db in
            try db.execute(
                sql: "UPDATE workspace SET updatedAt = ? WHERE id = ?",
                arguments: [Date().timeIntervalSince1970, id]
            )
        }
    }

    func deleteWorkspace(id: String) {
        guard let dbQueue else { return }
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM workspace WHERE id = ?", arguments: [id])
            }
            NotificationCenter.default.post(
                name: .workspaceDataDidChange, object: nil,
                userInfo: ["workspaceId": id]
            )
        } catch {
            CaptureLog.error("Failed to delete workspace: \(error.localizedDescription)")
        }
    }

    /// Deletes the workspace iff it has no name and no placements. Called
    /// when a workspace tab is closed so unnamed empty drafts don't
    /// accumulate. Named workspaces always survive — they're intentional
    /// placeholders. Returns true if the workspace was deleted.
    @discardableResult
    func pruneWorkspaceIfEmptyUnnamed(id: String) -> Bool {
        guard let dbQueue else { return false }
        let didDelete: Bool = (try? dbQueue.write { db in
            let row = try Row.fetchOne(db,
                sql: "SELECT name FROM workspace WHERE id = ?",
                arguments: [id])
            guard let row else { return false }
            let name: String? = row["name"]
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard trimmed.isEmpty else { return false }
            let count = try Int.fetchOne(db,
                sql: "SELECT COUNT(*) FROM placement WHERE workspaceId = ?",
                arguments: [id]) ?? 0
            guard count == 0 else { return false }
            try db.execute(sql: "DELETE FROM workspace WHERE id = ?", arguments: [id])
            return true
        }) ?? false
        if didDelete {
            NotificationCenter.default.post(
                name: .workspaceDataDidChange, object: nil,
                userInfo: ["workspaceId": id, "workspaceDeleted": true]
            )
        }
        return didDelete
    }
}
