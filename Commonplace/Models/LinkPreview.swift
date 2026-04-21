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
    /// Hero image pixel dimensions, captured at save time. Enables the
    /// link card to reserve aspect-ratio space before the JPEG loads.
    var imageWidth: Int? = nil
    var imageHeight: Int? = nil

    var id: String { url }
    static let databaseTableName = "link_preview"

    var fetchedDate: Date { Date(timeIntervalSince1970: fetchedAt) }
}
