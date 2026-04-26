import Foundation
import GRDB

/// A spatial surface holding `Placement` rows. Workspaces are persisted
/// alongside stacks/highlights in the GRDB store; the in-memory tab/pane
/// shell (`WorkspaceState`) carries a workspace's id inside its
/// `WorkspaceTabContent` so the canvas tab and the DB row stay in sync.
struct Workspace: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    var id: String
    var name: String?
    var createdAt: Double
    var updatedAt: Double

    static let databaseTableName = "workspace"

    var date: Date { Date(timeIntervalSince1970: createdAt) }

    var isNamed: Bool {
        guard let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !n.isEmpty
    }
}
