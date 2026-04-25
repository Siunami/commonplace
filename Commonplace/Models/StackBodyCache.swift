import Foundation

/// Snapshot of everything `StackBody` loads on mount. Cached so a
/// freshly-mounted view — e.g. after the user drags a tab into a new
/// pane and the SwiftUI hierarchy is rebuilt — can paint its first
/// frame with live data instead of the empty-state placeholders it
/// used to show until `.onAppear` finished querying the DB.
struct CachedStackBodyState {
    var stack: Stack
    var items: [Highlight]
    var substacks: [Stack]
    var noteCounts: [String: Int]
    var highlightNotes: [String: [HighlightNote]]
    var pinnedStack: Stack?
    var pinnedItemCount: Int
}

/// Process-wide cache of recent `StackBody` states, keyed by stack id.
/// Stale-while-revalidate: mount reads the cache, renders immediately,
/// then the normal `.onAppear` reload rewrites the entry with fresh
/// numbers. Not thread-safe — reads happen during SwiftUI view init
/// and writes from `reload()`, both of which run on the main thread.
final class StackBodyCache {
    static let shared = StackBodyCache()

    /// Bounded to keep memory predictable if the user churns through
    /// many stacks. LRU-by-last-touch. 40 is roughly "every stack
    /// you've opened this session on any plausible workspace."
    private let maxEntries = 40
    private var entries: [String: CachedStackBodyState] = [:]
    private var order: [String] = []

    private init() {}

    func cached(stackId: String) -> CachedStackBodyState? {
        guard let entry = entries[stackId] else { return nil }
        touch(stackId)
        return entry
    }

    func store(stackId: String, state: CachedStackBodyState) {
        entries[stackId] = state
        touch(stackId)
        evictIfNeeded()
    }

    func invalidate(stackId: String) {
        entries.removeValue(forKey: stackId)
        order.removeAll { $0 == stackId }
    }

    private func touch(_ stackId: String) {
        order.removeAll { $0 == stackId }
        order.append(stackId)
    }

    private func evictIfNeeded() {
        while order.count > maxEntries {
            let oldest = order.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }
}
