import Foundation
import UniformTypeIdentifiers
import CoreTransferable

/// Unified drag payload for cross-pane card movement.
///
/// **Wire format**: round-trips through `String` via `ProxyRepresentation`,
/// which means the actual UTType on the pasteboard is `public.utf8-plain-text`.
/// SwiftUI's drag-drop type-matching is reliable for system types like that;
/// our earlier attempt at a private custom UTType (`UTType(exportedAs:...)`
/// with no Info.plist `UTExportedTypeDeclarations` entry) silently failed
/// to match drops because the system had no record of the type. The string
/// payload uses a `cmpl:` discriminator so the drop side can distinguish
/// our payloads from arbitrary text drops.
///
/// Usage:
/// - **Drag source**: `.draggable(CanvasDragItem(kind: .highlight, id: ...))`
///   on `MasonryCard`, `StackCard`, `StackDetailItemCell`, and `MaterialListRow`.
/// - **Drop target**: `.dropDestination(for: CanvasDragItem.self) { items, loc in ... }`
///   on `WorkspaceCanvasView` (creates placement) and `StackBody`
///   (adds to stack via `addHighlight`).
struct CanvasDragItem: Codable, Transferable, Equatable {
    enum Kind: String, Codable {
        case highlight
        case stack
    }

    let kind: Kind
    let id: String

    /// Wire format: `cmpl:<kind>:<id>`. Prefix lets the drop side reject
    /// arbitrary text drops; the system pasteboard sees a plain UTF-8
    /// string so external apps that accept text would see the literal
    /// discriminator if the user ever drags onto, say, TextEdit. That's
    /// inert and harmless for V1.
    var encoded: String {
        "cmpl:\(kind.rawValue):\(id)"
    }

    static func decode(_ raw: String) -> CanvasDragItem? {
        guard raw.hasPrefix("cmpl:") else { return nil }
        let rest = String(raw.dropFirst("cmpl:".count))
        let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let kind = Kind(rawValue: String(parts[0])) else { return nil }
        return CanvasDragItem(kind: kind, id: String(parts[1]))
    }

    enum DecodeError: Error {
        case invalidPayload
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting: { item in item.encoded },
            importing: { (string: String) in
                guard let parsed = CanvasDragItem.decode(string) else {
                    throw DecodeError.invalidPayload
                }
                return parsed
            }
        )
    }
}
