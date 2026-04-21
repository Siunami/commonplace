import Foundation
import AppKit

/// Writes a Stack to disk as a Textbundle:
///
///     Stack Name.textbundle/
///     ├── text.md
///     ├── info.json
///     └── assets/
///         ├── screenshot-001.png
///         └── recording-002.mov
///
/// Textbundle is the standard "markdown + media" wrapper that Bear,
/// iA Writer, Ulysses, and many others import natively — Bear in
/// particular resolves `assets/...` references on import so images
/// and videos land inside the imported note rather than getting dropped.
///
/// The bundle is also just a regular folder on disk, so Obsidian users
/// can drop it into a vault and open `text.md` with working images,
/// and ChatGPT/Claude users can paste the markdown body unchanged.
enum StackExporter {
    struct Result {
        let folderURL: URL
        let markdownURL: URL
        let mediaCopied: Int
    }

    enum ExportError: Error {
        case targetExists(URL)
    }

    /// Export `stack` into `parentDirectory`, creating a `.textbundle`
    /// package named after the stack. Returns the resulting folder URL
    /// so the caller can reveal it in Finder.
    static func export(stack: Stack, into parentDirectory: URL) throws -> Result {
        let db = DatabaseManager.shared
        let items = db.highlightsForStack(stackId: stack.id)

        let bundleName = exportBundleName(for: stack) + ".textbundle"
        let folderURL = parentDirectory.appendingPathComponent(bundleName, isDirectory: true)
        let mediaURL = folderURL.appendingPathComponent("assets", isDirectory: true)

        let fm = FileManager.default
        if fm.fileExists(atPath: folderURL.path) {
            throw ExportError.targetExists(folderURL)
        }
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try writeInfoJSON(into: folderURL)

        var mediaCounter = 1
        var mediaCreated = 0
        var body = ""

        body += "# \(displayName(for: stack))\n\n"
        if let desc = stack.stackDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !desc.isEmpty {
            body += "\(desc)\n\n"
        }
        body += "\(items.count) item\(items.count == 1 ? "" : "s")\n\n"

        for item in items {
            body += "---\n\n"
            body += renderItem(
                item,
                mediaDir: mediaURL,
                counter: &mediaCounter,
                mediaCreated: &mediaCreated
            )

            let notes = db.notesForHighlight(id: item.id)
            if !notes.isEmpty {
                body += "\n"
                for note in notes {
                    body += "- \(formatBullet(note.body))\n"
                }
            }
            body += "\n"
        }

        let markdownURL = folderURL.appendingPathComponent("text.md")
        try body.write(to: markdownURL, atomically: true, encoding: .utf8)

        if mediaCreated == 0 {
            try? fm.removeItem(at: mediaURL)
        }

        return Result(folderURL: folderURL, markdownURL: markdownURL, mediaCopied: mediaCreated)
    }

    // MARK: - Per-item rendering

    private static func renderItem(
        _ item: Highlight,
        mediaDir: URL,
        counter: inout Int,
        mediaCreated: inout Int
    ) -> String {
        var body = ""

        switch item.highlightType {
        case "screenshot":
            if let rel = copyMedia(
                from: item.contentText,
                to: mediaDir,
                kind: "screenshot",
                counter: &counter,
                created: &mediaCreated
            ) {
                body += "![](\(rel))\n"
            } else {
                body += "_(screenshot unavailable)_\n"
            }

        case "recording":
            if let rel = copyMedia(
                from: item.contentText,
                to: mediaDir,
                kind: "recording",
                counter: &counter,
                created: &mediaCreated
            ) {
                let name = (rel as NSString).lastPathComponent
                body += "[\(name)](\(rel))\n"
            } else {
                body += "_(recording unavailable)_\n"
            }

        case "file":
            let sourcePath: String
            let preserve: String
            if let fid = item.fileId,
               let rec = DatabaseManager.shared.fileRecord(byId: fid) {
                sourcePath = rec.filePath
                preserve = rec.fileName
            } else {
                sourcePath = item.contentText
                preserve = (sourcePath as NSString).lastPathComponent
            }
            if let rel = copyMedia(
                from: sourcePath,
                to: mediaDir,
                kind: "file",
                counter: &counter,
                created: &mediaCreated,
                preserveName: preserve
            ) {
                let ext = (rel as NSString).pathExtension.lowercased()
                if imageExtensions.contains(ext) {
                    body += "![](\(rel))\n"
                } else {
                    body += "[\(preserve)](\(rel))\n"
                }
            } else {
                body += "_(file unavailable: \(preserve))_\n"
            }

        case "highlight", "note":
            body += blockquote(item.contentText) + "\n"

        default:
            if item.isURLCopy {
                let url = item.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = URL(string: url)?.host?
                    .replacingOccurrences(of: "www.", with: "") ?? url
                body += "[\(label)](\(url))\n"
            } else {
                body += blockquote(item.contentText) + "\n"
            }
        }

        if let line = sourceLine(for: item) {
            body += "\nSource: \(line)\n"
        }

        return body
    }

