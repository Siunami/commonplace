import Foundation
import GRDB

extension Notification.Name {
    /// Posted when a stack is created, renamed, pinned/unpinned, or has
    /// members added/removed. userInfo may include "stackId".
    static let stackDataDidChange = Notification.Name("stackDataDidChange")
}

extension DatabaseManager {
    // MARK: - Stack reads

    func pinnedStack() -> Stack? {
        try? dbQueue?.read { db in
            try Stack.fetchOne(db, sql: "SELECT * FROM stack WHERE isPinned = 1 LIMIT 1")
        }
    }

    func stack(byId id: String) -> Stack? {
        try? dbQueue?.read { db in
            try Stack.fetchOne(db, key: id)
        }
    }

    /// All stacks ordered with the pinned stack first, then by most-recent
    /// activity (updatedAt desc). Prunes zero-item stacks before returning.
    func allStacks() -> [Stack] {
        pruneEmptyStacks()
        return (try? dbQueue?.read { db in
            try Stack.fetchAll(db, sql: """
                SELECT * FROM stack
                ORDER BY isPinned DESC, updatedAt DESC
                """)
        }) ?? []
    }

    /// Removes any stack that currently has zero items. Called from
    /// `allStacks()` and after item-removal so empties never linger.
    func pruneEmptyStacks() {
        guard let dbQueue else { return }
        let deletedIds: [String] = (try? dbQueue.write { db in
            let ids = try String.fetchAll(db, sql: """
                SELECT s.id FROM stack s
                LEFT JOIN highlight_stack hs ON hs.stackId = s.id
                WHERE hs.stackId IS NULL
                """)
            if !ids.isEmpty {
                try db.execute(
                    sql: "DELETE FROM stack WHERE id IN (\(ids.map { _ in "?" }.joined(separator: ",")))",
                    arguments: StatementArguments(ids)
                )
            }
            return ids
        }) ?? []
        if !deletedIds.isEmpty {
            NotificationCenter.default.post(name: .stackDataDidChange, object: nil)
        }
    }

    func highlightsForStack(stackId: String) -> [Highlight] {
        (try? dbQueue?.read { db in
            try Highlight.fetchAll(db, sql: """
                SELECT h.* FROM highlight h
                JOIN highlight_stack hs ON hs.highlightId = h.id
                WHERE hs.stackId = ?
                ORDER BY hs.addedAt DESC
                """, arguments: [stackId])
        }) ?? []
    }

    /// Up to `limit` most-recently-added items for the given stack.
    /// Used for the 6-item mosaic preview on stack cards.
    func recentHighlightsForStack(stackId: String, limit: Int = 6) -> [Highlight] {
        (try? dbQueue?.read { db in
            try Highlight.fetchAll(db, sql: """
                SELECT h.* FROM highlight h
                JOIN highlight_stack hs ON hs.highlightId = h.id
                WHERE hs.stackId = ?
                ORDER BY hs.addedAt DESC
                LIMIT ?
                """, arguments: [stackId, limit])
        }) ?? []
    }

