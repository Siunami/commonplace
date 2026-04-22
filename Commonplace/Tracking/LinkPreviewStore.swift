import Foundation
import LinkPresentation
import AppKit

/// Resolves and caches link metadata (title, favicon, hero image) for URLs
/// copied to the system. Backed by the `link_preview` DB table plus
/// JPEG files written under `~/Library/Application Support/com.dubberly.Capture/linkpreviews`.
///
/// Fetching is lazy (triggered by view `.task`) with in-flight dedupe, so many
/// cards scrolling into view at once won't spawn duplicate requests. A launch-
/// time background sweep handles historical copies at ~1 fetch/sec.
@MainActor
final class LinkPreviewStore {
    static let shared = LinkPreviewStore()

    private var inFlight: [String: Task<LinkPreview?, Never>] = [:]
    private let db = DatabaseManager.shared

    private static let staleAge: TimeInterval = 30 * 86_400   // 30 days
    private static let errorCooldown: TimeInterval = 3600     // 1 hour

    static let storageURL: URL = {
        let url = DatabaseManager.appSupportURL.appendingPathComponent("linkpreviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    // MARK: - Public API

    /// Returns the preview for a URL, using the DB cache when possible and
    /// fetching via `LPMetadataProvider` otherwise. Safe to call many times
    /// concurrently for the same URL — duplicates collapse.
    func preview(for urlString: String) async -> LinkPreview? {
        let now = Date().timeIntervalSince1970

        if let cached = db.linkPreview(forURL: urlString) {
            if cached.fetchError == nil, now - cached.fetchedAt < Self.staleAge {
                return cached
            }
            if cached.fetchError != nil, now - cached.fetchedAt < Self.errorCooldown {
                return cached
            }
        }

        if let task = inFlight[urlString] {
            return await task.value
        }

        let task = Task { [weak self] () -> LinkPreview? in
            let result = await self?.fetch(urlString)
            self?.inFlight.removeValue(forKey: urlString)
            return result
        }
        inFlight[urlString] = task
        return await task.value
    }

    /// Scans the DB for every URL copy that doesn't yet have a cached preview
    /// and fetches them at ~1/sec. Idempotent — re-runs on every launch are
    /// cheap once the backlog is drained.
    func backfillExistingURLs() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let urls = await self.db.distinctURLCopiesNeedingPreview()
            guard !urls.isEmpty else { return }
            await MainActor.run {
                CaptureLog.info("[LinkPreviewStore] Backfilling \(urls.count) URL copies")
            }
            for url in urls {
                _ = await self.preview(for: url)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            await MainActor.run {
                CaptureLog.info("[LinkPreviewStore] Backfill sweep complete")
            }
        }
    }

    // MARK: - Private

    private func fetch(_ urlString: String) async -> LinkPreview? {
        guard let url = URL(string: urlString) else { return nil }

        let provider = LPMetadataProvider()
        provider.timeout = 8

        let metadata: LPLinkMetadata
        do {
            metadata = try await provider.startFetchingMetadata(for: url)
        } catch {
            CaptureLog.warning("[LinkPreviewStore] fetch failed for \(urlString): \(error.localizedDescription)")
            var errPreview = LinkPreview(
                url: urlString,
                title: nil,
                siteName: url.host?.replacingOccurrences(of: "www.", with: ""),
                imagePath: nil,
                faviconPath: nil,
                fetchedAt: Date().timeIntervalSince1970,
                fetchError: error.localizedDescription
            )
            db.insertLinkPreview(&errPreview)
            return errPreview
        }

        let title = metadata.title
        let siteName = url.host?.replacingOccurrences(of: "www.", with: "")
        let hero = await Self.saveImage(provider: metadata.imageProvider, urlString: urlString, suffix: "hero")
        let favicon = await Self.saveImage(provider: metadata.iconProvider, urlString: urlString, suffix: "icon")
        let og = await Self.fetchOpenGraph(url: url)

        var preview = LinkPreview(
            url: urlString,
            title: title,
            siteName: og.siteName ?? siteName,
            imagePath: hero?.path,
            faviconPath: favicon?.path,
            fetchedAt: Date().timeIntervalSince1970,
            fetchError: nil,
            imageWidth: hero?.width,
            imageHeight: hero?.height,
            ogDescription: og.description,
            ogAuthor: og.author,
            ogPublishedAt: og.publishedAt,
            ogType: og.type
        )
        db.insertLinkPreview(&preview)
        CaptureLog.info("[LinkPreviewStore] cached preview for \(siteName ?? urlString)")
        return preview
    }

    // MARK: - Open Graph scrape

    /// Extra OG tags pulled from the page <head>. Runs in parallel with the
    /// `LPMetadataProvider` pass and supplements it — missing fields are fine
    /// (we fall back to whatever LP gave us). Budgeted to a short timeout so
    /// a slow origin can't hold up a card's first render.
    private struct OpenGraphFields {
        var description: String?
        var author: String?
        var publishedAt: Double?
        var type: String?
        var siteName: String?
    }

    private static func fetchOpenGraph(url: URL) async -> OpenGraphFields {
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        // Many sites (news, paywalls) return a reduced payload without a
        // desktop UA. This matches what LPMetadataProvider sends internally.
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            return OpenGraphFields()
        }

        // Bail on obvious non-HTML — images, JSON APIs, file downloads, etc.
        if let http = response as? HTTPURLResponse,
           let ct = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           !ct.contains("html") && !ct.contains("xml") {
            return OpenGraphFields()
        }

        // Cap parsing at the first ~256KB so huge pages don't burn time; OG
        // tags live in <head>, always near the start.
        let cap = min(data.count, 256 * 1024)
        let slice = data.prefix(cap)
        guard let html = String(data: slice, encoding: .utf8)
            ?? String(data: slice, encoding: .isoLatin1)
        else { return OpenGraphFields() }

        // Trim to <head> when we can find it — avoids scanning entire body.
        let headEnd = html.range(of: "</head>", options: .caseInsensitive)?.upperBound
        let scope = headEnd.map { String(html[..<$0]) } ?? html

        var fields = OpenGraphFields()
        fields.description = metaContent(in: scope, keys: ["og:description", "twitter:description", "description"])
        fields.author = metaContent(in: scope, keys: ["article:author", "author", "twitter:creator"])
        fields.type = metaContent(in: scope, keys: ["og:type"])
        fields.siteName = metaContent(in: scope, keys: ["og:site_name"])
        if let published = metaContent(in: scope, keys: ["article:published_time", "og:published_time", "article:modified_time"]) {
            fields.publishedAt = ISO8601DateFormatter().date(from: published)?.timeIntervalSince1970
        }
        return fields
    }

