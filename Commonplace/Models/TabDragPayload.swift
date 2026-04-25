import Foundation
import UniformTypeIdentifiers
import CoreTransferable

/// Custom UTI used as the wire format for drag-and-drop of workspace
/// tabs. Declared in `Info.plist` under `UTExportedTypeDeclarations`
/// and conforms to `public.data` — `UTType(exportedAs:)` needs that
/// plist entry to register the identifier with LaunchServices, without
/// which SwiftUI's `.draggable` / `.dropDestination` silently no-op.
/// The payload itself is still in-process only: the UUIDs only have
/// meaning within the running app.
extension UTType {
    static let commonplaceTab = UTType(exportedAs: "com.commonplace.workspace-tab")
}

/// Identifies one tab during a drag operation. Carries the source pane id
/// alongside the tab id so the drop handler can call the right mutation
/// (move within pane = reorder, move across panes = cross-pane move,
/// drop on right edge of single pane = split).
///
/// Codable so it round-trips through SwiftUI's drag pasteboard via
/// `CodableRepresentation`. Values are UUIDs that only make sense within
/// the running process — dragging out of the app does nothing.
struct TabDragPayload: Codable, Transferable {
    let paneId: UUID
    let tabId: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .commonplaceTab)
    }
}
