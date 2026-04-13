import Foundation
import GRDB

struct RecordingRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    var id: Int64?
    var timestamp: Double
    var dayString: String
    var filePath: String
    var thumbnailPath: String
    var fileSize: Int64
    var duration: Double
    var displayId: String
    var captureType: String  // "full" | "region"
    var hasAudio: Bool
    var windowTitle: String?
    var bundleId: String?

    static let databaseTableName = "recording"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var date: Date {
        Date(timeIntervalSince1970: timestamp)
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedFileSize: String {
        Self.formatFileSize(fileSize)
    }

    static func formatFileSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }
}
