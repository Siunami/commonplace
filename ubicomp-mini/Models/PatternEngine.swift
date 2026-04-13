import Foundation

/// Pure computation over arrays of Highlight — no side effects, fully testable.
enum PatternEngine {

    // MARK: - Context Clustering

    /// Groups consecutive highlights sharing the same sourceApp + URL domain within a 60-minute gap.
    /// Input must be sorted by timestamp ASC. Single-item clusters are filtered out.
    static func clusterByContext(_ highlights: [Highlight]) -> [ContextCluster] {
        guard !highlights.isEmpty else { return [] }

        var clusters: [ContextCluster] = []
        var currentGroup: [Highlight] = [highlights[0]]
        var currentKey = contextKey(for: highlights[0])

        for i in 1..<highlights.count {
            let h = highlights[i]
            let key = contextKey(for: h)
            let gap = h.timestamp - highlights[i - 1].timestamp

            if key == currentKey && gap <= 3600 { // 60 minutes
                currentGroup.append(h)
            } else {
                if currentGroup.count > 1 {
                    clusters.append(makeCluster(from: currentGroup))
                }
                currentGroup = [h]
                currentKey = key
            }
        }
        // Close final group
        if currentGroup.count > 1 {
            clusters.append(makeCluster(from: currentGroup))
        }

        return clusters
    }

    private static func contextKey(for h: Highlight) -> String {
        let app = h.sourceApp ?? "Unknown"
        let domain = extractDomain(from: h.sourceUrl)
        return "\(app)|\(domain ?? "")"
    }

    private static func extractDomain(from urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty,
              let url = URL(string: urlString),
              let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func makeCluster(from highlights: [Highlight]) -> ContextCluster {
        let app = highlights[0].sourceApp ?? "Unknown"
        let domain = extractDomain(from: highlights[0].sourceUrl)
        let dates = highlights.map(\.date)
        return ContextCluster(
            id: "\(app)|\(domain ?? "")|\(highlights[0].id)",
            sourceApp: app,
            domain: domain,
            highlights: highlights,
            timeRange: dates.min()! ... dates.max()!
        )
    }

    // MARK: - Session Detection

    /// Splits highlights into sessions separated by 30+ minute gaps.
    /// Input must be sorted by timestamp ASC. Single-capture sessions are filtered out.
    static func detectSessions(_ highlights: [Highlight]) -> [WorkSession] {
        guard !highlights.isEmpty else { return [] }

        var sessions: [WorkSession] = []
        var currentSession: [Highlight] = [highlights[0]]

        for i in 1..<highlights.count {
            let gap = highlights[i].timestamp - highlights[i - 1].timestamp
            if gap > 1800 { // 30 minutes
                if currentSession.count >= 2 {
                    sessions.append(makeSession(from: currentSession))
                }
                currentSession = [highlights[i]]
            } else {
                currentSession.append(highlights[i])
            }
        }
        // Close final session
        if currentSession.count >= 2 {
            sessions.append(makeSession(from: currentSession))
        }

        return sessions
    }

    private static func makeSession(from highlights: [Highlight]) -> WorkSession {
        let dates = highlights.map(\.date)

        // Count captures per app
        var appCounts: [String: Int] = [:]
        for h in highlights {
            let app = h.sourceApp ?? "Unknown"
            appCounts[app, default: 0] += 1
        }
        let summary = appCounts
            .map { (app: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        return WorkSession(
            id: UUID().uuidString,
            highlights: highlights,
            timeRange: dates.min()! ... dates.max()!,
            appSummary: summary
        )
    }

    // MARK: - Linked Capture Detection

    /// Detects captures from the same app within 5 seconds with different types.
    /// Input must be sorted by timestamp ASC.
    /// Returns linked captures and the set of highlight IDs that were consumed.
    static func detectLinkedCaptures(_ highlights: [Highlight]) -> ([LinkedCapture], Set<String>) {
        var linked: [LinkedCapture] = []
        var consumedIds = Set<String>()

        for (i, h) in highlights.enumerated() {
            guard !consumedIds.contains(h.id) else { continue }

            var matches: [Highlight] = []
            for j in (i + 1)..<highlights.count {
                let other = highlights[j]
                guard other.timestamp - h.timestamp <= 5.0 else { break }
                guard !consumedIds.contains(other.id) else { continue }

                if other.sourceApp == h.sourceApp &&
                   other.highlightType != h.highlightType {
                    matches.append(other)
                }
            }

            if !matches.isEmpty {
                consumedIds.insert(h.id)
                for m in matches { consumedIds.insert(m.id) }
                linked.append(LinkedCapture(
                    id: h.id,
                    primary: h,
                    linked: matches,
                    sourceApp: h.sourceApp ?? "Unknown"
                ))
            }
        }

        return (linked, consumedIds)
    }
}