    // MARK: - Helpers

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "bmp"
    ]

    /// Textbundle spec requires an `info.json` at the root of the bundle
    /// declaring the markdown flavor. Without this, Bear treats the
    /// folder as a plain directory and doesn't resolve `assets/...`.
    private static func writeInfoJSON(into bundleURL: URL) throws {
        let payload: [String: Any] = [
            "version": 2,
            "type": "net.daringfireball.markdown",
            "transient": false,
            "creatorIdentifier": "com.commonplace.stackexport"
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: bundleURL.appendingPathComponent("info.json"))
    }

    private static func displayName(for stack: Stack) -> String {
        if let n = stack.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !n.isEmpty {
            return n
        }
        return "Untitled Stack"
    }

    private static func sourceLine(for item: Highlight) -> String? {
        if let raw = item.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           URL(string: raw) != nil {
            let title = item.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let title, !title.isEmpty {
                return "[\(title)](\(raw))"
            }
            let host = URL(string: raw)?.host?
                .replacingOccurrences(of: "www.", with: "") ?? raw
            return "[\(host)](\(raw))"
        }
        if let app = item.sourceApp?.trimmingCharacters(in: .whitespacesAndNewlines),
           !app.isEmpty {
            return app
        }
        return nil
    }

    private static func blockquote(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "> " }
        return trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? ">" : "> \($0)" }
            .joined(separator: "\n")
    }

    private static func formatBullet(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return trimmed }
        let first = String(lines[0])
        let rest = lines.dropFirst().map { "  \($0)" }.joined(separator: "\n")
        return "\(first)\n\(rest)"
    }

    private static func copyMedia(
        from sourcePath: String,
        to mediaDir: URL,
        kind: String,
        counter: inout Int,
        created: inout Int,
        preserveName: String? = nil
    ) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourcePath) else { return nil }

        do {
            try fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let ext = (sourcePath as NSString).pathExtension
        let padded = String(format: "%03d", counter)
        let filename: String
        if let preserveName {
            let stem = (preserveName as NSString).deletingPathExtension
            let sanitizedStem = sanitizeFilename(stem)
            let ext2 = ext.isEmpty
                ? (preserveName as NSString).pathExtension
                : ext
            if ext2.isEmpty {
                filename = "\(padded)-\(sanitizedStem)"
            } else {
                filename = "\(padded)-\(sanitizedStem).\(ext2)"
            }
        } else {
            filename = ext.isEmpty ? "\(kind)-\(padded)" : "\(kind)-\(padded).\(ext)"
        }

        let dest = mediaDir.appendingPathComponent(filename)
        do {
            try fm.copyItem(at: URL(fileURLWithPath: sourcePath), to: dest)
        } catch {
            return nil
        }

        counter += 1
        created += 1
        return "assets/\(filename)"
    }

    private static func sanitizedFolderName(_ name: String) -> String {
        let cleaned = sanitizeFilename(name)
        return cleaned.isEmpty ? "Untitled Stack" : cleaned
    }

    /// Export folder name with leading `Stack Export` tag and an ISO
    /// date + time suffix. The tag up front makes these easy to spot
    /// when re-imported into the archiving tool, and the timestamp
    /// sorts chronologically and disambiguates repeat exports of the
    /// same stack on the same day.
    ///
    /// Example: `Stack Export — My Reading List — 2026-04-20 1432`
    private static func exportBundleName(for stack: Stack) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let stamp = formatter.string(from: Date())
        let title = sanitizedFolderName(displayName(for: stack))
        return "Stack Export — \(title) — \(stamp)"
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let clean = name.components(separatedBy: invalid).joined()
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
