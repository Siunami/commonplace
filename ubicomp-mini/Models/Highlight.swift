import Foundation
import GRDB

struct Highlight: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    var id: String
    var timestamp: Double
    var contentText: String
    var sourceApp: String?
    var sourceUrl: String?
    var userNote: String?
    var highlightType: String  // "copy" | "highlight" | "screenshot" | "recording" | "note" | "file"
    var screenshotId: Int64?
    var recordingId: Int64?
    var fileId: Int64?

    // v2 metadata
    var windowTitle: String?
    var bundleId: String?
    var contentHash: String?
    var documentPath: String?
    var contentType: String?

    // v6 environment metadata
    var displayName: String?
    var displayResolution: String?
    var appearanceMode: String?
    var wifiNetwork: String?

    static let databaseTableName = "highlight"

    var date: Date { Date(timeIntervalSince1970: timestamp) }
}
