import Foundation
import GRDB

struct PageVisit: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var url: String
    var title: String?
    var domain: String?
    var sourceApp: String?
    var bundleId: String?
    var startedAt: Double
    var endedAt: Double?
    var duration: Double?
    var isBookmarked: Bool
    var captureCount: Int

    static let databaseTableName = "page_visit"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var startDate: Date { Date(timeIntervalSince1970: startedAt) }
    var endDate: Date? { endedAt.map { Date(timeIntervalSince1970: $0) } }

    var formattedDuration: String {
        guard let d = duration, d > 0 else { return "< 1s" }
        if d < 60 { return "\(Int(d))s" }
        if d < 3600 { return "\(Int(d / 60))m" }
        let h = Int(d / 3600)
        let m = Int((d.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(h)h \(m)m"
    }

    /// Extract domain from a URL string, stripping "www." prefix.
    static func extractDomain(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