    /// Pulls the first non-empty `<meta … content="…">` for any of the given
    /// property/name keys. Handles both `property="…"` and `name="…"` and
    /// either attribute order (content-before-key vs. key-before-content).
    private static func metaContent(in html: String, keys: [String]) -> String? {
        for key in keys {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            // Either `<meta … property|name="key" … content="…">` or the
            // inverse attribute order.
            let patterns = [
                "<meta[^>]+?(?:property|name)=[\"']\(escaped)[\"'][^>]*?content=[\"']([^\"']*)[\"']",
                "<meta[^>]+?content=[\"']([^\"']*)[\"'][^>]*?(?:property|name)=[\"']\(escaped)[\"']",
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
                else { continue }
                let range = NSRange(html.startIndex..., in: html)
                if let match = regex.firstMatch(in: html, options: [], range: range),
                   match.numberOfRanges >= 2,
                   let r = Range(match.range(at: 1), in: html) {
                    let raw = String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !raw.isEmpty {
                        return decodeHTMLEntities(raw)
                    }
                }
            }
        }
        return nil
    }

    private static func decodeHTMLEntities(_ s: String) -> String {
        var out = s
        let replacements: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&#x27;", "'"),
            ("&nbsp;", " "),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;", "…"),
            ("&rsquo;", "’"),
            ("&lsquo;", "‘"),
            ("&rdquo;", "”"),
            ("&ldquo;", "“"),
        ]
        for (from, to) in replacements { out = out.replacingOccurrences(of: from, with: to) }
        return out
    }

    /// Persists a provider-loaded NSImage as JPEG and returns its path +
    /// intrinsic pixel dimensions. Dimensions flow back so the LinkPreview
    /// row can persist them — otherwise the masonry card has no way to
    /// reserve an aspect-correct frame before the hero decodes.
    private static func saveImage(
        provider: NSItemProvider?,
        urlString: String,
        suffix: String
    ) async -> (path: String, width: Int, height: Int)? {
        guard let provider, provider.canLoadObject(ofClass: NSImage.self) else { return nil }

        let image: NSImage? = await withCheckedContinuation { cont in
            provider.loadObject(ofClass: NSImage.self) { obj, _ in
                cont.resume(returning: obj as? NSImage)
            }
        }

        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { return nil }

        // pixelsWide/pixelsHigh reflect the bitmap's true pixel count;
        // image.size would return points (scaled by the default 72 DPI
        // representation), which is wrong for our use.
        let width = rep.pixelsWide
        let height = rep.pixelsHigh

        let hash = String(format: "%x", UInt(bitPattern: urlString.hashValue))
        let path = storageURL.appendingPathComponent("\(hash)-\(suffix).jpg")
        do {
            try jpeg.write(to: path, options: .atomic)
            return (path.path, width, height)
        } catch {
            CaptureLog.warning("[LinkPreviewStore] failed to save \(suffix) image: \(error.localizedDescription)")
            return nil
        }
    }
}
