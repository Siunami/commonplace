import Testing
@testable import Commonplace

struct BrowseLoadRequestTests {

    @Test func normalizesSearchText() {
        let request = BrowseLoadRequest(
            searchText: "  launch notes  \n",
            selectedFilter: .all,
            selectedApp: nil,
            selectedTagIds: []
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

    @Test func reloadBehaviorTracksSearchAndTagScopes() {
        let tagScopedRequest = BrowseLoadRequest(
            searchText: "",
            selectedFilter: .all,
            selectedApp: nil,
            selectedTagIds: ["tag-1"]
        )
        let searchRequest = BrowseLoadRequest(
            searchText: "meeting",
            selectedFilter: .all,
            selectedApp: nil,
            selectedTagIds: []
        )

        #expect(tagScopedRequest.shouldReloadOnHighlightMutation(change: "tags"))
        #expect(!tagScopedRequest.shouldReloadOnHighlightMutation(change: "notes"))
        #expect(searchRequest.shouldReloadOnHighlightMutation(change: "notes"))
        #expect(searchRequest.shouldReloadOnHighlightMutation(change: "userNote"))
        #expect(!searchRequest.shouldReloadOnHighlightMutation(change: "sourceApp"))
    }
}
