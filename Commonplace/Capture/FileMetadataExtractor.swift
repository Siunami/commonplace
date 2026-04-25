import Foundation
import AppKit
import ImageIO
import PDFKit
import AVFoundation
import CoreMedia

/// Best-effort metadata extraction for a file already at its persistent
/// path. Pulls xattr provenance (kMDItemWhereFroms, quarantine), file
/// identity (type/size/dimensions), and embedded metadata (EXIF/PDF/video)
/// and emits them as `SourceContextEntry` rows so the same detail-view
/// render path that serves browser captures can surface them.
///
/// Never throws; missing attributes just yield fewer entries.
enum FileMetadataExtractor {
    static func extract(path: String, contentType: String?) async -> [SourceContextEntry] {
        var entries: [SourceContextEntry] = []
        entries.append(contentsOf: provenanceEntries(path: path))
        entries.append(contentsOf: fileIdentityEntries(path: path, contentType: contentType))
        entries.append(contentsOf: await embeddedMetadataEntries(path: path, contentType: contentType))

        return entries.filter { entry in
            let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.lowercased() != "null"
        }
    }

    // MARK: - Tier 1: Provenance

    private static func provenanceEntries(path: String) -> [SourceContextEntry] {
        var entries: [SourceContextEntry] = []

        let whereFroms = FileMonitor.readWhereFroms(path: path)
        if let pageUrl = FileMonitor.preferredSourceUrl(from: whereFroms) {
            let display = URL(string: pageUrl)?.host ?? pageUrl
            entries.append(SourceContextEntry(
                key: "page_url",
                label: "Page",
                value: display,
                icon: "globe",
                url: pageUrl
            ))
        }
        // Direct download URL — only surfaced when it differs from the
        // referrer row above, so we don't double-show "pinterest.com" twice.
        if whereFroms.count >= 2,
           !whereFroms[0].isEmpty,
           whereFroms[0] != whereFroms[1] {
            let direct = whereFroms[0]
            let display = URL(string: direct)?.host ?? direct
            entries.append(SourceContextEntry(
                key: "download_url",
                label: "Direct file",
                value: display,
                icon: "arrow.down.circle",
                url: direct
            ))
        }

        if let quarantine = readQuarantine(path: path) {
            if let appName = quarantine.appName {
                entries.append(SourceContextEntry(
                    key: "download_app",
                    label: "Downloaded by",
                    value: appName,
                    icon: "app.badge.fill",
                    url: nil
                ))
            }
            if let date = quarantine.date {
                entries.append(SourceContextEntry(
                    key: "downloaded_at",
                    label: "Downloaded",
                    value: relativeString(for: date),
                    icon: "clock",
                    url: nil
                ))
            }
        }

        return entries
    }

    /// Parse `com.apple.quarantine` — format is
    /// `flags;hex_timestamp;AppName;UUID`. App name is omitted for some
    /// sideloaded binaries; treat every field as optional.
    private static func readQuarantine(path: String) -> (appName: String?, date: Date?)? {
        let attrName = "com.apple.quarantine"
        let size = getxattr(path, attrName, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = Data(count: size)
        let read = buffer.withUnsafeMutableBytes { ptr -> ssize_t in
            guard let base = ptr.baseAddress else { return -1 }
            return getxattr(path, attrName, base, size, 0, 0)
        }
        guard read > 0, let raw = String(data: buffer, encoding: .utf8) else { return nil }

        let parts = raw.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }

        var date: Date? = nil
        if let stamp = UInt64(parts[1], radix: 16) {
            date = Date(timeIntervalSince1970: TimeInterval(stamp))
        }

        var appName: String? = nil
        if parts.count >= 3 {
            let trimmed = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { appName = trimmed }
        }

        if appName == nil && date == nil { return nil }
        return (appName, date)
    }

    // MARK: - Tier 2: File identity

    private static func fileIdentityEntries(path: String, contentType: String?) -> [SourceContextEntry] {
        var entries: [SourceContextEntry] = []

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return entries }
        let fileSize = (attrs[.size] as? Int64) ?? 0
        let creationDate = attrs[.creationDate] as? Date
        let ext = (path as NSString).pathExtension.uppercased()

