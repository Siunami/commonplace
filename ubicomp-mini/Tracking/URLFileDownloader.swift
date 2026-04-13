import Foundation
import AppKit

/// Best-effort downloader that fetches a copied URL when it points to a file
/// (PDF, image, video, etc.), lands it in the app's media folder via
/// `FileMonitor.importDownloadedFile`, and attaches the resulting FileRecord
/// to the existing URL-copy highlight. Failures are silent — the highlight
/// stays a normal link.
final class URLFileDownloader {
    static let shared = URLFileDownloader()

    /// Conservative ceiling. Anything larger is skipped.
    static let maxDownloadBytes: Int64 = 200 * 1024 * 1024

    /// Request timeout. Keep short — this is a background enhancement.
    private static let requestTimeout: TimeInterval = 30

    /// Extensions we treat as file URLs. Mirrors the categories
    /// `FileMonitor.contentTypeCategory(from:uti:)` already recognises.
    static let fileExtensions: Set<String> = [
        "pdf", "epub", "mobi",
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "svg", "tiff", "bmp",
        "mp4", "mov", "m4v", "webm", "mkv", "avi",
        "mp3", "m4a", "wav", "flac", "ogg", "aac",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "csv", "txt", "md", "rtf",
        "zip"
    ]

    private let db = DatabaseManager.shared

    /// Returns true if the URL string has a path extension we recognise as a file.
    /// Strips query/fragment before checking, so `…/paper.pdf?token=abc` → `pdf`.
    static func isLikelyFileURL(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return false }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        return fileExtensions.contains(ext)
    }

    /// Download the URL, persist it as a FileRecord, and attach it to
    /// `highlightId`. No-op if the URL isn't a known file type, or if
    /// anything along the way fails. Safe to call from any actor.
    func downloadIfFile(urlString: String, attachTo highlightId: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isLikelyFileURL(trimmed), let url = URL(string: trimmed) else { return }

        // Dedup: if we already downloaded this URL, reuse the existing FileRecord
        // and just point the new highlight at it — no network hit, no second copy.
        if let existing = db.fileRecord(byOriginalUrl: trimmed), let existingId = existing.id {
            db.updateHighlightFileLink(
                id: highlightId,
                fileId: existingId,
                contentType: existing.contentType
            )
            CaptureLog.info("URLFileDownloader: reused \(existing.fileName) for highlight \(highlightId)")
            await MainActor.run {
                NotificationCenter.default.post(name: .highlightDidSave, object: nil)
            }
            return
        }

        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        // Send a browser-ish UA — some CDNs block the default URLSession UA.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) ubicomp-mini",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let tempURL: URL
        let response: URLResponse
        do {
            (tempURL, response) = try await URLSession.shared.download(for: request)
        } catch {
            CaptureLog.info("URLFileDownloader: download failed for \(trimmed): \(error.localizedDescription)")
            return
        }

        guard let http = response as? HTTPURLResponse else {
            CaptureLog.info("URLFileDownloader: non-HTTP response for \(trimmed)")
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        guard (200..<300).contains(http.statusCode) else {
            CaptureLog.info("URLFileDownloader: HTTP \(http.statusCode) for \(trimmed)")
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        // Reject HTML pages masquerading as file URLs (e.g. auth gates).
        if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.hasPrefix("text/html") {
            CaptureLog.info("URLFileDownloader: Content-Type is HTML, skipping \(trimmed)")
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        if http.expectedContentLength > 0 && http.expectedContentLength > Self.maxDownloadBytes {
            CaptureLog.info("URLFileDownloader: \(http.expectedContentLength) bytes exceeds cap, skipping \(trimmed)")
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        // Derive a display filename. Prefer Content-Disposition, then URL path, then synthesised.
        let displayName = Self.deriveFilename(from: http, url: url)

        // importDownloadedFile moves the temp file into the media folder,
        // so we don't need a second removeItem on the tempURL afterwards.
        guard let record = await FileMonitor.shared.importDownloadedFile(
            from: tempURL,
            displayFilename: displayName,
            originalUrl: trimmed
        ) else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        guard let fileId = record.id else { return }

        db.updateHighlightFileLink(
            id: highlightId,
            fileId: fileId,
            contentType: record.contentType
        )

        CaptureLog.info("URLFileDownloader: attached \(record.fileName) to highlight \(highlightId)")

        await MainActor.run {
            NotificationCenter.default.post(name: .highlightDidSave, object: nil)
        }
    }

    /// Prefer Content-Disposition `filename=…`, otherwise the URL's last path
    /// component, otherwise a synthesised name with the URL extension.
    private static func deriveFilename(from http: HTTPURLResponse, url: URL) -> String? {
        if let disp = http.value(forHTTPHeaderField: "Content-Disposition") {
            if let name = parseContentDispositionFilename(disp), !name.isEmpty {
                return name
            }
        }
        let last = url.lastPathComponent
        if !last.isEmpty && last != "/" {
            return last
        }
        let ext = url.pathExtension.lowercased()
        let stem = String(UUID().uuidString.prefix(6))
        return ext.isEmpty ? "download-\(stem)" : "download-\(stem).\(ext)"
    }

    /// Extract `filename` from a Content-Disposition header. Handles both
    /// `filename="x.pdf"` and `filename*=UTF-8''x.pdf`.
    private static func parseContentDispositionFilename(_ header: String) -> String? {
        // RFC 5987: filename*=UTF-8''...
        if let range = header.range(of: "filename\\*=[^']*''", options: .regularExpression) {
            let tail = header[range.upperBound...]
            let raw = tail.split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespaces)
            if let raw, let decoded = raw.removingPercentEncoding, !decoded.isEmpty {
                return decoded
            }
        }
        // Plain: filename="x.pdf" or filename=x.pdf
        if let range = header.range(of: "filename=", options: .caseInsensitive) {
            var tail = header[range.upperBound...]
            if let semi = tail.firstIndex(of: ";") { tail = tail[..<semi] }
            var name = tail.trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\"") && name.hasSuffix("\"") && name.count >= 2 {
                name = String(name.dropFirst().dropLast())
            }
            return name.isEmpty ? nil : name
        }
        return nil
    }
}