    func itemCountForStack(stackId: String) -> Int {
        (try? dbQueue?.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM highlight_stack WHERE stackId = ?",
                             arguments: [stackId])
        } ?? 0) ?? 0
    }

    func stackItemCounts() -> [String: Int] {
        guard let dbQueue else { return [:] }
        return (try? dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT stackId, COUNT(*) as cnt FROM highlight_stack GROUP BY stackId
                """)
            var result: [String: Int] = [:]
            for row in rows {
                if let id: String = row["stackId"], let cnt: Int = row["cnt"] {
                    result[id] = cnt
                }
            }
            return result
        }) ?? [:]
    }

    /// Stacks that contain the given highlight — used to surface "pivot" stacks
    /// when viewing a single item.
    func stacksForHighlight(id: String) -> [Stack] {
        (try? dbQueue?.read { db in
            try Stack.fetchAll(db, sql: """
                SELECT s.* FROM stack s
                JOIN highlight_stack hs ON hs.stackId = s.id
                WHERE hs.highlightId = ?
                ORDER BY s.updatedAt DESC
                """, arguments: [id])
        }) ?? []
    }

    // MARK: - Stack writes

    /// Create a new stack and return it. Optionally pins it immediately —
    /// pinning unsets any previously pinned stack in the same transaction.
    @discardableResult
    func createStack(name: String? = nil, pinned: Bool = false) -> Stack? {
        guard let dbQueue else { return nil }
        let now = Date().timeIntervalSince1970
        let stack = Stack(
            id: UUID().uuidString,
            name: name,
            stackDescription: nil,
            createdAt: now,
            updatedAt: now,
            isPinned: pinned
        )
        do {
            try dbQueue.write { db in
                if pinned {
                    try db.execute(sql: "UPDATE stack SET isPinned = 0 WHERE isPinned = 1")
                }
                try stack.insert(db)
            }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil,
                userInfo: ["stackId": stack.id]
            )
            return stack
        } catch {
            CaptureLog.error("Failed to create stack: \(error.localizedDescription)")
            return nil
        }
    }

    func deleteStack(id: String) {
        guard let dbQueue else { return }
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM stack WHERE id = ?", arguments: [id])
            }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil,
                userInfo: ["stackId": id]
            )
        } catch {
            CaptureLog.error("Failed to delete stack: \(error.localizedDescription)")
        }
    }

    func renameStack(id: String, name: String?) {
        guard let dbQueue else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedName = (trimmed?.isEmpty ?? true) ? nil : trimmed
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE stack SET name = ?, updatedAt = ? WHERE id = ?",
                    arguments: [storedName, Date().timeIntervalSince1970, id]
                )
            }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil,
                userInfo: ["stackId": id]
            )
        } catch {
            CaptureLog.error("Failed to rename stack: \(error.localizedDescription)")
        }
    }

    func setStackDescription(id: String, description: String?) {
        guard let dbQueue else { return }
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedDesc = (trimmed?.isEmpty ?? true) ? nil : trimmed
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE stack SET description = ?, updatedAt = ? WHERE id = ?",
                    arguments: [storedDesc, Date().timeIntervalSince1970, id]
                )
            }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil,
                userInfo: ["stackId": id]
            )
        } catch {
            CaptureLog.error("Failed to update stack description: \(error.localizedDescription)")
        }
    }

    /// Pin the given stack, unpinning any other stack in the same transaction.
    /// Pass nil to unpin whatever is currently pinned.
    func setPinnedStack(id: String?) {
        guard let dbQueue else { return }
        do {
            try dbQueue.write { db in
                try db.execute(sql: "UPDATE stack SET isPinned = 0 WHERE isPinned = 1")
                if let id = id {
                    try db.execute(
                        sql: "UPDATE stack SET isPinned = 1, updatedAt = ? WHERE id = ?",
                        arguments: [Date().timeIntervalSince1970, id]
                    )
                }
            }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil,
                userInfo: id.map { ["stackId": $0] } ?? [:]
            )
        } catch {
            CaptureLog.error("Failed to pin stack: \(error.localizedDescription)")
        }
    }

    /// Add an item to a stack. Bumps the stack's updatedAt so it floats
    /// to the top of recency-ordered lists.
    func addHighlight(_ highlightId: String, toStack stackId: String) {
        guard let dbQueue else { return }
        let now = Date().timeIntervalSince1970
        do {
            try dbQueue.write { db in
                try db.execute(sql: """
                    INSERT OR IGNORE INTO highlight_stack (stackId, highlightId, addedAt)
                    VALUES (?, ?, ?)
                    """, arguments: [stackId, highlightId, now])
                try db.execute(
                    sql: "UPDATE stack SET updatedAt = ? WHERE id = ?",
                    arguments: [now, stackId]
                )
            }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil,
                userInfo: ["stackId": stackId, "highlightId": highlightId]
            )
        } catch {
            CaptureLog.error("Failed to add highlight to stack: \(error.localizedDescription)")
        }
    }

    func removeHighlight(_ highlightId: String, fromStack stackId: String) {
        guard let dbQueue else { return }
        let now = Date().timeIntervalSince1970
        var stackWasDeleted = false
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "DELETE FROM highlight_stack WHERE stackId = ? AND highlightId = ?",
                    arguments: [stackId, highlightId]
                )
                let remaining = try Int.fetchOne(db,
                    sql: "SELECT COUNT(*) FROM highlight_stack WHERE stackId = ?",
                    arguments: [stackId]) ?? 0
                if remaining == 0 {
                    try db.execute(sql: "DELETE FROM stack WHERE id = ?", arguments: [stackId])
                    stackWasDeleted = true
                } else {
                    try db.execute(
                        sql: "UPDATE stack SET updatedAt = ? WHERE id = ?",
                        arguments: [now, stackId]
                    )
                }
            }
            var info: [String: Any] = ["stackId": stackId, "highlightId": highlightId]
            if stackWasDeleted { info["stackDeleted"] = true }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil, userInfo: info
            )
        } catch {
            CaptureLog.error("Failed to remove highlight from stack: \(error.localizedDescription)")
        }
    }

    /// Convenience used by the archive "+ to stack" button: add to the
    /// currently pinned stack if there is one; otherwise create a new
    /// unnamed stack, pin it, and add the item. Returns the stack used.
    @discardableResult
    func addHighlightToPinnedOrNewStack(_ highlightId: String) -> Stack? {
        if let pinned = pinnedStack() {
            addHighlight(highlightId, toStack: pinned.id)
            return stack(byId: pinned.id)
        }
        guard let created = createStack(name: nil, pinned: true) else { return nil }
        addHighlight(highlightId, toStack: created.id)
        return stack(byId: created.id)
    }

    /// Bulk variant of `addHighlightToPinnedOrNewStack`. All inserts run
    /// in a single write transaction and one change notification is posted,
    /// so "add all from this time range" is cheap regardless of cluster size.
    @discardableResult
    func addHighlightsToPinnedOrNewStack(_ highlightIds: [String]) -> Stack? {
        guard !highlightIds.isEmpty else { return nil }
        let target: Stack
        if let pinned = pinnedStack() {
            target = pinned
        } else if let created = createStack(name: nil, pinned: true) {
            target = created
        } else {
            return nil
        }
        guard let dbQueue else { return target }
        let now = Date().timeIntervalSince1970
        do {
            try dbQueue.write { db in
                for hid in highlightIds {
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO highlight_stack (stackId, highlightId, addedAt)
                        VALUES (?, ?, ?)
                        """, arguments: [target.id, hid, now])
                }
                try db.execute(
                    sql: "UPDATE stack SET updatedAt = ? WHERE id = ?",
                    arguments: [now, target.id]
                )
            }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil,
                userInfo: ["stackId": target.id]
            )
            return stack(byId: target.id)
        } catch {
            CaptureLog.error("Failed to bulk-add highlights to stack: \(error.localizedDescription)")
            return target
        }
    }
}
