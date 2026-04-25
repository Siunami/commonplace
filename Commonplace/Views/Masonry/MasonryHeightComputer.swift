import AppKit
import CoreGraphics
import Foundation

/// Pre-computes a masonry card's natural height in pure Swift so
/// `MasonryLayout` doesn't have to walk into SwiftUI's `sizeThatFits`
/// on every layout pass. Running the computation on a background
/// `Task.detached` during pagination means heights are ready before
/// the mosaic renders — the user never sees the main thread peg while
/// SwiftUI measures 20+ cards in sequence.
///
/// The constants below mirror the chrome inside each card variant in
/// `BrowseView.swift`. Keep them in sync: a discrepancy shows up as
/// visible overlap or gaps between cards. When either side changes
/// (card body or height formula), update both.
enum MasonryHeightComputer {
    struct Inputs {
        let highlight: Highlight
        let noteCount: Int
        /// Pre-resolved intrinsic aspect ratio from the pagination
        /// batch, when available. Nil for highlights that haven't
        /// resolved one yet — formula falls back to a type-specific
        /// default matching the card's `fallbackAspectRatio`.
        let aspectRatio: CGFloat?
        let hasAnnotation: Bool
        let annotationText: String?
    }

    static func height(for inputs: Inputs, columnWidth: CGFloat) -> CGFloat {
        guard columnWidth > 0 else { return 0 }
        let content = contentHeight(for: inputs, columnWidth: columnWidth)
        let annotation = (inputs.hasAnnotation || inputs.noteCount > 1)
            ? annotationStripHeight(inputs: inputs, columnWidth: columnWidth)
            : 0
        return content + annotation
    }

    // MARK: - Routing

    private static func contentHeight(for inputs: Inputs, columnWidth: CGFloat) -> CGFloat {
        let h = inputs.highlight
        switch h.highlightType {
        case "screenshot", "recording":
            return screenshotHeight(columnWidth: columnWidth, aspectRatio: inputs.aspectRatio)
        case "highlight":
            // `HighlightCard` routes to ScreenshotCard when the text is
            // actually a file path to an image — matches the runtime
            // check in `TextHighlightRouter.isImageFilePath`.
            if isImageFilePath(h.contentText) {
                return screenshotHeight(columnWidth: columnWidth, aspectRatio: inputs.aspectRatio)
            }
            return textCardHeight(text: h.contentText, columnWidth: columnWidth, hasAccentBar: true)
        case "note":
            return textCardHeight(text: h.contentText, columnWidth: columnWidth, hasAccentBar: false)
        case "file":
            return fileCardHeight(columnWidth: columnWidth, aspectRatio: inputs.aspectRatio)
        default:
            if isURLCopy(h) {
                return linkCardHeight(columnWidth: columnWidth, aspectRatio: inputs.aspectRatio)
            }
            // TextCard path.
            if isImageFilePath(h.contentText) {
                return screenshotHeight(columnWidth: columnWidth, aspectRatio: inputs.aspectRatio)
            }
            return textCardHeight(text: h.contentText, columnWidth: columnWidth, hasAccentBar: true)
        }
    }

    // MARK: - Aspect-ratio buckets
    // Must match each card variant's `aspectRatioBuckets` + `fallbackAspectRatio`
    // in BrowseView.swift so the computed height aligns with the rendered cover.

    private static let screenshotBuckets: [CGFloat] = [0.82, 1.25, 1.78]
    private static let screenshotFallback: CGFloat = 1.42

    private static let fileBuckets: [CGFloat] = [1.0, 1.28, 1.58]
    private static let fileFallback: CGFloat = 1.28

    private static let linkBuckets: [CGFloat] = [1.33, 1.58, 1.82]
    private static let linkFallback: CGFloat = 1.45

    /// Mirrors `CardCoverPreview.nearestAspectRatio` — pick the bucket
    /// with the smallest absolute diff so the pre-computed height
    /// matches the rendered cover exactly.
    private static func snapAspect(raw: CGFloat, buckets: [CGFloat], fallback: CGFloat) -> CGFloat {
        let sorted = buckets.isEmpty ? [fallback] : buckets.sorted()
        return sorted.min(by: { abs($0 - raw) < abs($1 - raw) }) ?? fallback
    }

    // MARK: - Per-card-type content heights

    private static func screenshotHeight(columnWidth: CGFloat, aspectRatio: CGFloat?) -> CGFloat {
        let ratio = snapAspect(
            raw: aspectRatio ?? screenshotFallback,
            buckets: screenshotBuckets,
            fallback: screenshotFallback
        )
        return columnWidth / ratio
    }

    /// FileCard = cover + filename row.
    /// Filename row: `.lineLimit(2, reservesSpace: true)` @ .caption (~13pt line)
    /// + 8pt top padding + 2pt bottom padding + ~14pt slack for body spacing and
    /// the extension label when present. 52pt total is empirically accurate.
    private static func fileCardHeight(columnWidth: CGFloat, aspectRatio: CGFloat?) -> CGFloat {
        let ratio = snapAspect(
            raw: aspectRatio ?? fileFallback,
            buckets: fileBuckets,
            fallback: fileFallback
        )
        return (columnWidth / ratio) + 52
    }

    /// LinkCard = cover + text block (host row + title + optional desc + app).
    /// Text block is ~92pt when title fills 2 lines. Variable when desc lands
    /// async, but reserving this much absorbs the typical case without extra
    /// slack. Underestimates cause overlap; overestimates cause tiny gaps —
    /// prefer overestimation slightly.
    private static func linkCardHeight(columnWidth: CGFloat, aspectRatio: CGFloat?) -> CGFloat {
        let ratio = snapAspect(
            raw: aspectRatio ?? linkFallback,
            buckets: linkBuckets,
            fallback: linkFallback
        )
        return (columnWidth / ratio) + 92
    }

