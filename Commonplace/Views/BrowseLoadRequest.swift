import Foundation

struct BrowseLoadRequest: Equatable {
    let searchText: String
    let selectedFilter: CaptureFilter
    let selectedApp: String?

    var normalizedSearchText: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var hasActiveSearch: Bool {
        normalizedSearchText != nil
    }

    var hasActiveFilters: Bool {
        selectedFilter != .all || selectedApp != nil
    }

    func shouldReloadOnHighlightMutation(change: String) -> Bool {
        if hasActiveSearch {
            return change == "notes" || change == "userNote"
        }
        return false
    }
}

extension Dictionary where Key == String, Value == Int {
    var totalBrowseHighlights: Int {
        reduce(into: 0) { total, entry in
            guard !entry.key.hasPrefix("_") else { return }
            total += entry.value
        }
    }
}
