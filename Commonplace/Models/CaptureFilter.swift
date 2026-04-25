import Foundation

/// Coarse content-type filter applied to the All view masonry. The cases
/// are user-facing — `rawValue` is shown as the chip label. `.all` is the
/// default; the others narrow to a single content type or to a virtual
/// grouping (annotated, links, videos, files-excluding-videos).
enum CaptureFilter: String, CaseIterable {
    case all = "All"
    case annotated = "Annotated"
    case screenshots = "Screenshots"
    case videos = "Videos"
    case links = "Links"
    case copies = "Copies"
    case files = "Files"

    var highlightType: String? {
        switch self {
        case .all, .annotated, .links, .videos: return nil
        case .screenshots: return "screenshot"
        case .copies: return "copy"
        case .files: return "file"
        }
    }

    var isAnnotatedFilter: Bool { self == .annotated }
    var isLinksFilter: Bool { self == .links }
    var isVideosFilter: Bool { self == .videos }
    /// Files filter excludes videos — they have their own category.
    var isFilesExcludingVideos: Bool { self == .files }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .annotated: return "text.bubble"
        case .screenshots: return "camera.viewfinder"
        case .videos: return "video.fill"
        case .links: return "link"
        case .copies: return "doc.on.clipboard"
        case .files: return "doc.fill"
        }
    }
}

/// One row in the source-app facet list — used by the All view's app
/// picker to surface which apps have captures plus their counts.
struct AppFacet: Identifiable {
    let appName: String
    let bundleId: String?
    let count: Int

    var id: String { appName }
}

/// Active filter set for the All view masonry. Each facet allows multiple
/// values; values within one facet are OR'd (a row matches if it satisfies
/// any selected value), and facets are AND'd together (a row must
/// satisfy every facet that has at least one value selected).
///
/// Example: `types = [.screenshots, .videos]`, `apps = ["Slack"]` →
/// "screenshots OR videos, captured from Slack."
///
/// Empty across the board means no filtering.
struct ActiveFilters: Equatable {
    var types: Set<CaptureFilter> = []
    var apps: Set<String> = []

    var isEmpty: Bool { types.isEmpty && apps.isEmpty }
}
