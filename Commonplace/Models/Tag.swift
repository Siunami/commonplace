import Foundation
import GRDB

struct Tag: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    var id: String
    var name: String
    var color: String?
    var emoji: String?
    var createdAt: Double
    var updatedAt: Double
    var isPublished: Bool?
    static let databaseTableName = "tag"
    var date: Date { Date(timeIntervalSince1970: createdAt) }

    var slug: String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}

struct HighlightTag: Codable, FetchableRecord, PersistableRecord {
    var tagId: String
    var highlightId: String
    var createdAt: Double
    static let databaseTableName = "highlight_tag"
}
