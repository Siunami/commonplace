import SwiftUI

/// Left sidebar for the Browse window.
/// Collections (tags) first, then type filters, then source apps.
struct CaptureFilterSidebar: View {
    let appFacets: [AppFacet]
    let allTags: [Tag]
    let tagCounts: [String: Int]
    let typeCounts: [String: Int]
    @Binding var selectedApp: String?
    @Binding var selectedFilter: CaptureFilter
    @Binding var selectedTagIds: Set<String>
    @Binding var searchText: String
    @Binding var showSettings: Bool
    let onSearch: () -> Void

    private var totalCount: Int {
        typeCounts.values.reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit { onSearch() }
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Collections (tags) — first, only those with items
                    if !allTags.isEmpty {
                        collectionsSection
                    }

                    // Type filters
                    typeSection

                    // Source apps
                    if !appFacets.isEmpty {
                        appSection
                    }
                }
                .padding(.vertical, 12)
            }

            Divider()

            Button(action: { showSettings.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: showSettings ? "xmark" : "gear")
                        .font(.caption)
                        .frame(width: 16)
                    Text(showSettings ? "Back" : "Settings")
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(showSettings ? .primary : .secondary)
        }
        .frame(width: 200)
    }

    // MARK: - Collections (Tags)

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Collections")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach(allTags) { tag in
                let count = tagCounts[tag.id] ?? 0
                HStack(spacing: 8) {
                    if let color = tag.color {
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 10, height: 10)
                            .frame(width: 16)
                    } else {
                        Image(systemName: "folder.fill")
                            .font(.caption)
                            .frame(width: 16)
                    }
                    Text(tag.name)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if tag.isPublished == true {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.blue.opacity(0.6))
                    }
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selectedTagIds.contains(tag.id) ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .foregroundStyle(selectedTagIds.contains(tag.id) ? .primary : .secondary)
                .onTapGesture { selectTag(tag.id) }
                .contextMenu {
                    if tag.isPublished == true {
                        Button("Unpublish") {
                            CollectionPublisher.shared.unpublishCollection(tag)
                        }
                        if !CollectionPublisher.shared.publicUrl.isEmpty {
                            let url = "\(CollectionPublisher.shared.publicUrl)/\(tag.slug)/index.html"
                            Button("Copy Web URL") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url, forType: .string)
                            }
                            let apiUrl = "\(CollectionPublisher.shared.publicUrl)/\(tag.slug)/manifest.json"
                            Button("Copy API URL") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(apiUrl, forType: .string)
                            }
                        }
                    } else {
                        Button("Publish") {
                            Task { await CollectionPublisher.shared.publishCollection(tag) }
                        }
                        .disabled(!CollectionPublisher.shared.isConfigured)
                    }
                }
            }
        }
    }

    private func selectTag(_ tagId: String) {
        if selectedTagIds == [tagId] {
            selectedTagIds = []
            return
        }
        selectedTagIds = [tagId]
        selectedFilter = .all
        selectedApp = nil
    }

    // MARK: - Type Filters

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Type")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach(CaptureFilter.allCases, id: \.self) { filter in
                let count: Int = if filter == .all {
                    totalCount
                } else if filter == .annotated {
                    typeCounts["_annotated"] ?? 0
                } else {
                    typeCounts[filter.highlightType ?? ""] ?? 0
                }

                HStack(spacing: 8) {
                    Image(systemName: filter.icon)
                        .font(.caption)
                        .frame(width: 16)
                    Text(filter.rawValue)
                        .font(.callout)
                    Spacer(minLength: 0)
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isTypeSelected(filter) ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .foregroundStyle(isTypeSelected(filter) ? .primary : .secondary)
                .onTapGesture { selectType(filter) }
            }
        }
    }

    private func isTypeSelected(_ filter: CaptureFilter) -> Bool {
        selectedFilter == filter && selectedApp == nil && selectedTagIds.isEmpty
    }

    private func selectType(_ filter: CaptureFilter) {
        selectedFilter = filter
        selectedApp = nil
        selectedTagIds = []
    }

    // MARK: - Source Apps

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Source App")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach(appFacets.prefix(15)) { facet in
                HStack(spacing: 8) {
                    appIcon(for: facet)
                        .frame(width: 16, height: 16)
                    Text(facet.appName)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(facet.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selectedApp == facet.appName ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .foregroundStyle(selectedApp == facet.appName ? .primary : .secondary)
                .onTapGesture { selectApp(facet.appName) }
            }
        }
    }

    private func selectApp(_ appName: String) {
        if selectedApp == appName {
            selectedApp = nil
            selectedFilter = .all
            selectedTagIds = []
            return
        }
        selectedApp = appName
        selectedFilter = .all
        selectedTagIds = []
    }

    @ViewBuilder
    private func appIcon(for facet: AppFacet) -> some View {
        if let bundleId = facet.bundleId,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - CaptureFilter (shared enum)

enum CaptureFilter: String, CaseIterable {
    case all = "All"
    case annotated = "Annotated"
    case screenshots = "Screenshots"
    case recordings = "Recordings"
    case copies = "Copies"
    case files = "Files"

    var highlightType: String? {
        switch self {
        case .all, .annotated: return nil
        case .screenshots: return "screenshot"
        case .recordings: return "recording"
        case .copies: return "copy"
        case .files: return "file"
        }
    }

    /// True when this filter requires note-based filtering (not type-based).
    var isAnnotatedFilter: Bool { self == .annotated }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .annotated: return "text.bubble"
        case .screenshots: return "camera.viewfinder"
        case .recordings: return "video.fill"
        case .copies: return "doc.on.clipboard"
        case .files: return "doc.fill"
        }
    }
}

// MARK: - Color hex helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0.5; g = 0.5; b = 0.5
        }
        self.init(red: r, green: g, blue: b)
    }
}
