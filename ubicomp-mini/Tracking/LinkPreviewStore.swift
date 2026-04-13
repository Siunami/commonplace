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
        let imagePath = await Self.saveImage(provider: metadata.imageProvider, urlString: urlString, suffix: "hero")
        let faviconPath = await Self.saveImage(provider: metadata.iconProvider, urlString: urlString, suffix: "icon")

        var preview = LinkPreview(
            url: urlString,
            title: title,
            siteName: siteName,
            imagePath: imagePath,
            faviconPath: faviconPath,
            fetchedAt: Date().timeIntervalSince1970,
            fetchError: nil
        )
        db.insertLinkPreview(&preview)
        CaptureLog.info("[LinkPreviewStore] cached preview for \(siteName ?? urlString)")
        return preview
    }

    private static func saveImage(provider: NSItemProvider?, urlString: String, suffix: String) async -> String? {
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

        let hash = String(format: "%x", UInt(bitPattern: urlString.hashValue))
        let path = storageURL.appendingPathComponent("\(hash)-\(suffix).jpg")
        do {
            try jpeg.write(to: path, options: .atomic)
            return path.path
        } catch {
            CaptureLog.warning("[LinkPreviewStore] failed to save \(suffix) image: \(error.localizedDescription)")
            return nil
        }
    }
}
