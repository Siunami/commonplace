import SwiftUI

struct AppFacetSidebar: View {
    let facets: [AppFacet]
    @Binding var selectedApp: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Source Apps")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    // "Show all" row
                    Button(action: { selectedApp = nil }) {
                        HStack {
                            Image(systemName: "square.grid.2x2")
                                .font(.caption)
                                .frame(width: 20)
                            Text("All Apps")
                                .font(.callout)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedApp == nil ? Color.accentColor.opacity(0.1) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedApp == nil ? .primary : .secondary)

                    ForEach(facets) { facet in
                        Button(action: { selectedApp = facet.appName }) {
                            HStack {
                                appIcon(for: facet)
                                    .frame(width: 20, height: 20)
                                Text(facet.appName)
                                    .font(.callout)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(facet.count)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedApp == facet.appName ? Color.accentColor.opacity(0.1) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selectedApp == facet.appName ? .primary : .secondary)
                    }
                }
            }
        }
        .frame(width: 200)
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
