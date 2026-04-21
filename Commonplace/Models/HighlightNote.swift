import Foundation
import GRDB

struct HighlightNote: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String
    var highlightId: String
    var body: String
    var createdAt: Double
    var timestampSeconds: Double?

    static let databaseTableName = "highlight_note"

    var date: Date { Date(timeIntervalSince1970: createdAt) }
}