    /// Text-driven cards: measured via `NSAttributedString.boundingRect`, which
    /// runs pure AppKit text layout with no SwiftUI involvement. Font + line
    /// limit + padding match `TextCardStyle.style(for:)` in BrowseView.swift.
    private static func textCardHeight(text: String, columnWidth: CGFloat, hasAccentBar: Bool) -> CGFloat {
        let style = textCardStyle(for: text)
        // TextCard / HighlightCard wrap text in an HStack with a 2pt accent
        // bar on the leading edge. NoteCard doesn't. Either way the bar
        // reduces the text width available for measurement.
        let accentBarWidth: CGFloat = hasAccentBar ? 2 : 0
        let availableWidth = max(1, columnWidth - style.horizontalPadding * 2 - accentBarWidth)
        let measured = measureText(
            text,
            font: style.nsFont,
            width: availableWidth,
            lineLimit: style.lineLimit
        )
        return measured + style.verticalPadding * 2
    }

    // MARK: - Annotation strip
    // Matches the VStack below `cardContent` in `MasonryCard.body`:
    //   .padding(.leading, 14)            — leading text inset past accent bar
    //   .padding(.horizontal, 14)         — outer 14pt each side
    //   .padding(.vertical, 14)           — 14pt top + 14pt bottom
    //   Accent bar (2pt) leading overlay — no height impact
    //   If hasAnnotation: Text @ .callout serif, lineLimit 6
    //   If noteCount > 1: "+N more" Text @ .caption2
    //   VStack(spacing: 5)

    private static func annotationStripHeight(inputs: Inputs, columnWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 14
        let barLeadingInset: CGFloat = 14 // `.padding(.leading, 14)` + 2pt bar overlays inside it
        let availableWidth = max(1, columnWidth - horizontalPadding * 2 - barLeadingInset)

        var textHeight: CGFloat = 0
        if inputs.hasAnnotation, let text = inputs.annotationText, !text.isEmpty {
            // .callout ≈ 13-15pt depending on platform; 15pt gives a
            // safe upper bound that avoids underestimating.
            let annotationFont = NSFont.systemFont(ofSize: 15)
            textHeight += measureText(
                text,
                font: annotationFont,
                width: availableWidth,
                lineLimit: 6
            )
        }
        if inputs.noteCount > 1 {
            if textHeight > 0 {
                textHeight += 5 // VStack spacing between annotation text and "+N more"
            }
            // .caption2 line height ≈ 11pt font + leading
            let caption = NSFont.systemFont(ofSize: 11)
            textHeight += caption.ascender - caption.descender + caption.leading
        }

        return textHeight + 14 * 2 // vertical padding top + bottom
    }

    // MARK: - Text measurement

    /// Measures `text` bounded by `width` and clamped to `lineLimit` lines
    /// via `NSAttributedString.boundingRect`. Close enough to SwiftUI's
    /// `Text` layout for masonry packing (empirically <2pt drift).
    private static func measureText(_ text: String, font: NSFont, width: CGFloat, lineLimit: Int) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return 0 }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let bounding = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let rawHeight = ceil(bounding.height)
        let lineHeight = font.ascender - font.descender + font.leading
        let maxHeight = ceil(lineHeight * CGFloat(lineLimit))
        return min(rawHeight, maxHeight)
    }

    // MARK: - TextCardStyle equivalent
    // Mirrors `TextCardStyle.style(for:)` in BrowseView.swift. Keep in sync.

    private struct TextStyle {
        let nsFont: NSFont
        let lineLimit: Int
        let verticalPadding: CGFloat
        let horizontalPadding: CGFloat
    }

    private static func textCardStyle(for text: String) -> TextStyle {
        let count = text.count
        if count < 60 {
            return TextStyle(
                nsFont: NSFont(name: "Times New Roman", size: 20)
                    ?? NSFont.systemFont(ofSize: 20, weight: .medium),
                lineLimit: 6,
                verticalPadding: 12,
                horizontalPadding: 14
            )
        }
        if count < 200 {
            return TextStyle(
                nsFont: NSFont(name: "Times New Roman", size: 14)
                    ?? NSFont.systemFont(ofSize: 14),
                lineLimit: 10,
                verticalPadding: 10,
                horizontalPadding: 12
            )
        }
        return TextStyle(
            nsFont: NSFont(name: "Times New Roman", size: 13)
                ?? NSFont.systemFont(ofSize: 13),
            lineLimit: 14,
            verticalPadding: 10,
            horizontalPadding: 12
        )
    }

    // MARK: - URL-copy detection
    // Mirrors `MasonryCard.isURLCopy(_:)` so the default-case routing
    // here matches the runtime switch.

    /// Mirrors `TextHighlightRouter.isImageFilePath` in BrowseView.swift.
    /// Duplicated here because that helper is file-private. Some legacy
    /// highlights store an image file path as contentText; both Text /
    /// Highlight cards route to the image formula in that case.
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "bmp", "tiff", "tif", "webp"
    ]

    private static func isImageFilePath(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return false }
        guard !trimmed.contains("\n") else { return false }
        let ext = (trimmed as NSString).pathExtension.lowercased()
        guard imageExtensions.contains(ext) else { return false }
        return FileManager.default.fileExists(atPath: trimmed)
    }

    private static func isURLCopy(_ h: Highlight) -> Bool {
        if h.contentType == "url" { return true }
        let trimmed = h.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else { return false }
        return !trimmed.contains(" ") && !trimmed.contains("\n")
    }
}
