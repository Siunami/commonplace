import Foundation
import ScreenCaptureKit
import CoreGraphics

/// One app/window contributing visible pixels to a screenshot. Persisted
/// as JSON inside the highlight + screenshot tables (`sources` column).
/// `visibleArea` is in screen-space points and is the *visible* area
/// inside the capture rect after subtracting whatever windows in front
/// were occluding this one — not the raw rect overlap.
struct ScreenshotSource: Codable, Hashable {
    let bundleId: String?
    let name: String?
    let windowTitle: String?
    let visibleArea: CGFloat
}

/// Resolves the list of distinct apps visible inside a screenshot
/// region by intersecting each `SCWindow`'s frame with the capture
/// rect, then walking front-to-back and subtracting the area already
/// claimed by windows on top. Apps whose remaining visible area falls
/// below `minOverlapArea(for:)` are dropped — that's how a 1px sliver
/// of a window bleeding into the region gets ignored.
///
/// Pure logic, no capture-time side effects, easy to unit-test against
/// fabricated `[SCWindow]`-shaped inputs.
enum ScreenshotSources {
    /// Threshold tuning. A window must contribute at least
    /// `max(minOverlapFraction × rect.area, minOverlapPixels)` of
    /// visible pixels inside the capture rect to count as a source.
    /// 5% of the region OR 6400 px (≈80×80), whichever is larger,
    /// rules out edge-bleed slivers without dropping legitimately
    /// small contributors on full-screen captures.
    static let minOverlapFraction: CGFloat = 0.05
    static let minOverlapPixels: CGFloat = 80 * 80

    /// Bundle identifiers that should never appear as a source even
    /// when their windows technically intersect the capture rect.
    /// These are system chrome the user wouldn't think of as "the
    /// thing in the screenshot."
    static let systemChromeBundleIds: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowServer",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui"
    ]

    /// Windows above this layer are system chrome (menu bar = 25,
    /// status windows = 25, dock = 20). Keep them as occluders so
    /// a window peeking out from behind the menu bar isn't credited
    /// for those pixels — but they're filtered out as candidate
    /// sources by the bundle-id blocklist + this layer guard.
    static let maxSourceWindowLayer: Int = 4

    static func resolve(
        rect: CGRect,
        windows: [SCWindow],
        excluding: Set<CGWindowID> = []
    ) -> [ScreenshotSource] {
        guard !rect.isEmpty else { return [] }
        let threshold = max(minOverlapFraction * rect.width * rect.height, minOverlapPixels)

        // Front-to-back order: higher windowLayer = further forward.
        // Within the same layer SCShareableContent already returns
        // windows in z-order (front first), so a stable sort by layer
        // descending preserves that ordering.
        let ordered = windows.sorted { $0.windowLayer > $1.windowLayer }

        var occupied: [CGRect] = []
        var sources: [ScreenshotSource] = []

        for window in ordered {
            guard window.isOnScreen,
                  !excluding.contains(window.windowID) else { continue }

            let raw = window.frame.intersection(rect)
            guard !raw.isNull, !raw.isEmpty else { continue }

            // Compute visible area = raw overlap minus pieces already
            // claimed by windows in front of this one.
            let visiblePieces = subtract(raw, holes: occupied)
            let visibleArea = visiblePieces.reduce(0) { $0 + $1.width * $1.height }

            // Always claim the raw overlap going forward — even system
            // chrome occludes pixels behind it visually, so a window
            // peeking out from behind the menu bar shouldn't get
            // credit for menu-bar-covered pixels.
            occupied.append(raw)

            guard visibleArea >= threshold else { continue }
            guard isCandidateSource(window) else { continue }

            sources.append(
                ScreenshotSource(
                    bundleId: window.owningApplication?.bundleIdentifier,
                    name: window.owningApplication?.applicationName,
                    windowTitle: window.title?.nilIfEmpty,
                    visibleArea: visibleArea
                )
            )
        }

        // Largest visible contributor first — callers use sources[0]
        // as the primary attribution when populating Highlight's
        // singular sourceApp / bundleId fields for backward compat.
        return sources.sorted { $0.visibleArea > $1.visibleArea }
    }

    /// Whether this window is allowed to surface as a source. Occlusion
    /// uses every visible window; sourcing is stricter.
    private static func isCandidateSource(_ window: SCWindow) -> Bool {
        guard let app = window.owningApplication else { return false }
        if systemChromeBundleIds.contains(app.bundleIdentifier) { return false }
        if window.windowLayer > maxSourceWindowLayer { return false }
        return true
    }

    /// Returns the rectangles of `target` not covered by any of `holes`.
    /// Iteratively replaces each surviving piece with up to four
    /// strips (above / below / left / right of the hole's intersection).
    /// O(|target| × |holes|) which is fine — typical screen has under
    /// 50 visible windows.
    static func subtract(_ target: CGRect, holes: [CGRect]) -> [CGRect] {
        var pieces: [CGRect] = [target]
        for hole in holes where !hole.isNull && !hole.isEmpty {
            var next: [CGRect] = []
            next.reserveCapacity(pieces.count * 2)
            for piece in pieces {
                next.append(contentsOf: subtractOne(piece, hole: hole))
            }
            pieces = next
            if pieces.isEmpty { return [] }
        }
        return pieces
    }

    /// Single-rect subtraction: returns 0–4 axis-aligned remainders of
    /// `piece` after removing the `hole` overlap. When the hole doesn't
    /// touch the piece, returns `[piece]` unchanged.
    private static func subtractOne(_ piece: CGRect, hole: CGRect) -> [CGRect] {
        let inter = piece.intersection(hole)
        if inter.isNull || inter.isEmpty { return [piece] }
        if inter == piece { return [] }

        var remainders: [CGRect] = []

        // Top strip — full piece width, above the intersection's top edge.
        if inter.minY > piece.minY {
            remainders.append(CGRect(
                x: piece.minX, y: piece.minY,
                width: piece.width, height: inter.minY - piece.minY
            ))
        }
        // Bottom strip — full piece width, below the intersection.
        if inter.maxY < piece.maxY {
            remainders.append(CGRect(
                x: piece.minX, y: inter.maxY,
                width: piece.width, height: piece.maxY - inter.maxY
            ))
        }
        // Left strip — within the intersection's y-range, left of it.
        if inter.minX > piece.minX {
            remainders.append(CGRect(
                x: piece.minX, y: inter.minY,
                width: inter.minX - piece.minX, height: inter.height
            ))
        }
        // Right strip — within the intersection's y-range, right of it.
        if inter.maxX < piece.maxX {
            remainders.append(CGRect(
                x: inter.maxX, y: inter.minY,
                width: piece.maxX - inter.maxX, height: inter.height
            ))
        }
        return remainders
    }

    /// Encode a resolved source list to a JSON string suitable for the
    /// `sources` TEXT column on `highlight` and `screenshot`. Returns
    /// nil when the list is empty so we don't pollute rows with `[]`.
    static func encodeJSON(_ sources: [ScreenshotSource]) -> String? {
        guard !sources.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(sources),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    /// Decode the JSON string from the DB back into the in-memory list.
    /// Empty / nil / malformed inputs all return `[]`, matching the
    /// behavior of `Highlight.decodedSourceContext`.
    static func decodeJSON(_ json: String?) -> [ScreenshotSource] {
        guard let json, !json.isEmpty,
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ScreenshotSource].self, from: data)) ?? []
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
