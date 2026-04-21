import Foundation
import GRDB

struct Stack: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    var id: String
    var name: String?
    var stackDescription: String?
    var createdAt: Double
    var updatedAt: Double
    var isPinned: Bool

    static let databaseTableName = "stack"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case stackDescription = "description"
        case createdAt
        case updatedAt
        case isPinned
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
