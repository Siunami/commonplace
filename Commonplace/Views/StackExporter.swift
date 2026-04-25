import Foundation
import AppKit

/// Serializes a Stack to disk or to a markdown string. Used by
/// `StackExportTargets` to build Textbundle packages, flat LLM-friendly
/// folders, and plain clipboard markdown.
///
/// Three output shapes share one item renderer, parameterized by where
/// media files land (if at all) and what prefix shows up in markdown
/// image/file links:
///
///   * Textbundle:  media → `<bundle>/assets/…`, links → `assets/file.png`
///   * Flat folder: media → `<folder>/…`,        links → `file.png`
///   * Text only:   no media copy, links become `[screenshot]` placeholders
enum StackExporter {
    struct Result {
        let folderURL: URL?
        let markdownURL: URL?
        let markdown: String
        let mediaCopied: Int
    }

    enum ExportError: Error {
        case targetExists(URL)
    }

    // MARK: - Public API

    /// Textbundle package: `<Name>.textbundle/text.md` + `info.json` + `assets/`.
    /// Standard format for Bear, iA Writer, Ulysses; works as a plain
    /// folder in Obsidian.
    static func exportTextbundle(
        stack: Stack,
        into parentDirectory: URL
    ) throws -> Result {
        let bundleName = exportBundleName(for: stack, prefix: "Stack Export") + ".textbundle"
        let folderURL = parentDirectory.appendingPathComponent(bundleName, isDirectory: true)
        let mediaURL = folderURL.appendingPathComponent("assets", isDirectory: true)

        let fm = FileManager.default
        if fm.fileExists(atPath: folderURL.path) {
            throw ExportError.targetExists(folderURL)
        }
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try writeInfoJSON(into: folderURL)

        var mediaCreated = 0
        let markdown = buildMarkdown(
            stack: stack,
            seed: nil,
            mediaDir: mediaURL,
            mediaLinkPrefix: "assets/",
            mediaCreated: &mediaCreated
        )
        let markdownURL = folderURL.appendingPathComponent("text.md")
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

        if mediaCreated == 0 {
            try? fm.removeItem(at: mediaURL)
        }

        return Result(
            folderURL: folderURL,
            markdownURL: markdownURL,
            markdown: markdown,
            mediaCopied: mediaCreated
        )
    }

    /// Flat folder: `<Name>/prompt.md` + media files as siblings. Each
    /// item's media can be dragged individually into an LLM chat input
    /// or any tool that doesn't understand Textbundle's asset subfolder
    /// convention.
    static func exportFolder(
        stack: Stack,
        into parentDirectory: URL,
        seed: String? = nil
    ) throws -> Result {
        let folderName = exportBundleName(for: stack, prefix: "Stack Prompt")
        let folderURL = parentDirectory.appendingPathComponent(folderName, isDirectory: true)

        let fm = FileManager.default
        if fm.fileExists(atPath: folderURL.path) {
            throw ExportError.targetExists(folderURL)
        }
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var mediaCreated = 0
        let markdown = buildMarkdown(
            stack: stack,
            seed: seed,
            mediaDir: folderURL,
            mediaLinkPrefix: "",
            mediaCreated: &mediaCreated
        )
        let markdownURL = folderURL.appendingPathComponent("prompt.md")
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

        return Result(
            folderURL: folderURL,
            markdownURL: markdownURL,
            markdown: markdown,
            mediaCopied: mediaCreated
        )
    }

    /// Markdown only, no disk I/O. Media items render as placeholders so
    /// the output paste-cleanly into a chat input without broken links.
    static func renderMarkdown(stack: Stack, seed: String? = nil) -> String {
        var dummy = 0
        return buildMarkdown(
            stack: stack,
            seed: seed,
            mediaDir: nil,
            mediaLinkPrefix: "",
            mediaCreated: &dummy
        )
    }

    // MARK: - Body construction

    private static func buildMarkdown(
        stack: Stack,
        seed: String?,
        mediaDir: URL?,
        mediaLinkPrefix: String,
        mediaCreated: inout Int
    ) -> String {
        var body = ""
        if let trimmed = seed?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty {
            body += "\(trimmed)\n\n---\n\n"
        }

        var mediaCounter = 1
        var visited = Set<String>()
        body += renderStackNode(
            stack: stack,
            depth: 1,
            visited: &visited,
            mediaDir: mediaDir,
            mediaLinkPrefix: mediaLinkPrefix,
            mediaCounter: &mediaCounter,
            mediaCreated: &mediaCreated
        )
        return body
    }

