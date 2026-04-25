import SwiftUI
import AppKit

/// Compact filter strip mounted at the top of the All view body. Renders
/// each active filter as a removable pill (type or app), followed by a
/// single "+" trigger that opens a unified multi-select popover. Filters
/// AND across facets, OR within a facet — see `ActiveFilters` for the
/// data model and `BrowseFilterSQL` for the query side.
/// Identifies one row in the add-filter popover so the candidate-count
/// callback can hand back a "count if you added this" without each call
/// site having to rebuild the test `ActiveFilters` itself.
enum CandidateFilter {
    case type(CaptureFilter)
    case app(String)
}

struct AllViewFilterBar: View {
    @Binding var activeFilters: ActiveFilters
    let appFacets: [AppFacet]
    let typeCounts: [String: Int]
    /// Returns how many rows would match if the given candidate were added
    /// to `activeFilters` (current filters AND the candidate). The popover
    /// uses this to hide candidates that would zero out the result set —
    /// "everything is AND" semantics make stacking incompatible filters
    /// produce empty pages, so we prune them up front instead.
    let candidateCount: (CandidateFilter) -> Int

    @State private var isAddPickerPresented = false

    /// The set of types offerable in the picker — `.all` is the absence of
    /// filtering, not a value, so it never appears as a pill.
    private var pickableTypes: [CaptureFilter] {
        CaptureFilter.allCases.filter { $0 != .all }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pillModels) { pill in
                    FilterPill(model: pill)
                }
                if !activeFilters.isEmpty {
                    clearAllButton
                }
                addFilterTrigger
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(UITokens.surfaceCard.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(UITokens.surfaceBorder)
                .frame(height: 0.5)
        }
    }

    private var clearAllButton: some View {
        Button {
            activeFilters = .init()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 10))
                Text("Clear")
                    .font(.system(size: 11, weight: .regular))
            }
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Clear all filters")
    }

    // MARK: - Pill models

    /// Snapshot of every active filter as a pill, ordered types-then-apps
    /// so the strip reads consistently across renders.
    private var pillModels: [FilterPillModel] {
        var pills: [FilterPillModel] = []
        let orderedTypes = activeFilters.types.sorted { $0.rawValue < $1.rawValue }
        for type in orderedTypes {
            pills.append(FilterPillModel(
                id: "type:\(type.rawValue)",
                icon: .symbol(type.icon),
                label: type.rawValue,
                onRemove: { activeFilters.types.remove(type) }
            ))
        }
        let orderedApps = activeFilters.apps.sorted()
        for app in orderedApps {
            let bundleId = appFacets.first(where: { $0.appName == app })?.bundleId
            let appIcon = bundleId.flatMap { AppIconResolver.icon(forBundleId: $0) }
            pills.append(FilterPillModel(
                id: "app:\(app)",
                icon: appIcon.map(FilterPillIcon.appIcon) ?? .symbol("app"),
                label: app,
                onRemove: { activeFilters.apps.remove(app) }
            ))
        }
        return pills
    }

    // MARK: - Add trigger

    private var addFilterTrigger: some View {
        Button {
            NSApp.keyWindow?.makeFirstResponder(nil)
            isAddPickerPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("Filter")
                    .font(.system(size: 11, weight: .regular))
            }
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(UITokens.surfaceBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isAddPickerPresented, arrowEdge: .bottom) {
            AddFilterPopover(
                pickableTypes: pickableTypes,
                appFacets: appFacets,
                activeFilters: $activeFilters,
                candidateCount: candidateCount
            )
        }
    }
}

// MARK: - Pill

private enum FilterPillIcon {
    case symbol(String)
    case appIcon(NSImage)
}

private struct FilterPillModel: Identifiable {
    let id: String
    let icon: FilterPillIcon
    let label: String
    let onRemove: () -> Void
}

private struct FilterPill: View {
    let model: FilterPillModel
    @State private var isCloseHovered = false

    var body: some View {
        HStack(spacing: 5) {
            iconView
                .frame(width: 14, height: 14)
            Text(model.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Button(action: model.onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(isCloseHovered ? .primary : .secondary)
                    .frame(width: 14, height: 14)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isCloseHovered ? 0.10 : 0))
                    )
            }
            .buttonStyle(.plain)
            .help("Remove filter")
            .onHover { isCloseHovered = $0 }
        }
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.5)
        )
        .fixedSize()
    }

    @ViewBuilder
    private var iconView: some View {
        switch model.icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
        case .appIcon(let image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
        }
    }
}

