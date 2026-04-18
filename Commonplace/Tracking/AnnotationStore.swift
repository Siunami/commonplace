import Foundation

struct AnnotationEntry: Codable, Identifiable {
    let id: String
    let content: String
    let timestamp: Double
    let sourceApp: String?
    let type: String  // "copy" | "highlight" | "screenshot"
    var annotation: String?
}

final class AnnotationStore {
    static let shared = AnnotationStore()

    private let folder: URL
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        folder = DatabaseManager.appSupportURL
            .appendingPathComponent("annotations")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func fileURL(for date: Date = Date()) -> URL {
        let dateString = dateFormatter.string(from: date)
        return folder.appendingPathComponent("\(dateString).json")
    }

    private func loadEntries(from url: URL) -> [AnnotationEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([AnnotationEntry].self, from: data)) ?? []
    }

    private func writeEntries(_ entries: [AnnotationEntry], to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: url)
        }
    }

    func save(_ entry: AnnotationEntry) {
        let url = fileURL()
        var entries = loadEntries(from: url)
        entries.append(entry)
        writeEntries(entries, to: url)
    }

    func updateAnnotation(id: String, note: String) {
        let url = fileURL()
        var entries = loadEntries(from: url)
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].annotation = note
            writeEntries(entries, to: url)
        }
    }
}
