import SwiftUI

/// A tile representing a Workspace. Mirrors `StackCard` geometry (220pt
/// fixed width, 10pt radius, surface chrome) so workspaces and stacks
/// read as siblings in the chooser. Where StackCard shows a 6-slot
/// mosaic of children, WorkspaceCard shows a position-aware miniature
/// of the canvas — every placement rendered as a scaled rectangle at
/// its world-coord position, tinted by highlight type.
struct WorkspaceCard: View {
    let workspace: Workspace
    var onOpen: (() -> Void)? = nil

    @State private var placements: [DatabaseManager.PlacementMiniature] = []
    @State private var totalCount: Int = 0

    private let db = DatabaseManager.shared
    private let previewHeight: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
                .frame(height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            labelRow
        }
        .padding(12)
        .frame(width: 220)
        .background(UITokens.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: UITokens.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: UITokens.radiusCard)
                .strokeBorder(UITokens.surfaceBorder, lineWidth: 0.5)
        )
        .shadow(color: UITokens.shadowCard, radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: UITokens.radiusCard))
        .onTapGesture { onOpen?() }
        .task(id: workspace.id) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceDataDidChange)) { note in
            let changed = note.userInfo?["workspaceId"] as? String
            if changed == nil || changed == workspace.id { reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .placementDataDidChange)) { note in
            let changed = note.userInfo?["workspaceId"] as? String
            if changed == nil || changed == workspace.id { reload() }
        }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            // Dot-grid hint mimicking the canvas grid-snap aesthetic so
            // the miniature reads as "a workspace surface" even when
            // empty.
            DotGridBackground()
                .opacity(0.4)

            if placements.isEmpty {
                Image(systemName: "rectangle.split.3x3")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary)
            } else {
                WorkspaceMiniatureCanvas(placements: placements)
                    .padding(6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var labelRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workspace.isNamed ? (workspace.name ?? "") : "Unnamed workspace")
                .font(.system(size: 12, weight: workspace.isNamed ? .semibold : .regular))
                .foregroundStyle(workspace.isNamed ? .primary : .secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            Text(metaSummary)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var metaSummary: String {
        let countLabel: String
        switch totalCount {
        case 0: countLabel = "Empty"
        case 1: countLabel = "1 card"
        default: countLabel = "\(totalCount) cards"
        }
        return "\(countLabel) · \(relativeUpdatedAt)"
    }

    private var relativeUpdatedAt: String {
        let date = Date(timeIntervalSince1970: workspace.updatedAt)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func reload() {
        placements = db.placementsForWorkspaceMiniature(workspaceId: workspace.id)
        totalCount = db.placementCountForWorkspace(workspaceId: workspace.id)
    }
}

/// Renders every placement as a scaled rectangle at its world-coord
/// position. Computes a bounding box of all placements with 10% padding,
/// scales uniformly to fit the available area, and centers the result.
/// Cards smaller than 2pt at scale clamp to 2pt so they remain visible
/// as dots.
private struct WorkspaceMiniatureCanvas: View {
    let placements: [DatabaseManager.PlacementMiniature]

    var body: some View {
        GeometryReader { geo in
            let canvas = geo.size
            let bbox = boundingBox()
            let paddedW = bbox.width * 1.2
            let paddedH = bbox.height * 1.2
            let scale: CGFloat = {
                guard paddedW > 0, paddedH > 0,
                      canvas.width > 0, canvas.height > 0 else { return 1 }
                return min(canvas.width / paddedW, canvas.height / paddedH)
            }()
            let usedW = paddedW * scale
            let usedH = paddedH * scale
            let centerInsetX = (canvas.width - usedW) / 2
            let centerInsetY = (canvas.height - usedH) / 2
            let paddedMinX = bbox.minX - bbox.width * 0.1
            let paddedMinY = bbox.minY - bbox.height * 0.1

            ZStack(alignment: .topLeading) {
                ForEach(Array(placements.enumerated()), id: \.offset) { _, p in
                    let w = max(CGFloat(p.width) * scale, 2)
                    let h = max(CGFloat(p.height) * scale, 2)
                    let x = centerInsetX + (CGFloat(p.x) - paddedMinX) * scale
                    let y = centerInsetY + (CGFloat(p.y) - paddedMinY) * scale
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(tint(for: p.highlightType))
                        .frame(width: w, height: h)
                        .offset(x: x, y: y)
                }
            }
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        }
    }

    private func boundingBox() -> (minX: CGFloat, minY: CGFloat, width: CGFloat, height: CGFloat) {
        guard !placements.isEmpty else { return (0, 0, 1, 1) }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for p in placements {
            let x = CGFloat(p.x), y = CGFloat(p.y)
            let w = CGFloat(p.width), h = CGFloat(p.height)
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x + w)
            maxY = max(maxY, y + h)
        }
        // Guard against degenerate single-point case (all placements at
        // the same coords with zero size — shouldn't happen, but doesn't
        // hurt to keep scale finite).
        let w = max(maxX - minX, 1)
        let h = max(maxY - minY, 1)
        return (minX, minY, w, h)
    }

    private func tint(for type: String) -> Color {
        switch type {
        case "screenshot", "recording": return .gray.opacity(0.6)
        case "file":                    return .gray.opacity(0.4)
        case "highlight":               return .orange.opacity(0.4)
        case "note":                    return Color.secondary.opacity(0.4)
        case "copy":                    return Color.accentColor.opacity(0.4)
        default:                        return Color.secondary.opacity(0.4)
        }
    }
}

/// Subtle dot grid hinting at the canvas grid-snap aesthetic — used as
/// the workspace miniature's background so empty named workspaces still
/// read as "a workspace surface" rather than an empty card.
private struct DotGridBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 12
            let radius: CGFloat = 0.7
            let dot = Color.secondary.opacity(0.5)
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    let rect = CGRect(x: x - radius, y: y - radius,
                                      width: radius * 2, height: radius * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(dot))
                    x += spacing
                }
                y += spacing
            }
        }
    }
}
