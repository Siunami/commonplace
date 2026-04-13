import Foundation
import CommonCrypto
import AppKit

/// Publishes collections to Cloudflare R2 (S3-compatible).
/// Each published collection gets:
///   - `/{slug}/manifest.json` — live JSON API
///   - `/{slug}/index.html`    — shareable web view
///   - `/{slug}/files/`        — uploaded assets
final class CollectionPublisher {
    static let shared = CollectionPublisher()

    private static let endpointKey = "r2Endpoint"
    private static let accessKeyIdKey = "r2AccessKeyId"
    private static let secretKeyKey = "r2SecretKey"
    private static let bucketKey = "r2Bucket"
    private static let publicUrlKey = "r2PublicUrl"

    private var pendingSyncs: Set<String> = []
    private var syncTimer: Timer?
    private let db = DatabaseManager.shared

    // MARK: - Configuration

    var endpoint: String {
        get { UserDefaults.standard.string(forKey: Self.endpointKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.endpointKey) }
    }

    var accessKeyId: String {
        get { UserDefaults.standard.string(forKey: Self.accessKeyIdKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.accessKeyIdKey) }
    }

    var secretKey: String {
        get { UserDefaults.standard.string(forKey: Self.secretKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.secretKeyKey) }
    }

    var bucket: String {
        get { UserDefaults.standard.string(forKey: Self.bucketKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.bucketKey) }
    }

    var publicUrl: String {
        get { UserDefaults.standard.string(forKey: Self.publicUrlKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.publicUrlKey) }
    }

    var isConfigured: Bool {
        !endpoint.isEmpty && !accessKeyId.isEmpty && !secretKey.isEmpty && !bucket.isEmpty
    }

    // MARK: - Publish / Unpublish

    func publishCollection(_ tag: Tag) async {
        guard isConfigured else {
            CaptureLog.warning("CollectionPublisher: R2 not configured")
            return
        }

        db.setTagPublished(id: tag.id, published: true)
        await syncCollection(tag)
    }

    func unpublishCollection(_ tag: Tag) {
        db.setTagPublished(id: tag.id, published: false)
    }

    // MARK: - Sync

    func queueSync(tagId: String) {
        guard isConfigured else { return }
        pendingSyncs.insert(tagId)
        scheduleSyncTimer()
    }

