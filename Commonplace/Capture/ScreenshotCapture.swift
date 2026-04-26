import Foundation
import ScreenCaptureKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class ScreenshotCapture {
    static let shared = ScreenshotCapture()

    struct CaptureResult {
        let cgImage: CGImage
        let filePath: String
        let screenshotId: Int64?
        let ocrText: String?
        let context: CaptureContext
        /// Full list of apps with visible pixels inside the capture
        /// region, ordered by visible area descending. Empty when the
        /// capture didn't go through the source resolver (paste paths).
        /// JSON-encoded form lives on Highlight + ScreenshotRecord.
        let sources: [ScreenshotSource]
    }

    private let db = DatabaseManager.shared

    // MARK: - Active Display Detection

    /// Determines which display to capture for a full-screen screenshot.
    /// Uses cursor position as the primary signal — both NSEvent.mouseLocation
    /// and NSScreen.frame are in the same coordinate space, so no conversion needed.
    private func targetDisplay() -> CGDirectDisplayID {
        let cursorLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if screen.frame.contains(cursorLocation) {
                if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                    CaptureLog.info("targetDisplay: cursor on display \(displayID) (\(screen.localizedName))")
                    return displayID
                }
            }
        }

        if let mainScreen = NSScreen.main,
           let displayID = mainScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            CaptureLog.warning("targetDisplay: cursor matched no screen, using NSScreen.main (\(displayID))")
            return displayID
        }

        CaptureLog.warning("targetDisplay: no screen matched, using CGMainDisplayID()")
        return CGMainDisplayID()
    }

    // MARK: - Public

    func captureFullScreen() async -> CaptureResult? {
        guard CGPreflightScreenCaptureAccess() else {
            CaptureLog.warning("No screen recording permission")
            ScreenRecordingPermission.recordNoPermission()
            return nil
        }

        // Gather context before capture — frontmost window is known now
        let context = CaptureContext.current()
        let targetDisplayID = targetDisplay()

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == targetDisplayID })
                    ?? content.displays.first else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            // Resolve every app whose visible pixels land inside the
            // captured region. Full-screen captures use the display's
            // global frame as the region — global coords match SCWindow.frame.
            let displayFrame = displayGlobalFrame(for: targetDisplayID)
            let sources = ScreenshotSources.resolve(rect: displayFrame, windows: content.windows)

            let result = await saveAndOCR(
                image: image, captureType: "full",
                displayId: targetDisplayID, context: context,
                sources: sources
            )
            ScreenRecordingPermission.recordCaptureSuccess()
            return result
        } catch {
            CaptureLog.error("Screenshot capture error: \(error.localizedDescription)")
            ScreenRecordingPermission.recordCaptureFailure()
            return nil
        }
    }

    /// Display frame in the global screen coordinate space — the same
    /// space `SCWindow.frame` lives in. Falls back to the display's
    /// own pixel size at origin when the display id can't be matched
    /// to an `NSScreen` (rare; handles displays disconnected mid-flow).
    private func displayGlobalFrame(for displayID: CGDirectDisplayID) -> CGRect {
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  id == displayID else { continue }
            return screen.frame
        }
        let bounds = CGDisplayBounds(displayID)
        return bounds
    }

    func captureRegion(
        _ rect: CGRect,
        on screen: NSScreen? = nil,
        excludingWindowIDs: [CGWindowID] = [],
        context: CaptureContext? = nil
    ) async -> CaptureResult? {
        guard CGPreflightScreenCaptureAccess() else {
            CaptureLog.warning("No screen recording permission")
            ScreenRecordingPermission.recordNoPermission()
            return nil
        }

        let resolvedContext = context ?? CaptureContext.current()
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen else { return nil }

        let displayID: CGDirectDisplayID
        if let id = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            displayID = id
        } else {
            displayID = CGMainDisplayID()
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID })
                    ?? content.displays.first else { return nil }

            // Exclude overlay windows (e.g. region selection) from the capture
            let excludedWindows = content.windows.filter { excludingWindowIDs.contains(CGWindowID($0.windowID)) }
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false

            let fullImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            // Derive scale from actual captured image — robust on scaled display modes
            let imageWidth = CGFloat(fullImage.width)
            let imageHeight = CGFloat(fullImage.height)
            let scaleX = imageWidth / targetScreen.frame.width
            let scaleY = imageHeight / targetScreen.frame.height

            let localRect = CGRect(
                x: rect.origin.x - targetScreen.frame.origin.x,
                y: rect.origin.y - targetScreen.frame.origin.y,
                width: rect.width,
                height: rect.height
            )

            let pixelRect = CGRect(
                x: localRect.origin.x * scaleX,
                y: (targetScreen.frame.height - localRect.origin.y - localRect.height) * scaleY,
                width: localRect.width * scaleX,
                height: localRect.height * scaleY
            ).intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

            guard !pixelRect.isEmpty, let cropped = fullImage.cropping(to: pixelRect) else {
                CaptureLog.error("Screenshot cropping failed: pixelRect=\(pixelRect), image=\(imageWidth)×\(imageHeight)")
                return nil
            }

            // Encode capture rect as JSON for storage
            let rectJSON = "{\"x\":\(rect.origin.x),\"y\":\(rect.origin.y),\"width\":\(rect.width),\"height\":\(rect.height)}"

            // Resolve every app with visible pixels in the captured
            // region — uses the same window list and overlay-exclusion
            // set we already built for the SCContentFilter.
            let excludedSet = Set(excludingWindowIDs)
            let sources = ScreenshotSources.resolve(
                rect: rect,
                windows: content.windows,
                excluding: excludedSet
            )

            let result = await saveAndOCR(
                image: cropped, captureType: "region",
                displayId: displayID, context: resolvedContext,
                captureRect: rectJSON, scaleFactor: Double(scaleX),
                sources: sources
            )
            ScreenRecordingPermission.recordCaptureSuccess()
            return result
        } catch {
            CaptureLog.error("Region capture error: \(error.localizedDescription)")
            ScreenRecordingPermission.recordCaptureFailure()
            return nil
        }
    }

    // MARK: - Clipboard Image

    /// Save a raw image that came from the clipboard (e.g., Cmd+C on an image
    /// in Preview or a browser) as a regular screenshot record + highlight.
    /// Uses captureType="paste" so provenance is preserved and the main display
    /// id as a placeholder (clipboard images don't have a meaningful originating
    /// display).
    func saveClipboardImage(image: CGImage, context: CaptureContext) async -> CaptureResult? {
        // Pasted images don't have a capture region we could resolve
        // sources from — leave the source list empty so the column
        // stores nothing for these rows.
        return await saveAndOCR(
            image: image,
            captureType: "paste",
            displayId: CGMainDisplayID(),
            context: context,
            sources: []
        )
    }

    // MARK: - Save + OCR

    private func saveAndOCR(
        image: CGImage, captureType: String,
        displayId: CGDirectDisplayID, context: CaptureContext,
        captureRect: String? = nil, scaleFactor: Double? = nil,
        sources: [ScreenshotSource] = []
    ) async -> CaptureResult? {
        let now = Date()
        let dayString = Self.dayFormatter.string(from: now)
        let timeString = Self.timeFormatter.string(from: now)

        let screenshotDir = Self.screenshotsBaseURL.appendingPathComponent(dayString)
        try? FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)

        let filename = "\(timeString).png"
        let filePath = screenshotDir.appendingPathComponent(filename)

        guard let dest = CGImageDestinationCreateWithURL(filePath as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: filePath.path))?[.size] as? Int64 ?? 0

        let ocrText = await TextExtractor.shared.extract(from: image)
        let sourcesJSON = ScreenshotSources.encodeJSON(sources)

        var record = ScreenshotRecord(
            timestamp: now.timeIntervalSince1970,
            dayString: dayString,
            filePath: filePath.path,
            fileSize: fileSize,
            displayId: String(displayId),
            ocrText: ocrText,
            captureType: captureType,
            windowTitle: context.windowTitle,
            bundleId: context.bundleId,
            captureRect: captureRect,
            scaleFactor: scaleFactor,
            imageWidth: image.width,
            imageHeight: image.height,
            sources: sourcesJSON
        )
        db.insertScreenshot(&record)

        CaptureLog.info("Screenshot saved: \(captureType), display: \(displayId), window: \(context.windowTitle ?? "nil"), sources: \(sources.count)")

        return CaptureResult(
            cgImage: image,
            filePath: filePath.path,
            screenshotId: record.id,
            ocrText: ocrText,
            context: context,
            sources: sources
        )
    }

    // MARK: - Paths

    static let screenshotsBaseURL: URL = {
        let url = DatabaseManager.appSupportURL.appendingPathComponent("screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    // MARK: - Formatters

    static func dayString(for date: Date = Date()) -> String {
        dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH-mm-ss"
        return f
    }()
}