// MARK: - Add filter popover

/// Multi-select popover surfaced by the "+" trigger. Each row is a
/// candidate filter — selected rows show a checkmark; unselected rows
/// are HIDDEN when adding them would zero out the result set under the
/// current `activeFilters`. Refined counts are recomputed whenever the
/// active filter set changes (typically after the user toggles a row),
/// so the visible options shrink as constraints stack.
private struct AddFilterPopover: View {
    let pickableTypes: [CaptureFilter]
    let appFacets: [AppFacet]
    @Binding var activeFilters: ActiveFilters
    let candidateCount: (CandidateFilter) -> Int

    @State private var typeCounts: [CaptureFilter: Int] = [:]
    @State private var appCounts: [String: Int] = [:]

    private var visibleTypes: [CaptureFilter] {
        pickableTypes.filter { type in
            // Selected rows always render so the user can deselect them.
            activeFilters.types.contains(type) || (typeCounts[type] ?? 0) > 0
        }
    }

    private var visibleApps: [AppFacet] {
        appFacets.prefix(20).filter { facet in
            activeFilters.apps.contains(facet.appName) || (appCounts[facet.appName] ?? 0) > 0
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if !visibleTypes.isEmpty {
                    sectionHeader("Type")
                    ForEach(visibleTypes, id: \.self) { type in
                        AddFilterRow(
                            icon: .symbol(type.icon),
                            label: type.rawValue,
                            count: typeCounts[type] ?? 0,
                            isSelected: activeFilters.types.contains(type),
                            onToggle: { toggle(type) }
                        )
                    }
                }

                if !visibleApps.isEmpty {
                    sectionHeader("App")
                    ForEach(visibleApps) { facet in
                        let appIcon = facet.bundleId.flatMap { AppIconResolver.icon(forBundleId: $0) }
                        AddFilterRow(
                            icon: appIcon.map(FilterPillIcon.appIcon) ?? .symbol("app"),
                            label: facet.appName,
                            count: appCounts[facet.appName] ?? 0,
                            isSelected: activeFilters.apps.contains(facet.appName),
                            onToggle: { toggle(app: facet.appName) }
                        )
                    }
                }

                if visibleTypes.isEmpty && visibleApps.isEmpty {
                    Text("No further filters apply.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .padding(6)
        }
        .frame(width: 240, height: popoverHeight)
        .onAppear { recomputeCounts() }
        .onChange(of: activeFilters) { _, _ in recomputeCounts() }
    }

    private var popoverHeight: CGFloat {
        let baseRows = visibleTypes.count + visibleApps.count
        let estimated = CGFloat(baseRows) * 26 + 60   // rows + section headers + padding
        return min(420, max(80, estimated))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func recomputeCounts() {
        var nextTypeCounts: [CaptureFilter: Int] = [:]
        for type in pickableTypes {
            nextTypeCounts[type] = candidateCount(.type(type))
        }
        typeCounts = nextTypeCounts

        var nextAppCounts: [String: Int] = [:]
        for facet in appFacets.prefix(20) {
            nextAppCounts[facet.appName] = candidateCount(.app(facet.appName))
        }
        appCounts = nextAppCounts
    }

    private func toggle(_ type: CaptureFilter) {
        if activeFilters.types.contains(type) {
            activeFilters.types.remove(type)
        } else {
            activeFilters.types.insert(type)
        }
    }

    private func toggle(app: String) {
        if activeFilters.apps.contains(app) {
            activeFilters.apps.remove(app)
        } else {
            activeFilters.apps.insert(app)
        }
    }
}

private struct AddFilterRow: View {
    let icon: FilterPillIcon
    let label: String
    let count: Int
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                checkbox
                iconView
                    .frame(width: 16, height: 16)
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.6))
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        case .appIcon(let image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
        }
    }

    private var checkbox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.5),
                    lineWidth: 1
                )
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .frame(width: 14, height: 14)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isHovered {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.06))
        } else {
            Color.clear
        }
    }
}

// MARK: - App icon resolver

/// Resolves a bundle id to its on-disk app icon. Cache lives for the
/// process lifetime — app icons rarely change, the lookup hits NSWorkspace
/// (and potentially the disk via LSCopyApplicationURLsForBundleIdentifier),
/// and the popover redraws on every hover so re-querying every render
/// would be wasteful.
private enum AppIconResolver {
    private static var cache: [String: NSImage] = [:]

    static func icon(forBundleId bundleId: String) -> NSImage? {
        if let cached = cache[bundleId] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleId] = icon
        return icon
    }
}
