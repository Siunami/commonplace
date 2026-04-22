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

    // v21 per-app enricher output (JSON-encoded [SourceContextEntry])
    var sourceContext: String?

    static let databaseTableName = "highlight"

    var date: Date { Date(timeIntervalSince1970: timestamp) }

    var isURLCopy: Bool {
        if contentType == "url" { return true }
        let trimmed = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else { return false }
        return !trimmed.contains(" ") && !trimmed.contains("\n")
    }

    var decodedSourceContext: [SourceContextEntry] {
        guard let raw = sourceContext, !raw.isEmpty,
              let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SourceContextEntry].self, from: data)) ?? []
    }
}
