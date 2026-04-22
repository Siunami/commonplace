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
    /// Extended Open Graph metadata scraped from the page's <head>.
    /// `LPMetadataProvider` only surfaces title / hero / icon, so we do a
    /// secondary HTML fetch to pick up these richer fields.
    var ogDescription: String? = nil
    var ogAuthor: String? = nil
    /// `article:published_time` parsed into unix seconds.
    var ogPublishedAt: Double? = nil
    /// `og:type` (article / video / product / profile / …).
    var ogType: String? = nil

    var id: String { url }
    static let databaseTableName = "link_preview"

    var fetchedDate: Date { Date(timeIntervalSince1970: fetchedAt) }
    var publishedDate: Date? {
        ogPublishedAt.map { Date(timeIntervalSince1970: $0) }
    }
}
