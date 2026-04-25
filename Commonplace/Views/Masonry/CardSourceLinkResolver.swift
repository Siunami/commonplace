import Foundation

/// Resolves a `Highlight` to its best `CardSourceLink` — the pill surfaced on
/// hover at the top-right of a link-card. Previously this ran as a computed
/// property on `MasonryCard` and fired `FileManager.fileExists` syscalls plus
/// a JSON decode on every render. Moving it off the render path here makes
/// the whole resolve a single batch during pagination; the result is stored
/// in BrowseView state and passed down as a parameter.
enum CardSourceLinkResolver {
    /// Deterministic rank:
    ///   1. sourceContext entry carrying an explicit URL (enricher-promoted).
    ///   2. `sourceUrl` when it parses as http(s).
    ///   3. URL-copy `contentText` when the body IS a URL.
    ///   4. `sourceUrl` file path that exists on disk.
    ///   5. `documentPath` that exists on disk.
    ///   6. Bare app launch via `bundleId` / `sourceApp`.
    static func resolve(for highlight: Highlight) -> CardSourceLink? {
        if let entry = highlight.decodedSourceContext.first(where: { $0.url != nil }),
           let urlString = entry.url, let parsed = URL(string: urlString) {
            return .url(urlString, label: hostLabel(from: parsed, fallback: urlString))
        }

        if let urlString = highlight.sourceUrl, !urlString.isEmpty,
           let parsed = URL(string: urlString), parsed.scheme?.hasPrefix("http") == true {
            return .url(urlString, label: hostLabel(from: parsed, fallback: urlString))
        }

        if highlight.isURLCopy {
            let trimmed = highlight.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = URL(string: trimmed) {
                return .url(trimmed, label: hostLabel(from: parsed, fallback: trimmed))
            }
        }

        if let path = highlight.sourceUrl, path.hasPrefix("/"),
           FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            return .file(url, label: url.lastPathComponent)
        }
        if let path = highlight.documentPath, !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            return .file(url, label: url.lastPathComponent)
        }

        if let bid = highlight.bundleId, !bid.isEmpty,
           let name = highlight.sourceApp, !name.isEmpty {
            return .app(bundleId: bid, label: name)
        }
        return nil
    }

    /// Batch helper for a page of highlights — shields callers from the per-
    /// highlight syscall cost by allowing it to run on a background queue.
    static func resolveBatch(_ highlights: [Highlight]) -> [String: CardSourceLink] {
        var out: [String: CardSourceLink] = [:]
        out.reserveCapacity(highlights.count)
        for h in highlights {
            if let link = resolve(for: h) {
                out[h.id] = link
            }
        }
        return out
    }

    static func hostLabel(from url: URL, fallback: String) -> String {
        if let host = url.host, !host.isEmpty {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return fallback
    }
}
