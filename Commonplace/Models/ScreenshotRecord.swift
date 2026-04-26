import Foundation
import GRDB

struct ScreenshotRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    var id: Int64?
    var timestamp: Double
    var dayString: String
    var filePath: String
    var fileSize: Int64
    var displayId: String
    var ocrText: String?
    var captureType: String  // "full" | "region"

    // v2 metadata
    var windowTitle: String?
    var bundleId: String?
    var captureRect: String?
    var scaleFactor: Double?

    // v6 metadata
    var imageWidth: Int?
    var imageHeight: Int?

    // v27 multi-source attribution. JSON-encoded [ScreenshotSource]
    // listing every app with visible pixels in the capture region,
    // ordered by visible area descending. Nullable for compatibility
    // with paste-image flows and historical rows.
    var sources: String?

    static let databaseTableName = "screenshot"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var date: Date {
        Date(timeIntervalSince1970: timestamp)
    }
}
