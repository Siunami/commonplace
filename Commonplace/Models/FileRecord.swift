import Foundation
import GRDB

struct FileRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    var id: Int64?
    var timestamp: Double
    var dayString: String
    var filePath: String
    var fileName: String
    var fileSize: Int64
    var uti: String?
    var contentType: String?
    var thumbnailPath: String?
    var sourceFolder: String
    var creationDate: Double?
    var fileExtension: String?
    var pageCount: Int?
    /// Source URL for files that came from a copied link (URLFileDownloader).
    /// Used to dedup re-copies of the same URL. Nil for drag-and-drop / folder-watched files.
    var originalUrl: String? = nil
    /// Intrinsic image/video pixel dimensions, captured at ingest. Enables
    /// masonry cards to reserve aspect-ratio space before the thumbnail
    /// loads, so neighbour cards don't shift when it arrives.
    var imageWidth: Int? = nil
    var imageHeight: Int? = nil

    static let databaseTableName = "file_record"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var date: Date { Date(timeIntervalSince1970: timestamp) }

    var formattedFileSize: String {
        RecordingRecord.formatFileSize(fileSize)
    }
}
