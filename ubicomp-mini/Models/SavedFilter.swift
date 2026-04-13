import Foundation
import GRDB

struct SavedFilter: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: String
    var name: String
    var predicateJSON: String  // JSON-encoded array of FilterPredicate
    var createdAt: Double
    var icon: String           // SF Symbol name

    static let databaseTableName = "saved_filter"

    var date: Date { Date(timeIntervalSince1970: createdAt) }

    var predicates: [FilterPredicate] {
        guard let data = predicateJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([FilterPredicate].self, from: data) else {
            return []
        }
        return decoded
    }

    static func encode(predicates: [FilterPredicate]) -> String {
        guard let data = try? JSONEncoder().encode(predicates),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    /// Build a SQL WHERE clause from the predicates (AND logic).
    func toSQL() -> (clause: String, arguments: [String]) {
        let preds = predicates
        guard !preds.isEmpty else { return ("1=1", []) }

        var clauses: [String] = []
        var args: [String] = []

        for pred in preds {
            // Tag field uses subqueries instead of column-based filtering
            if pred.field == .tag {
                switch pred.op {
                case .equals:
                    clauses.append("""
                        EXISTS (SELECT 1 FROM highlight_tag ht \
                        JOIN tag t ON t.id = ht.tagId \
                        WHERE ht.highlightId = highlight.id AND t.name = ?)
                        """)
                    args.append(pred.value)
                case .contains:
                    clauses.append("""
                        EXISTS (SELECT 1 FROM highlight_tag ht \
                        JOIN tag t ON t.id = ht.tagId \
                        WHERE ht.highlightId = highlight.id AND t.name LIKE ? COLLATE NOCASE)
                        """)
                    args.append("%\(pred.value)%")
                case .isNotEmpty:
                    clauses.append("EXISTS (SELECT 1 FROM highlight_tag WHERE highlightId = highlight.id)")
                case .isEmpty:
                    clauses.append("NOT EXISTS (SELECT 1 FROM highlight_tag WHERE highlightId = highlight.id)")
                case .startsWith:
                    clauses.append("""
                        EXISTS (SELECT 1 FROM highlight_tag ht \
                        JOIN tag t ON t.id = ht.tagId \
                        WHERE ht.highlightId = highlight.id AND t.name LIKE ? COLLATE NOCASE)
                        """)
                    args.append("\(pred.value)%")
                }
                continue
            }

            let col = pred.field.columnName
            switch pred.op {
            case .equals:
                clauses.append("\(col) = ?")
                args.append(pred.value)
            case .contains:
                clauses.append("\(col) LIKE ?")
                args.append("%\(pred.value)%")
            case .startsWith:
                clauses.append("\(col) LIKE ?")
                args.append("\(pred.value)%")
            case .isNotEmpty:
                clauses.append("\(col) IS NOT NULL AND \(col) != ''")
            case .isEmpty:
                clauses.append("(\(col) IS NULL OR \(col) = '')")
            }
        }

        return (clauses.joined(separator: " AND "), args)
    }
}

// MARK: - Filter Building Blocks

struct FilterPredicate: Codable, Identifiable {
    var id: String = UUID().uuidString
    var field: FilterField
    var op: FilterOperator
    var value: String

    enum CodingKeys: String, CodingKey {
        case id, field, op, value
    }
}

enum FilterField: String, Codable, CaseIterable {
    case sourceApp
    case sourceUrl
    case windowTitle
    case bundleId
    case highlightType
    case contentType
    case wifiNetwork
    case displayName
    case appearanceMode
    case tag

    var displayName_: String {
        switch self {
        case .sourceApp: return "App"
        case .sourceUrl: return "URL"
        case .windowTitle: return "Window"
        case .bundleId: return "Bundle ID"
        case .highlightType: return "Capture type"
        case .contentType: return "Content type"
        case .wifiNetwork: return "Wi-Fi"
        case .displayName: return "Display"
        case .appearanceMode: return "Appearance"
        case .tag: return "Tag"
        }
    }

    var columnName: String {
        switch self {
        case .tag: return "tag"
        default: return rawValue
        }
    }
}

enum FilterOperator: String, Codable, CaseIterable {
    case equals
    case contains
    case startsWith
    case isNotEmpty
    case isEmpty

    var displayName: String {
        switch self {
        case .equals: return "is"
        case .contains: return "contains"
        case .startsWith: return "starts with"
        case .isNotEmpty: return "has value"
        case .isEmpty: return "is empty"
        }
    }

    var needsValue: Bool {
        switch self {
        case .isNotEmpty, .isEmpty: return false
        default: return true
        }
    }
}
