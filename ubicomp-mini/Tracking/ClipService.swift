import AppKit
import ImageIO
import UniformTypeIdentifiers

final class ClipService: NSObject {
    static let shared = ClipService()

    /// Called by macOS Services when user selects "Clip to Commonplace"
    @objc func clipContent(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        // Prefer image if available
        if let image = NSImage(pasteboard: pboard) {
            clipImage(image)
            return
        }
        // Fall back to text
        if let text = pboard.string(forType: .string), !text.isEmpty {
            clipText(text)
            return
        }
        error.pointee = "No supported content on pasteboard" as NSString
    }

    private func clipText(_ text: String) {
        let context = CaptureContext.current()
        let entryId = UUID().uuidString
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        HighlightCapture.shared.captureFromCopy(
            content: text, sourceApp: sourceApp,
            entryId: entryId, context: context
        )
        CaptureLog.info("Clipped text via Services (\(text.count) chars)")
    }

    private func clipImage(_ image: NSImage) {
        Task {
            await saveAndShowClippedImage(image)
        }
    }

    private func saveAndShowClippedImage(_ image: NSImage) async {
        guard let cgImage = image.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ) else { return }

        let context = CaptureContext.current()
        let now = Date()
        let dayString = ScreenshotCapture.dayString(for: now)
        let timeString = Self.timeFormatter.string(from: now)

        let dir = ScreenshotCapture.screenshotsBaseURL
            .appendingPathComponent(dayString)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let filePath = dir.appendingPathComponent("\(timeString)-clip.png")

        guard let dest = CGImageDestinationCreateWithURL(
            filePath as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return }

        let fileSize = (try? FileManager.default.attributesOfItem(
            atPath: filePath.path
        ))?[.size] as? Int64 ?? 0

        let ocrText = await TextExtractor.shared.extract(from: cgImage)

        var record = ScreenshotRecord(
            timestamp: now.timeIntervalSince1970,
            dayString: dayString,
            filePath: filePath.path,
            fileSize: fileSize,
            displayId: "clip",
            ocrText: ocrText,
            captureType: "clip",
            windowTitle: context.windowTitle,
            bundleId: context.bundleId,
            captureRect: nil,
            scaleFactor: nil
        )
        DatabaseManager.shared.insertScreenshot(&record)

        HighlightCapture.shared.captureFromUserScreenshot(
            filePath: filePath.path,
            image: image,
            screenshotId: record.id,
            context: context,
            badgeLabel: "Clip"
        )

        CaptureLog.info("Clipped image via Services, saved to \(filePath.lastPathComponent)")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH-mm-ss"
        return f
    }()
}
