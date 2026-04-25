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
    /// activity (updatedAt desc). Does not auto-prune on read — the "+ New
    /// stack" affordance creates a fresh unnamed empty stack and would
    /// race against an eager sweep before the user had a chance to name
    /// it. Emptied-out stacks are already deleted inline from `removeHighlight`
    /// and `moveHighlightsToNewStack`, so the eager sweep isn't needed here.
    func allStacks() -> [Stack] {
        return (try? dbQueue?.read { db in
            try Stack.fetchAll(db, sql: """
                SELECT * FROM stack
                ORDER BY isPinned DESC, updatedAt DESC
                """)
        }) ?? []
    }

    /// Removes unnamed stacks that currently have zero highlights AND zero
    /// substacks. Named stacks are *index-card placeholders* the user created
    /// intentionally — they survive going empty so the "outline first, fill
    /// later" workflow works. A stack with only substacks (no highlights) is
    /// also non-empty and is preserved.
    func pruneEmptyStacks() {
        guard let dbQueue else { return }
        let deletedIds: [String] = (try? dbQueue.write { db in
            let ids = try String.fetchAll(db, sql: """
                SELECT s.id FROM stack s
                WHERE (s.name IS NULL OR TRIM(s.name) = '')
                  AND NOT EXISTS (SELECT 1 FROM highlight_stack hs WHERE hs.stackId = s.id)
                  AND NOT EXISTS (SELECT 1 FROM stack_stack ss WHERE ss.parentStackId = s.id)
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
                ORDER BY hs.position ASC, hs.addedAt DESC
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
                ORDER BY hs.position ASC, hs.addedAt DESC
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

    /// The set of highlight ids currently in the pinned stack (or empty
    /// when nothing is pinned). BrowseView uses this to visually flag
    /// items that are already members, so the "add" button becomes a
    /// proper toggle.
    func highlightIdsInPinnedStack() -> Set<String> {
        guard let dbQueue else { return [] }
        let ids: [String] = (try? dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT hs.highlightId
                FROM highlight_stack hs
                JOIN stack s ON s.id = hs.stackId
                WHERE s.isPinned = 1
                """)
        }) ?? []
        return Set(ids)
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
    /// to the top of recency-ordered lists. New items land at the TOP
    /// of the user-defined order (MIN(position) - 1) so captures appear
    /// where the user expects them without disturbing existing drag
    /// arrangements below.
    func addHighlight(_ highlightId: String, toStack stackId: String) {
        guard let dbQueue else { return }
        let now = Date().timeIntervalSince1970
        do {
            try dbQueue.write { db in
                let nextPosition = (try Int.fetchOne(db,
                    sql: "SELECT COALESCE(MIN(position), 0) - 1 FROM highlight_stack WHERE stackId = ?",
                    arguments: [stackId]) ?? -1)
                try db.execute(sql: """
                    INSERT OR IGNORE INTO highlight_stack (stackId, highlightId, addedAt, position)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [stackId, highlightId, now, nextPosition])
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
                let remainingHighlights = try Int.fetchOne(db,
                    sql: "SELECT COUNT(*) FROM highlight_stack WHERE stackId = ?",
                    arguments: [stackId]) ?? 0
                let remainingSubstacks = try Int.fetchOne(db,
                    sql: "SELECT COUNT(*) FROM stack_stack WHERE parentStackId = ?",
                    arguments: [stackId]) ?? 0
                // Named stacks (user-created placeholders) survive going empty.
                // Unnamed "scratch" stacks auto-delete only when they have
                // zero highlights AND zero substacks.
                let name = try String.fetchOne(db,
                    sql: "SELECT name FROM stack WHERE id = ?",
                    arguments: [stackId])
                let isNamed = !(name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                let isEmpty = remainingHighlights == 0 && remainingSubstacks == 0
                if isEmpty && !isNamed {
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

    /// Persist a new user-defined order for the given stack. `orderedIds`
    /// must be the complete list of highlight ids currently in the stack;
    /// any id present in the stack but missing from the list keeps its
    /// prior position (shouldn't happen under normal drag-reorder flow).
    func reorderHighlightsInStack(stackId: String, orderedIds: [String]) {
        guard let dbQueue, !orderedIds.isEmpty else { return }
        do {
            try dbQueue.write { db in
                for (index, hid) in orderedIds.enumerated() {
                    try db.execute(sql: """
                        UPDATE highlight_stack
                        SET position = ?
                        WHERE stackId = ? AND highlightId = ?
                        """, arguments: [index, stackId, hid])
                }
            }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil,
                userInfo: ["stackId": stackId, "reorder": true]
            )
        } catch {
            CaptureLog.error("Failed to reorder stack items: \(error.localizedDescription)")
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

    /// Opposite of `addHighlightToPinnedOrNewStack`: removes the highlight from
    /// the currently pinned stack (if any). No-op when nothing is pinned.
    func removeHighlightFromPinnedStack(_ highlightId: String) {
        guard let pinned = pinnedStack() else { return }
        removeHighlight(highlightId, fromStack: pinned.id)
    }

    /// Combine all items from `sourceId` into `destinationId` and delete
    /// the source stack. Source items are inserted at the TOP of the
    /// destination (lowest `position` values) in their source-ordered
    /// sequence, so the user's hand-ordering within the source is
    /// preserved at the top of the merged stack. INSERT OR IGNORE makes
    /// items already in both stacks a silent no-op. The composite PK on
    /// `highlight_stack` means the result is always duplicate-free.
    /// Notifies once, with `mergedSource` and `mergedInto` so listeners
    /// that were observing the source can swap to the destination.
    @discardableResult
    func mergeStack(sourceId: String, into destinationId: String) -> Bool {
        guard let dbQueue else { return false }
        guard sourceId != destinationId else { return false }
        let now = Date().timeIntervalSince1970
        do {
            try dbQueue.write { db in
                let sourceIds = try String.fetchAll(db, sql: """
                    SELECT highlightId FROM highlight_stack
                    WHERE stackId = ?
                    ORDER BY position ASC, addedAt DESC
                    """, arguments: [sourceId])

                if !sourceIds.isEmpty {
                    let minExisting = (try Int.fetchOne(db,
                        sql: "SELECT COALESCE(MIN(position), 0) FROM highlight_stack WHERE stackId = ?",
                        arguments: [destinationId]) ?? 0)
                    var nextPosition = minExisting - sourceIds.count
                    for hid in sourceIds {
                        try db.execute(sql: """
                            INSERT OR IGNORE INTO highlight_stack (stackId, highlightId, addedAt, position)
                            VALUES (?, ?, ?, ?)
                            """, arguments: [destinationId, hid, now, nextPosition])
                        nextPosition += 1
                    }
                    try db.execute(
                        sql: "UPDATE stack SET updatedAt = ? WHERE id = ?",
                        arguments: [now, destinationId]
                    )
                }

                // Cascading FK on highlight_stack removes source's junction rows.
                try db.execute(sql: "DELETE FROM stack WHERE id = ?", arguments: [sourceId])
            }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil,
                userInfo: ["mergedSource": sourceId, "mergedInto": destinationId]
            )
            return true
        } catch {
            CaptureLog.error("Failed to merge stack: \(error.localizedDescription)")
            return false
        }
    }

    /// Split a selection out of an existing stack into a brand-new
    /// unnamed stack, in a single transaction. Items keep their relative
    /// ordering from the source and are removed from it. If removing
    /// them leaves the source empty, the source is deleted too (matching
    /// the auto-prune behavior of single-item removal). Returns the new
    /// stack on success, or nil if nothing was moved / the transaction
    /// failed. Fires one `.stackDataDidChange` notification so every
    /// observer reloads once regardless of how many items moved.
    @discardableResult
    func moveHighlightsToNewStack(highlightIds: [String], fromStack sourceId: String) -> Stack? {
        guard let dbQueue else { return nil }
        guard !highlightIds.isEmpty else { return nil }
        let now = Date().timeIntervalSince1970
        let newStack = Stack(
            id: UUID().uuidString,
            name: nil,
            stackDescription: nil,
            createdAt: now,
            updatedAt: now,
            isPinned: false
        )
        do {
            var sourceStackDeleted = false
            try dbQueue.write { db in
                try newStack.insert(db)

                // Preserve source ordering for the moved items.
                let placeholders = Array(repeating: "?", count: highlightIds.count).joined(separator: ",")
                var args: [DatabaseValueConvertible] = [sourceId]
                args.append(contentsOf: highlightIds)
                let orderedIds = try String.fetchAll(db, sql: """
                    SELECT highlightId FROM highlight_stack
                    WHERE stackId = ? AND highlightId IN (\(placeholders))
                    ORDER BY position ASC, addedAt DESC
                    """, arguments: StatementArguments(args))

                for (index, hid) in orderedIds.enumerated() {
                    try db.execute(sql: """
                        INSERT INTO highlight_stack (stackId, highlightId, addedAt, position)
                        VALUES (?, ?, ?, ?)
                        """, arguments: [newStack.id, hid, now, index])
                }

                var deleteArgs: [DatabaseValueConvertible] = [sourceId]
                deleteArgs.append(contentsOf: highlightIds)
                try db.execute(sql: """
                    DELETE FROM highlight_stack
                    WHERE stackId = ? AND highlightId IN (\(placeholders))
                    """, arguments: StatementArguments(deleteArgs))

                let remainingHighlights = try Int.fetchOne(db,
                    sql: "SELECT COUNT(*) FROM highlight_stack WHERE stackId = ?",
                    arguments: [sourceId]) ?? 0
                let remainingSubstacks = try Int.fetchOne(db,
                    sql: "SELECT COUNT(*) FROM stack_stack WHERE parentStackId = ?",
                    arguments: [sourceId]) ?? 0
                let sourceName = try String.fetchOne(db,
                    sql: "SELECT name FROM stack WHERE id = ?",
                    arguments: [sourceId])
                let sourceIsNamed = !(sourceName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                let sourceIsEmpty = remainingHighlights == 0 && remainingSubstacks == 0
                if sourceIsEmpty && !sourceIsNamed {
                    try db.execute(sql: "DELETE FROM stack WHERE id = ?", arguments: [sourceId])
                    sourceStackDeleted = true
                } else {
                    try db.execute(
                        sql: "UPDATE stack SET updatedAt = ? WHERE id = ?",
                        arguments: [now, sourceId]
                    )
                }
            }
            var userInfo: [String: Any] = ["stackId": newStack.id, "sourceStackId": sourceId]
            if sourceStackDeleted { userInfo["sourceStackDeleted"] = true }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil, userInfo: userInfo
            )
            return newStack
        } catch {
            CaptureLog.error("Failed to move highlights to new stack: \(error.localizedDescription)")
            return nil
        }
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
                // Insert at the top. Reserve `highlightIds.count` slots
                // below the current min so input order is preserved
                // visually (first id in the array ends up highest).
                let minExisting = (try Int.fetchOne(db,
                    sql: "SELECT COALESCE(MIN(position), 0) FROM highlight_stack WHERE stackId = ?",
                    arguments: [target.id]) ?? 0)
                var nextPosition = minExisting - highlightIds.count
                for hid in highlightIds {
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO highlight_stack (stackId, highlightId, addedAt, position)
                        VALUES (?, ?, ?, ?)
                        """, arguments: [target.id, hid, now, nextPosition])
                    nextPosition += 1
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

    // MARK: - Substack reads

    /// All substacks of the given parent, ordered by the user-defined
    /// `position` (ascending). Fetched separately from highlights so the
    /// detail view can render substacks and items in two independent sections.
    func substacksForStack(stackId: String) -> [Stack] {
        (try? dbQueue?.read { db in
            try Stack.fetchAll(db, sql: """
                SELECT s.* FROM stack s
                JOIN stack_stack ss ON ss.childStackId = s.id
                WHERE ss.parentStackId = ?
                ORDER BY ss.position ASC, ss.addedAt DESC
                """, arguments: [stackId])
        }) ?? []
    }

    /// Up to `limit` most-recently-added substacks (by `addedAt`), used for
    /// mosaic preview rendering when a stack's tile needs to show substacks
    /// alongside highlight thumbnails.
    func recentSubstacksForStack(stackId: String, limit: Int = 6) -> [Stack] {
        (try? dbQueue?.read { db in
            try Stack.fetchAll(db, sql: """
                SELECT s.* FROM stack s
                JOIN stack_stack ss ON ss.childStackId = s.id
                WHERE ss.parentStackId = ?
                ORDER BY ss.position ASC, ss.addedAt DESC
                LIMIT ?
                """, arguments: [stackId, limit])
        }) ?? []
    }

    func substackCountForStack(stackId: String) -> Int {
        (try? dbQueue?.read { db in
            try Int.fetchOne(db,
                sql: "SELECT COUNT(*) FROM stack_stack WHERE parentStackId = ?",
                arguments: [stackId])
        } ?? 0) ?? 0
    }

    /// Parent stacks that contain the given child. Used by `StackCard` and
    /// `AllStacksView` to show a "⊂ Parent" indicator so nested stacks remain
    /// discoverable even when they also surface at the top level.
    func parentStacksForStack(stackId: String) -> [Stack] {
        (try? dbQueue?.read { db in
            try Stack.fetchAll(db, sql: """
                SELECT s.* FROM stack s
                JOIN stack_stack ss ON ss.parentStackId = s.id
                WHERE ss.childStackId = ?
                ORDER BY s.updatedAt DESC
                """, arguments: [stackId])
        }) ?? []
    }

    // MARK: - Substack writes

    /// Attach an existing stack as a substack of another. No items move —
    /// only the parent-child junction row is inserted. New substacks land at
    /// the TOP of the parent's substack section (MIN(position) - 1), matching
    /// how `addHighlight` floats new items to the top of their stack.
    /// Cycles are permitted intentionally; callers that recurse (export,
    /// reachable-item counts) must carry a visited set.
    func addSubstack(_ childId: String, toStack parentId: String) {
        guard let dbQueue else { return }
        guard childId != parentId else {
            // Self-reference is nonsense — the only cycle we do reject, for
            // consistency with `highlight_stack`'s composite PK semantics.
            return
        }
        let now = Date().timeIntervalSince1970
        do {
            try dbQueue.write { db in
                let nextPosition = (try Int.fetchOne(db,
                    sql: "SELECT COALESCE(MIN(position), 0) - 1 FROM stack_stack WHERE parentStackId = ?",
                    arguments: [parentId]) ?? -1)
                try db.execute(sql: """
                    INSERT OR IGNORE INTO stack_stack (parentStackId, childStackId, addedAt, position)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [parentId, childId, now, nextPosition])
                try db.execute(
                    sql: "UPDATE stack SET updatedAt = ? WHERE id = ?",
                    arguments: [now, parentId]
                )
            }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil,
                userInfo: ["stackId": parentId, "childStackId": childId]
            )
        } catch {
            CaptureLog.error("Failed to add substack: \(error.localizedDescription)")
        }
    }

    /// Detach a substack from its parent. The child stack itself survives
    /// (it remains a first-class top-level stack); only the parent-child
    /// relationship is removed. Never auto-prunes the child.
    func removeSubstack(_ childId: String, fromStack parentId: String) {
        guard let dbQueue else { return }
        let now = Date().timeIntervalSince1970
        do {
            try dbQueue.write { db in
                try db.execute(sql: """
                    DELETE FROM stack_stack
                    WHERE parentStackId = ? AND childStackId = ?
                    """, arguments: [parentId, childId])
                try db.execute(
                    sql: "UPDATE stack SET updatedAt = ? WHERE id = ?",
                    arguments: [now, parentId]
                )
            }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil,
                userInfo: ["stackId": parentId, "childStackId": childId]
            )
        } catch {
            CaptureLog.error("Failed to remove substack: \(error.localizedDescription)")
        }
    }

    /// Persist a new user-defined order for substacks within a parent.
    /// Mirrors `reorderHighlightsInStack` — `orderedIds` is the complete list
    /// of substack ids; rows not in the list keep their prior position.
    func reorderSubstacksInStack(parentId: String, orderedIds: [String]) {
        guard let dbQueue, !orderedIds.isEmpty else { return }
        do {
            try dbQueue.write { db in
                for (index, childId) in orderedIds.enumerated() {
                    try db.execute(sql: """
                        UPDATE stack_stack
                        SET position = ?
                        WHERE parentStackId = ? AND childStackId = ?
                        """, arguments: [index, parentId, childId])
                }
            }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil,
                userInfo: ["stackId": parentId, "reorderSubstacks": true]
            )
        } catch {
            CaptureLog.error("Failed to reorder substacks: \(error.localizedDescription)")
        }
    }

    /// "Group into substack" — the in-place grouping primitive. Given a
    /// selection of highlights within a parent stack, create a new unnamed
    /// child stack, move the selected highlights into it (preserving their
    /// source order), and attach the child to the parent. The highlights
    /// are removed from the parent and appear ONLY in the new substack; the
    /// parent now shows a substack tile in their place.
    ///
    /// Returns the new substack on success. All operations run in a single
    /// transaction so the parent is never left in a half-extracted state.
    @discardableResult
    func extractSubstackFromSelection(
        highlightIds: [String],
        inStack parentId: String
    ) -> Stack? {
        guard let dbQueue else { return nil }
        guard !highlightIds.isEmpty else { return nil }
        let now = Date().timeIntervalSince1970
        let child = Stack(
            id: UUID().uuidString,
            name: nil,
            stackDescription: nil,
            createdAt: now,
            updatedAt: now,
            isPinned: false
        )
        do {
            try dbQueue.write { db in
                try child.insert(db)

                // Preserve source ordering within the selection.
                let placeholders = Array(repeating: "?", count: highlightIds.count).joined(separator: ",")
                var fetchArgs: [DatabaseValueConvertible] = [parentId]
                fetchArgs.append(contentsOf: highlightIds)
                let orderedIds = try String.fetchAll(db, sql: """
                    SELECT highlightId FROM highlight_stack
                    WHERE stackId = ? AND highlightId IN (\(placeholders))
                    ORDER BY position ASC, addedAt DESC
                    """, arguments: StatementArguments(fetchArgs))

                for (index, hid) in orderedIds.enumerated() {
                    try db.execute(sql: """
                        INSERT INTO highlight_stack (stackId, highlightId, addedAt, position)
                        VALUES (?, ?, ?, ?)
                        """, arguments: [child.id, hid, now, index])
                }

                var deleteArgs: [DatabaseValueConvertible] = [parentId]
                deleteArgs.append(contentsOf: highlightIds)
                try db.execute(sql: """
                    DELETE FROM highlight_stack
                    WHERE stackId = ? AND highlightId IN (\(placeholders))
                    """, arguments: StatementArguments(deleteArgs))

                // Attach the new child as a substack of the parent. Land at
                // the top of the parent's substack section so it's visible
                // immediately where the items were.
                let minExisting = (try Int.fetchOne(db,
                    sql: "SELECT COALESCE(MIN(position), 0) - 1 FROM stack_stack WHERE parentStackId = ?",
                    arguments: [parentId]) ?? -1)
                try db.execute(sql: """
                    INSERT INTO stack_stack (parentStackId, childStackId, addedAt, position)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [parentId, child.id, now, minExisting])

                try db.execute(
                    sql: "UPDATE stack SET updatedAt = ? WHERE id = ?",
                    arguments: [now, parentId]
                )
            }
            NotificationCenter.default.post(
                name: .stackDataDidChange, object: nil,
                userInfo: ["stackId": parentId, "childStackId": child.id, "extractedSubstack": true]
            )
            return child
        } catch {
            CaptureLog.error("Failed to extract substack: \(error.localizedDescription)")
            return nil
        }
    }
}
