import Foundation
import GRDB

struct Stack: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    var id: String
    var name: String?
    var stackDescription: String?
    var createdAt: Double
    var updatedAt: Double
    var isPinned: Bool

    // v26 origin metadata — populated when the stack is created from a
    // workspace canvas selection. Snapshot is JSON: [{cardId, x, y, w, h}]
    // frozen at create time so "View origin arrangement" can return to
    // the moment the relation was first seen, even if the cards are
    // moved afterwards.
    var originWorkspaceId: String? = nil
    var originArrangementSnapshot: String? = nil

    static let databaseTableName = "stack"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case stackDescription = "description"
        case createdAt
        case updatedAt
        case isPinned
        case originWorkspaceId
        case originArrangementSnapshot
    }

    var isNamed: Bool {
        guard let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !n.isEmpty
    }
}

struct HighlightStack: Codable, FetchableRecord, PersistableRecord {
    var stackId: String
    var highlightId: String
    var addedAt: Double
    static let databaseTableName = "highlight_stack"
}
