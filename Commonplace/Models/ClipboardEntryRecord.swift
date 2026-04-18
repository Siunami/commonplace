import Foundation
import GRDB

struct ClipboardEntryRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String
    var timestamp: Double
    var content: String
    var sourceApp: String?

    // v2 metadata
    var windowTitle: String?
    var bundleId: String?
    var sourceUrl: String?
    var clipboardTypes: String?
    var contentHash: String?
    var documentPath: String?
    var contentType: String?

    static let databaseTableName = "clipboard_entry"

    var date: Date { Date(timeIntervalSince1970: timestamp) }
}
