import Foundation

// MARK: - Context Cluster

/// A group of captures sharing the same sourceApp + URL domain within a time window.
struct ContextCluster: Identifiable {
    let id: String
    let sourceApp: String
    let domain: String?
    let highlights: [Highlight]
    let timeRange: ClosedRange<Date>

    var displayTitle: String {
        let count = highlights.count
        if let domain, !domain.isEmpty {
            return "\(count) captures from \(sourceApp) — \(domain)"
        }
        return "\(count) captures from \(sourceApp)"
    }
}

// MARK: - Work Session

/// A block of continuous activity (no gap > 30 min between consecutive captures).
struct WorkSession: Identifiable {
    let id: String
    let highlights: [Highlight]
    let timeRange: ClosedRange<Date>
    let appSummary: [(app: String, count: Int)]

    var label: String {
        let hour = Calendar.current.component(.hour, from: timeRange.lowerBound)
        let timeOfDay: String
        switch hour {
        case 6..<12:  timeOfDay = "Morning"
        case 12..<17: timeOfDay = "Afternoon"
        case 17..<21: timeOfDay = "Evening"
        default:      timeOfDay = "Late night"
        }
        let distinctApps = appSummary.count
        return "\(timeOfDay) session: \(highlights.count) captures across \(distinctApps) app\(distinctApps == 1 ? "" : "s")"
    }
}

// MARK: - Linked Capture

/// Two or more captures from the same app within a few seconds, merged for display.
struct LinkedCapture: Identifiable {
    let id: String
    let primary: Highlight
    let linked: [Highlight]
    let sourceApp: String

    var allHighlights: [Highlight] {
        [primary] + linked
    }
}

// MARK: - App Facet

/// Summary row for the source-app sidebar.
struct AppFacet: Identifiable {
    var id: String { appName }
    let appName: String
    let bundleId: String?
    let count: Int
}
