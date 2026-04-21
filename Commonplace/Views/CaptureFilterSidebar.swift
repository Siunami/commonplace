import SwiftUI

/// Left sidebar for the Browse window.
/// Stacks, type filters, and source apps — category/tag UI is hidden for now.
struct CaptureFilterSidebar: View {
    let appFacets: [AppFacet]
    let typeCounts: [String: Int]
    @Binding var selectedApp: String?
    @Binding var selectedFilter: CaptureFilter
    @Binding var showSettings: Bool
    @Binding var showStacks: Bool

    private var totalCount: Int {
        typeCounts.totalBrowseHighlights
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Stacks — provisional, lightweight grouping
                    stacksRow

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

            Button(action: { showSettings.toggle(); if showSettings { showStacks = false } }) {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                        .font(.caption)
                        .frame(width: 16)
                    Text("Settings")
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(showSettings ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(showSettings ? .primary : .secondary)
        }
        .frame(width: 200)
    }

    // MARK: - Stacks

    private var stacksRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.caption)
                .frame(width: 16)
            Text("Stacks")
                .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(showStacks ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .foregroundStyle(showStacks ? .primary : .secondary)
        .onTapGesture { selectStacks() }
    }

    private func selectStacks() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        showStacks.toggle()
        if showStacks {
            showSettings = false
            selectedFilter = .all
            selectedApp = nil
        }
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
                } else if filter == .links {
                    typeCounts["_links"] ?? 0
                } else if filter == .videos {
                    typeCounts["_videos"] ?? 0
                } else if filter == .files {
                    typeCounts["_filesNoVideo"] ?? 0
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
        !showStacks
            && !showSettings
            && selectedFilter == filter
            && selectedApp == nil
    }

    private func selectType(_ filter: CaptureFilter) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        selectedFilter = filter
        selectedApp = nil
        showSettings = false
        showStacks = false
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
        NSApp.keyWindow?.makeFirstResponder(nil)
        if selectedApp == appName {
            selectedApp = nil
            selectedFilter = .all
            return
        }
        selectedApp = appName
        selectedFilter = .all
        showSettings = false
        showStacks = false
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

// MARK: - AppFacet

struct AppFacet: Identifiable {
    let appName: String
    let bundleId: String?
    let count: Int

    var id: String { appName }
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
