import Foundation
import SwiftUI
import Observation

/// Per-tab state container for `.allView` tabs. Each `.allView` tab owns
/// one of these so typing in one pane's search bar doesn't leak into
/// another, splitting a pane doesn't duplicate state, and a freshly
/// opened tab starts with an empty query / full filter set / no scope
/// — just like browser tabs.
///
/// Holds both user-driven inputs (searchText, activeFilters) and the
/// derived result set (highlights, counts, pagination state). BrowseView
/// hosts a `[UUID: AllViewTabModel]` keyed by tab id and looks up the
/// right model when rendering each tab. The model is marked `@Observable`
/// (Swift Observation) so views bound to `@Bindable model` only
/// re-evaluate for the specific fields they read — partial invalidation
/// instead of ObservableObject's whole-view refresh.
@Observable
final class AllViewTabModel {
    // MARK: - User-driven inputs

    /// Free-text search query. Empty = no search.
    var searchText: String = ""

    /// Type/app filter state. Empty = no filter.
    var activeFilters: ActiveFilters = .init()

    // MARK: - Paginated result set

    /// Current loaded slice of highlights for this tab's query. Grows as
    /// the user scrolls near the bottom and `loadCaptures(reset: false)`
    /// fires. Reset to a fresh batch when inputs change.
    var highlights: [Highlight] = []
    var highlightsOffset: Int = 0
    var totalCaptureCount: Int = 0
    var hasMore: Bool = false
    var isReloadingCaptures: Bool = false

    // MARK: - Derived batches (populated alongside `highlights` in loadCaptures)

    var noteCounts: [String: Int] = [:]
    var highlightNotes: [String: [HighlightNote]] = [:]
    var aspectRatios: [String: CGFloat] = [:]
    var sourceLinks: [String: CardSourceLink] = [:]
    var fileRecords: [Int64: FileRecord] = [:]

    // MARK: - Facets / sidebar inputs (filter by this tab's current query)

    var appFacets: [AppFacet] = []
    var typeCounts: [String: Int] = [:]

    // MARK: - Navigation / focus state

    /// Set when the user jumps to a specific capture from a detail view
    /// or the capture-event timeline. Scoped to this tab so one tab's
    /// jump doesn't scroll another.
    var focusedHighlightId: String? = nil
    var isWindowedMode = false
    var jumpFlashId: String? = nil
    var isScrolledAwayFromTop = false

    // MARK: - In-flight work

    var loadGeneration: Int = 0
    var loadTask: Task<Void, Never>? = nil
    var sidebarRefreshGeneration: Int = 0
    var sidebarRefreshTask: Task<Void, Never>? = nil
    var jumpFlashTask: Task<Void, Never>? = nil

    // MARK: - Derivations

    /// Pure function of the user inputs — the query this tab sends to
    /// `DatabaseManager.browseHighlights(_:offset:limit:)` etc.
    var browseLoadRequest: BrowseLoadRequest {
        BrowseLoadRequest(searchText: searchText, activeFilters: activeFilters)
    }

    var emptyStateTitle: String {
        if browseLoadRequest.hasActiveSearch {
            return "No matching captures"
        }
        if browseLoadRequest.hasActiveFilters {
            return "No captures match this filter"
        }
        return "No captures yet"
    }

    var emptyStateSubtitle: String? {
        if browseLoadRequest.hasActiveSearch || browseLoadRequest.hasActiveFilters {
            return "Clear the search or adjust the current filters."
        }
        return nil
    }
}