        var parts: [String] = []
        if let contentType, !contentType.isEmpty {
            parts.append(contentType)
        }
        if !ext.isEmpty {
            parts.append(ext)
        }
        if fileSize > 0 {
            parts.append(RecordingRecord.formatFileSize(fileSize))
        }
        if let dims = readImageDimensions(path: path, contentType: contentType) {
            parts.append("\(dims.width)×\(dims.height)")
        }
        if !parts.isEmpty {
            entries.append(SourceContextEntry(
                key: "file_info",
                label: "File",
                value: parts.joined(separator: " · "),
                icon: "doc",
                url: nil
            ))
        }

        // Skip "just now" noise on fresh downloads — the quarantine row
        // already tells that story more accurately.
        if let creationDate, Date().timeIntervalSince(creationDate) > 60 {
            entries.append(SourceContextEntry(
                key: "created",
                label: "Created",
                value: relativeString(for: creationDate),
                icon: "calendar",
                url: nil
            ))
        }

        return entries
    }

    private static func readImageDimensions(path: String, contentType: String?) -> (width: Int, height: Int)? {
        guard contentType == "image" else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { return nil }
        return (w, h)
    }

    // MARK: - Tier 3: Embedded metadata

    private static func embeddedMetadataEntries(path: String, contentType: String?) async -> [SourceContextEntry] {
        let url = URL(fileURLWithPath: path)
        switch contentType {
        case "image":
            return imageExifEntries(url: url)
        case "pdf":
            return pdfEntries(url: url)
        case "video":
            return await videoEntries(url: url)
        default:
            return []
        }
    }

    private static func imageExifEntries(url: URL) -> [SourceContextEntry] {
        var entries: [SourceContextEntry] = []

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return entries
        }

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        let make = (tiff?[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces)
        let model = (tiff?[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
        let camera = [make, model]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " ")
        if !camera.isEmpty {
            entries.append(SourceContextEntry(
                key: "camera",
                label: "Camera",
                value: camera,
                icon: "camera.fill",
                url: nil
            ))
        }

        if let dateStr = exif?[kCGImagePropertyExifDateTimeOriginal] as? String,
           let date = parseExifDate(dateStr) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            entries.append(SourceContextEntry(
                key: "photo_taken",
                label: "Taken",
                value: formatter.string(from: date),
                icon: "calendar",
                url: nil
            ))
        }

        if let software = tiff?[kCGImagePropertyTIFFSoftware] as? String {
            let trimmed = software.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                entries.append(SourceContextEntry(
                    key: "software",
                    label: "Software",
                    value: trimmed,
                    icon: "slider.horizontal.3",
                    url: nil
                ))
            }
        }

        if let lens = exif?[kCGImagePropertyExifLensModel] as? String {
            let trimmed = lens.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                entries.append(SourceContextEntry(
                    key: "lens",
                    label: "Lens",
                    value: trimmed,
                    icon: "camera.aperture",
                    url: nil
                ))
            }
        }

        return entries
    }

    /// EXIF date strings look like `"2024:03:14 17:22:08"` — not ISO-8601.
    private static func parseExifDate(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: str)
    }

    private static func pdfEntries(url: URL) -> [SourceContextEntry] {
        var entries: [SourceContextEntry] = []

        guard let doc = PDFDocument(url: url),
              let attrs = doc.documentAttributes else { return entries }

        let emit = { (key: String, label: String, pdfKey: PDFDocumentAttribute, icon: String) in
            guard let raw = attrs[pdfKey] as? String else { return }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            entries.append(SourceContextEntry(
                key: key,
                label: label,
                value: trimmed,
                icon: icon,
                url: nil
            ))
        }

        emit("pdf_title", "Title", .titleAttribute, "doc.text")
        emit("pdf_author", "Author", .authorAttribute, "person")
        emit("pdf_subject", "Subject", .subjectAttribute, "text.alignleft")

        return entries
    }

    private static func videoEntries(url: URL) async -> [SourceContextEntry] {
        var entries: [SourceContextEntry] = []
        let asset = AVURLAsset(url: url)

        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 {
                entries.append(SourceContextEntry(
                    key: "duration",
                    label: "Duration",
                    value: formatDuration(seconds),
                    icon: "clock",
                    url: nil
                ))
            }
        } catch {
            // duration load reads headers only — a failure here means the
            // file isn't a real media container, which is fine to ignore.
        }

        return entries
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Shared formatting

    private static func relativeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
