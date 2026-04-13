import Foundation
import GRDB

struct LinkPreview: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    var url: String
    var title: String?
    var siteName: String?
    var imagePath: String?
    var faviconPath: String?
    var fetchedAt: Double
    var fetchError: String?

    var id: String { url }
    static let databaseTableName = "link_preview"

    var fetchedDate: Date { Date(timeIntervalSince1970: fetchedAt) }
}
