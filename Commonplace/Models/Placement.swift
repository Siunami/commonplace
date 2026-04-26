import Foundation
import GRDB

/// One card's appearance in one workspace at given coordinates.
/// `(workspaceId, cardId)` is unique at the DB level — V1 disallows the
/// same card appearing twice in the same workspace.
struct Placement: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    var id: String
    var workspaceId: String
    var cardId: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var createdAt: Double

    static let databaseTableName = "placement"
}
