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
    }

    private let db = DatabaseManager.shared

    // MARK: - Active Display Detection

    private func displayForActiveWindow() -> CGDirectDisplayID {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return CGMainDisplayID()
        }

        for info in windowList {
            let layer = info[kCGWindowLayer] as? Int ?? 0
            guard layer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"],
                  w > 0, h > 0 else { continue }

            let centerX = x + w / 2
            let centerY = y + h / 2

            for screen in NSScreen.screens {
                let frame = screen.frame
                let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
                let screenTopInCG = primaryHeight - frame.maxY
                let screenBottomInCG = primaryHeight - frame.minY

                if centerX >= frame.minX && centerX <= frame.maxX &&
                   centerY >= screenTopInCG && centerY <= screenBottomInCG {
                    if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                        return displayID
                    }
                }
            }

            break
        }

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
        let targetDisplayID = displayForActiveWindow()

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

            let result = await saveAndOCR(
                image: image, captureType: "full",
                displayId: targetDisplayID, context: context
            )
            ScreenRecordingPermission.recordCaptureSuccess()
            return result
        } catch {
            CaptureLog.error("Screenshot capture error: \(error.localizedDescription)")
            ScreenRecordingPermission.recordCaptureFailure()
            return nil
        }
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

            let result = await saveAndOCR(
                image: cropped, captureType: "region",
                displayId: displayID, context: resolvedContext,
                captureRect: rectJSON, scaleFactor: Double(scaleX)
            )
            ScreenRecordingPermission.recordCaptureSuccess()
            return result
        } catch {
            CaptureLog.error("Region capture error: \(error.localizedDescription)")
            ScreenRecordingPermission.recordCaptureFailure()
            return nil
        }
    }

    // MARK: - Save + OCR

    private func saveAndOCR(
        image: CGImage, captureType: String,
        displayId: CGDirectDisplayID, context: CaptureContext,
        captureRect: String? = nil, scaleFactor: Double? = nil
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
            imageHeight: image.height
        )
        db.insertScreenshot(&record)

        CaptureLog.info("Screenshot saved: \(captureType), display: \(displayId), window: \(context.windowTitle ?? "nil")")

        return CaptureResult(
            cgImage: image,
            filePath: filePath.path,
            screenshotId: record.id,
            ocrText: ocrText,
            context: context
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
