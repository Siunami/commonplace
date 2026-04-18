import Cocoa

final class ScreenshotShortcutHandler {
    static let shared = ScreenshotShortcutHandler()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isCapturing = false

    // MARK: - CGEvent Tap Callback

    private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        // If the tap is disabled by the system (e.g. timeout), re-enable it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let userInfo {
                let handler = Unmanaged<ScreenshotShortcutHandler>.fromOpaque(userInfo).takeUnretainedValue()
                if let tap = handler.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown, let userInfo else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let hasCmd = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)
        // Don't intercept if other modifiers (Ctrl, Alt) are also held
        let hasCtrl = flags.contains(.maskControl)
        let hasAlt = flags.contains(.maskAlternate)

        guard hasCmd && hasShift && !hasCtrl && !hasAlt else {
            return Unmanaged.passRetained(event)
        }

        let handler = Unmanaged<ScreenshotShortcutHandler>.fromOpaque(userInfo).takeUnretainedValue()

        switch keyCode {
        case 20: // key code for '3' — Cmd+Shift+3
            DispatchQueue.main.async { handler.handleFullScreenCapture() }
            return nil // consume the event — blocks system screenshot
        case 21: // key code for '4' — Cmd+Shift+4
            DispatchQueue.main.async { handler.handleRegionCapture() }
            return nil // consume the event — blocks system screenshot
        default:
            return Unmanaged.passRetained(event)
        }
    }

    // MARK: - Start / Stop

    func start() {
        guard eventTap == nil else { return }
        CaptureLog.info("[ScreenshotShortcutHandler] start()")

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            CaptureLog.warning("[ScreenshotShortcutHandler] Failed to create event tap — Accessibility permission required")
            return
        }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source

        CaptureLog.info("[ScreenshotShortcutHandler] Event tap installed — screenshot hotkeys intercepted")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        CaptureLog.info("[ScreenshotShortcutHandler] Event tap removed — screenshot hotkeys restored")
    }

    // MARK: - Capture Handlers

    private func handleFullScreenCapture() {
        guard !isCapturing else { return }
        isCapturing = true

        Task {
            defer { self.isCapturing = false }
            guard let result = await ScreenshotCapture.shared.captureFullScreen() else { return }
            let image = NSImage(cgImage: result.cgImage, size: NSSize(width: result.cgImage.width, height: result.cgImage.height))
            HighlightCapture.shared.captureFromUserScreenshot(
                filePath: result.filePath,
                image: image,
                screenshotId: result.screenshotId,
                context: result.context
            )
        }
    }

    private func handleRegionCapture() {
        guard !isCapturing else { return }
        isCapturing = true

        // Snapshot the frontmost app reference — fast, no AX calls
        let frontApp = NSWorkspace.shared.frontmostApplication

        RegionSelectionWindow.present { [weak self] rect, screen, overlayWindowIDs in
            guard let self else { return }
            guard let rect else {
                RegionSelectionWindow.dismiss()
                self.isCapturing = false
                return
            }

            Task {
                // Capture context NOW — user's app is still underneath, use saved frontApp
                let preContext = CaptureContext.current(frontApp: frontApp)
                let result = await ScreenshotCapture.shared.captureRegion(
                    rect, on: screen,
                    excludingWindowIDs: overlayWindowIDs,
                    context: preContext
                )

                // Dismiss overlay immediately — cursor restores, screen clears
                await MainActor.run { RegionSelectionWindow.dismiss() }
                self.isCapturing = false

                guard let result else { return }
                let image = NSImage(cgImage: result.cgImage, size: NSSize(width: result.cgImage.width, height: result.cgImage.height))
                HighlightCapture.shared.captureFromUserScreenshot(
                    filePath: result.filePath,
                    image: image,
                    screenshotId: result.screenshotId,
                    context: result.context
                )
            }
        }
    }
}
