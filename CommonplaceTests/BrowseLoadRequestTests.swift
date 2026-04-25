import Testing
@testable import Commonplace

struct BrowseLoadRequestTests {

    @Test func normalizesSearchText() {
        let request = BrowseLoadRequest(
            searchText: "  launch notes  \n",
            activeFilters: .init()
        )

        #expect(request.normalizedSearchText == "launch notes")
        #expect(request.hasActiveSearch)
    }

    @Test func totalBrowseHighlightsIgnoresSyntheticBuckets() {
        let counts = [
            "copy": 4,
            "screenshot": 3,
            "_annotated": 2,
        ]

        #expect(counts.totalBrowseHighlights == 7)
    }

    @Test func reloadBehaviorTracksSearchScope() {
        let plainRequest = BrowseLoadRequest(
            searchText: "",
            activeFilters: .init()
        )
        let searchRequest = BrowseLoadRequest(
            searchText: "meeting",
            activeFilters: .init()
        )

        #expect(!plainRequest.shouldReloadOnHighlightMutation(change: "notes"))
        #expect(searchRequest.shouldReloadOnHighlightMutation(change: "notes"))
        #expect(searchRequest.shouldReloadOnHighlightMutation(change: "userNote"))
        #expect(!searchRequest.shouldReloadOnHighlightMutation(change: "sourceApp"))
    }
}
