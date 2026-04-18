import Foundation

struct BrowseLoadRequest: Equatable {
    let searchText: String
    let selectedFilter: CaptureFilter
    let selectedApp: String?
    let selectedTagIds: Set<String>

    var normalizedSearchText: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var selectedTagId: String? {
        selectedTagIds.sorted().first
    }

    var hasActiveSearch: Bool {
        normalizedSearchText != nil
    }

    var hasActiveFilters: Bool {
        selectedFilter != .all || selectedApp != nil || selectedTagId != nil
    }

    func shouldReloadOnHighlightMutation(change: String) -> Bool {
        if hasActiveSearch {
            return change == "tags" || change == "notes" || change == "userNote"
        }
        return change == "tags" && selectedTagId != nil
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