    private func scheduleSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.flushPendingSyncs()
        }
    }

    private func flushPendingSyncs() {
        let tagIds = pendingSyncs
        pendingSyncs.removeAll()

        Task {
            for tagId in tagIds {
                guard let tag = db.allTags().first(where: { $0.id == tagId }),
                      tag.isPublished == true else { continue }
                await syncCollection(tag)
            }
        }
    }

    private func syncCollection(_ tag: Tag) async {
        let slug = tag.slug
        let highlights = db.highlightsForTag(tagId: tag.id)

        CaptureLog.info("CollectionPublisher: syncing \(tag.name) (\(highlights.count) items)")

        // Upload files
        var items: [[String: Any]] = []
        for highlight in highlights {
            let item = await uploadHighlight(highlight, slug: slug)
            items.append(item)
        }

        // Generate and upload manifest
        let manifest = generateManifest(tag: tag, items: items)
        await upload(data: manifest, remotePath: "\(slug)/manifest.json", contentType: "application/json")

        // Generate and upload web view
        let html = generateWebView(tag: tag)
        await upload(data: html, remotePath: "\(slug)/index.html", contentType: "text/html")

        CaptureLog.info("CollectionPublisher: published \(tag.name) — \(items.count) items")
    }

    // MARK: - Upload Highlight

    private func uploadHighlight(_ highlight: Highlight, slug: String) async -> [String: Any] {
        let baseUrl = publicUrl.isEmpty ? endpoint : publicUrl
        var item: [String: Any] = [
            "id": highlight.id,
            "type": highlight.highlightType,
            "capturedAt": ISO8601DateFormatter().string(from: highlight.date)
        ]

        if let app = highlight.sourceApp { item["sourceApp"] = app }
        if let url = highlight.sourceUrl { item["sourceUrl"] = url }
        if let wt = highlight.windowTitle { item["windowTitle"] = wt }
        if let ct = highlight.contentType { item["contentType"] = ct }

        // Notes
        let notes = db.notesForHighlight(id: highlight.id)
        if !notes.isEmpty {
            item["notes"] = notes.map { $0.body }
        }
        if let userNote = highlight.userNote, !userNote.isEmpty {
            var allNotes = (item["notes"] as? [String]) ?? []
            if !allNotes.contains(userNote) { allNotes.insert(userNote, at: 0) }
            item["notes"] = allNotes
        }

        // Handle file-based captures
        let filePath: String?
        if highlight.highlightType == "screenshot" || highlight.highlightType == "file" {
            filePath = highlight.contentText
        } else if highlight.highlightType == "recording",
                  let recId = highlight.recordingId,
                  let rec = db.recording(byId: recId) {
            filePath = rec.filePath
        } else {
            filePath = nil
            item["content"] = String(highlight.contentText.prefix(2000))
        }

        if let filePath, FileManager.default.fileExists(atPath: filePath) {
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            let remotePath = "\(slug)/files/\(fileName)"
            let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath))
            if let fileData {
                await upload(data: fileData, remotePath: remotePath, contentType: mimeType(for: filePath))
                item["fileUrl"] = "\(baseUrl)/\(remotePath)"
                item["title"] = fileName
                item["fileSize"] = fileData.count
            }

            // Upload thumbnail if available
            if let fileId = highlight.fileId,
               let fileRec = db.fileRecord(byId: fileId),
               let thumbPath = fileRec.thumbnailPath,
               FileManager.default.fileExists(atPath: thumbPath) {
                let thumbName = "\(URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent)-thumb.jpg"
                let thumbRemote = "\(slug)/files/\(thumbName)"
                if let thumbData = try? Data(contentsOf: URL(fileURLWithPath: thumbPath)) {
                    await upload(data: thumbData, remotePath: thumbRemote, contentType: "image/jpeg")
                    item["thumbnailUrl"] = "\(baseUrl)/\(thumbRemote)"
                }
            }
        } else if highlight.highlightType == "screenshot" {
            item["title"] = highlight.windowTitle ?? "Screenshot"
        }

        return item
    }

    // MARK: - Manifest

    private func generateManifest(tag: Tag, items: [[String: Any]]) -> Data {
        let manifest: [String: Any] = [
            "name": tag.name,
            "slug": tag.slug,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "itemCount": items.count,
            "items": items
        ]
        return (try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    // MARK: - Web View

    private func generateWebView(tag: Tag) -> Data {
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(tag.name)</title>
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
               background: #1a1a1a; color: #e0e0e0; padding: 24px; }
        h1 { font-size: 1.5rem; font-weight: 600; margin-bottom: 4px; }
        .meta { font-size: 0.75rem; color: #888; margin-bottom: 24px; }
        .grid { columns: 280px; column-gap: 16px; }
        .card { break-inside: avoid; margin-bottom: 16px; background: #252525;
                border-radius: 12px; overflow: hidden; border: 1px solid #333; }
        .card img { width: 100%; display: block; }
        .card-body { padding: 12px; }
        .card-title { font-size: 0.85rem; font-weight: 500; margin-bottom: 4px;
                      word-break: break-word; }
        .card-title a { color: #e0e0e0; text-decoration: none; }
        .card-title a:hover { color: #fff; text-decoration: underline; }
        .card-note { font-size: 0.8rem; color: #ccc; margin-top: 6px;
                     border-left: 3px solid #e67e22; padding-left: 8px; }
        .card-meta { font-size: 0.7rem; color: #666; margin-top: 6px; }
        .card-text { font-size: 0.8rem; color: #bbb; white-space: pre-wrap;
                     max-height: 200px; overflow: hidden; }
        .badge { display: inline-block; font-size: 0.65rem; background: #333;
                 color: #aaa; padding: 2px 6px; border-radius: 4px; margin-right: 4px; }
        </style>
        </head>
        <body>
        <h1 id="title"></h1>
        <p class="meta" id="meta"></p>
        <div class="grid" id="grid"></div>
        <script>
        fetch('manifest.json').then(r => r.json()).then(data => {
          document.getElementById('title').textContent = data.name;
          document.getElementById('meta').textContent =
            data.itemCount + ' items · Updated ' + new Date(data.updatedAt).toLocaleDateString();
          const grid = document.getElementById('grid');
          data.items.forEach(item => {
            const card = document.createElement('div');
            card.className = 'card';
            let html = '';
            if (item.thumbnailUrl) {
              html += '<a href="' + (item.fileUrl || '#') + '" target="_blank">'
                   + '<img src="' + item.thumbnailUrl + '" loading="lazy"></a>';
            }
            html += '<div class="card-body">';
            if (item.title) {
              const link = item.fileUrl ? '<a href="' + item.fileUrl + '" target="_blank">'
                         + item.title + '</a>' : item.title;
              html += '<div class="card-title">' + link + '</div>';
            }
            if (item.content) {
              html += '<div class="card-text">' + item.content.substring(0, 500) + '</div>';
            }
            if (item.notes && item.notes.length > 0) {
              item.notes.forEach(n => {
                html += '<div class="card-note">' + n + '</div>';
              });
            }
            let meta = [];
            if (item.contentType) meta.push('<span class="badge">' + item.contentType + '</span>');
            if (item.sourceApp) meta.push(item.sourceApp);
            if (meta.length) html += '<div class="card-meta">' + meta.join(' · ') + '</div>';
            html += '</div>';
            card.innerHTML = html;
            grid.appendChild(card);
          });
        });
        </script>
        </body>
        </html>
        """
        return Data(html.utf8)
    }

    // MARK: - S3 Upload (AWS Signature V4)

    private func upload(data: Data, remotePath: String, contentType: String) async {
        guard isConfigured else { return }
        guard let url = URL(string: "\(endpoint)/\(bucket)/\(remotePath)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        signRequest(&request, body: data)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                CaptureLog.warning("CollectionPublisher: upload failed \(remotePath) — HTTP \(http.statusCode)")
            }
        } catch {
            CaptureLog.warning("CollectionPublisher: upload error \(remotePath) — \(error.localizedDescription)")
        }
    }

    private func signRequest(_ request: inout URLRequest, body: Data) {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let amzDate = dateFormatter.string(from: now)
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: now)

        guard let url = request.url,
              let host = url.host else { return }

        let payloadHash = sha256Hex(body)
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

        let method = request.httpMethod ?? "PUT"
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query ?? ""

        let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = [
            "content-type:\(request.value(forHTTPHeaderField: "Content-Type") ?? "")",
            "host:\(host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)"
        ].joined(separator: "\n") + "\n"

        let canonicalRequest = [method, path, query, canonicalHeaders, signedHeaders, payloadHash]
            .joined(separator: "\n")

        let region = "auto"
        let service = "s3"
        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(scope)\n\(sha256Hex(Data(canonicalRequest.utf8)))"

        let signingKey = deriveSigningKey(dateStamp: dateStamp, region: region, service: service)
        let signature = hmacSHA256(key: signingKey, data: Data(stringToSign.utf8)).map { String(format: "%02x", $0) }.joined()

        let auth = "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(auth, forHTTPHeaderField: "Authorization")
    }

    private func deriveSigningKey(dateStamp: String, region: String, service: String) -> [UInt8] {
        let kDate = hmacSHA256(key: Array("AWS4\(secretKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        return hmacSHA256(key: kService, data: Data("aws4_request".utf8))
    }

    private func hmacSHA256(key: [UInt8], data: Data) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { dataPtr in
            CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), key, key.count, dataPtr.baseAddress, data.count, &result)
        }
        return result
    }

    private func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func mimeType(for path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "json": return "application/json"
        case "html": return "text/html"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Test Connection

    func testConnection() async -> Bool {
        guard isConfigured else { return false }
        guard let url = URL(string: "\(endpoint)/\(bucket)/?list-type=2&max-keys=1") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        signRequest(&request, body: Data())

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return http.statusCode < 300
            }
            return false
        } catch {
            return false
        }
    }
}