    /// Emits one stack's heading + items, then recurses into its substacks.
    /// `visited` guards against intentional cycles (the model allows them):
    /// a revisited stack emits a short "see earlier" pointer and stops, so
    /// markdown always terminates. The shared media counter keeps asset
    /// filenames unique across the whole exported tree.
    private static func renderStackNode(
        stack: Stack,
        depth: Int,
        visited: inout Set<String>,
        mediaDir: URL?,
        mediaLinkPrefix: String,
        mediaCounter: inout Int,
        mediaCreated: inout Int
    ) -> String {
        let db = DatabaseManager.shared
        if visited.contains(stack.id) {
            return "_(See earlier “\(displayName(for: stack))”)_\n\n"
        }
        visited.insert(stack.id)

        let items = db.highlightsForStack(stackId: stack.id)
        let substacks = db.substacksForStack(stackId: stack.id)

        var body = ""
        let hashes = String(repeating: "#", count: min(depth, 6))
        body += "\(hashes) \(displayName(for: stack))\n\n"
        if let desc = stack.stackDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !desc.isEmpty {
            body += "\(desc)\n\n"
        }

        var countParts: [String] = []
        if !substacks.isEmpty {
            countParts.append("\(substacks.count) stack\(substacks.count == 1 ? "" : "s")")
        }
        countParts.append("\(items.count) item\(items.count == 1 ? "" : "s")")
        body += "\(countParts.joined(separator: " · "))\n\n"

        for child in substacks {
            body += renderStackNode(
                stack: child,
                depth: depth + 1,
                visited: &visited,
                mediaDir: mediaDir,
                mediaLinkPrefix: mediaLinkPrefix,
                mediaCounter: &mediaCounter,
                mediaCreated: &mediaCreated
            )
        }

        for item in items {
            body += "---\n\n"
            body += renderItem(
                item,
                mediaDir: mediaDir,
                mediaLinkPrefix: mediaLinkPrefix,
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

        return body
    }

    // MARK: - Per-item rendering

    private static func renderItem(
        _ item: Highlight,
        mediaDir: URL?,
        mediaLinkPrefix: String,
        counter: inout Int,
        mediaCreated: inout Int
    ) -> String {
        var body = ""

        switch item.highlightType {
        case "screenshot":
            body += renderMediaItem(
                sourcePath: item.contentText,
                kind: "screenshot",
                preserveName: nil,
                placeholder: "[screenshot]",
                mediaDir: mediaDir,
                mediaLinkPrefix: mediaLinkPrefix,
                counter: &counter,
                mediaCreated: &mediaCreated
            )

        case "recording":
            body += renderMediaItem(
                sourcePath: item.contentText,
                kind: "recording",
                preserveName: nil,
                placeholder: "[recording]",
                mediaDir: mediaDir,
                mediaLinkPrefix: mediaLinkPrefix,
                counter: &counter,
                mediaCreated: &mediaCreated
            )

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
            body += renderMediaItem(
                sourcePath: sourcePath,
                kind: "file",
                preserveName: preserve,
                placeholder: "[file: \(preserve)]",
                mediaDir: mediaDir,
                mediaLinkPrefix: mediaLinkPrefix,
                counter: &counter,
                mediaCreated: &mediaCreated
            )

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

    private static func renderMediaItem(
        sourcePath: String,
        kind: String,
        preserveName: String?,
        placeholder: String,
        mediaDir: URL?,
        mediaLinkPrefix: String,
        counter: inout Int,
        mediaCreated: inout Int
    ) -> String {
        // No disk output requested — render a text placeholder so the
        // markdown pastes cleanly without broken image links.
        guard let mediaDir else {
            return "\(placeholder)\n"
        }

        guard let filename = copyMedia(
            from: sourcePath,
            to: mediaDir,
            kind: kind,
            counter: &counter,
            created: &mediaCreated,
            preserveName: preserveName
        ) else {
            return "_(\(kind) unavailable)_\n"
        }

        let link = "\(mediaLinkPrefix)\(filename)"
        let ext = (filename as NSString).pathExtension.lowercased()
        if imageExtensions.contains(ext) {
            return "![](\(link))\n"
        } else {
            let label = preserveName ?? filename
            return "[\(label)](\(link))\n"
        }
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

    /// Copies a source file into `mediaDir` with a numbered, sanitized
    /// filename and returns that filename (no path prefix). The caller
    /// composes the final markdown link by prepending whatever subdir
    /// prefix the target expects (`assets/` for Textbundle, `""` for a
    /// flat folder).
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
        return filename
    }

    private static func sanitizedFolderName(_ name: String) -> String {
        let cleaned = sanitizeFilename(name)
        return cleaned.isEmpty ? "Untitled Stack" : cleaned
    }

    /// Export folder name with a leading `prefix` tag and an ISO
    /// date + time suffix. The tag up front makes these easy to spot
    /// when re-imported, the timestamp sorts chronologically and
    /// disambiguates repeat exports of the same stack on the same day.
    ///
    /// Example: `Stack Export — My Reading List — 2026-04-20 1432`
    private static func exportBundleName(for stack: Stack, prefix: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let stamp = formatter.string(from: Date())
        let title = sanitizedFolderName(displayName(for: stack))
        return "\(prefix) — \(title) — \(stamp)"
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let clean = name.components(separatedBy: invalid).joined()
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
