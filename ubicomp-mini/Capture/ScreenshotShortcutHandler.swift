import Cocoa
import Carbon

@_silgen_name("CGSSetSymbolicHotKeyEnabled")
@discardableResult
func CGSSetSymbolicHotKeyEnabled(_ key: Int32, _ enabled: Bool) -> CGError

final class ScreenshotShortcutHandler {
    static let shared = ScreenshotShortcutHandler()

    private var fullScreenHotKeyRef: EventHotKeyRef?
    private var regionHotKeyRef: EventHotKeyRef?
    private var toolbarHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var terminationObserver: NSObjectProtocol?
    private var isCapturing = false

    private static let fullScreenFileKey: Int32 = 28   // Cmd+Shift+3
    private static let regionFileKey: Int32 = 30       // Cmd+Shift+4
    private static let toolbarFileKey: Int32 = 184     // Cmd+Shift+5
    private static let hotKeySignature: FourCharCode = 0x43415054  // "CAPT"

    // MARK: - Carbon Hotkey Callback

    private static let carbonHotKeyHandler: EventHandlerUPP = { _, event, userData in
        guard let event = event, let userData = userData else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return OSStatus(eventNotHandledErr) }

        let handler = Unmanaged<ScreenshotShortcutHandler>.fromOpaque(userData).takeUnretainedValue()

        switch hotKeyID.id {
        case 1:
            DispatchQueue.main.async { handler.handleFullScreenCapture() }
        case 2:
            DispatchQueue.main.async { handler.handleRegionCapture() }
        case 3:
            DispatchQueue.main.async { handler.handleToolbarToggle() }
        default:
            return OSStatus(eventNotHandledErr)
        }

        return noErr
    }

    // MARK: - Crash Recovery

    /// Re-enable system screenshot hotkeys. Safe to call anytime (idempotent).
    /// Static so it can be called from signal handlers and early launch cleanup.
    static func restoreSystemHotkeys() {
        CGSSetSymbolicHotKeyEnabled(fullScreenFileKey, true)
        CGSSetSymbolicHotKeyEnabled(regionFileKey, true)
        CGSSetSymbolicHotKeyEnabled(toolbarFileKey, true)
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.apple.symbolichotkeys.changed"),
            object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    private func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { sig in
            ScreenshotShortcutHandler.restoreSystemHotkeys()
            // Re-raise the signal with default handler so the OS crash reporter works
            signal(sig, SIG_DFL)
            raise(sig)
        }
        signal(SIGTERM, handler)
        signal(SIGINT, handler)
        signal(SIGABRT, handler)
        signal(SIGSEGV, handler)  // segfault — the ldr crash
        signal(SIGBUS, handler)   // bus error
        signal(SIGILL, handler)   // illegal instruction
        signal(SIGFPE, handler)   // floating point exception

        // atexit runs on normal exit() and most crash paths
        atexit {
            ScreenshotShortcutHandler.restoreSystemHotkeys()
        }

        // Catch uncaught ObjC/Swift exceptions
        NSSetUncaughtExceptionHandler { _ in
            ScreenshotShortcutHandler.restoreSystemHotkeys()
        }

        // Observe app termination as another safety net
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: nil
        ) { _ in
            ScreenshotShortcutHandler.restoreSystemHotkeys()
        }
    }

    // MARK: - Hotkey Watchdog

    /// Spawns a detached background process that monitors this app's PID.
    /// When the app exits for ANY reason (including SIGKILL from Xcode),
    /// the watchdog restores system screenshot hotkeys via `swift -e`.
    private func spawnHotkeyWatchdog() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 1; done
        swift -e '
        @_silgen_name("CGSSetSymbolicHotKeyEnabled")
        func CGSSetSymbolicHotKeyEnabled(_ key: Int32, _ enabled: Bool)
        CGSSetSymbolicHotKeyEnabled(28, true)
        CGSSetSymbolicHotKeyEnabled(30, true)
        CGSSetSymbolicHotKeyEnabled(184, true)
        import Foundation
        DistributedNotificationCenter.default().postNotificationName(
            .init("com.apple.symbolichotkeys.changed"),
            object: nil, userInfo: nil, deliverImmediately: true)
        '
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            CaptureLog.info("[ScreenshotShortcutHandler] Hotkey watchdog spawned (monitoring PID \(pid))")
        } catch {
            CaptureLog.warning("[ScreenshotShortcutHandler] Failed to spawn watchdog: \(error.localizedDescription)")
        }
    }

    // MARK: - Start / Stop

    func start() {
        guard eventHandlerRef == nil else { return }
        CaptureLog.info("[ScreenshotShortcutHandler] start()")

        // Crash recovery: restore system hotkeys first in case a prior run died uncleanly
        Self.restoreSystemHotkeys()

        installSignalHandlers()
        spawnHotkeyWatchdog()

        CGSSetSymbolicHotKeyEnabled(Self.fullScreenFileKey, false)
        CGSSetSymbolicHotKeyEnabled(Self.regionFileKey, false)
        CGSSetSymbolicHotKeyEnabled(Self.toolbarFileKey, false)

        DistributedNotificationCenter.default().postNotificationName(
            .init("com.apple.symbolichotkeys.changed"),
            object: nil, userInfo: nil, deliverImmediately: true
        )

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.carbonHotKeyHandler,
            1, &eventType, selfPtr, &eventHandlerRef
        )

        let modifiers = UInt32(cmdKey | shiftKey)

        var fullScreenID = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
        RegisterEventHotKey(UInt32(20), modifiers, fullScreenID,
                           GetApplicationEventTarget(), 0, &fullScreenHotKeyRef)

        var regionID = EventHotKeyID(signature: Self.hotKeySignature, id: 2)
        RegisterEventHotKey(UInt32(21), modifiers, regionID,
                           GetApplicationEventTarget(), 0, &regionHotKeyRef)

        var toolbarID = EventHotKeyID(signature: Self.hotKeySignature, id: 3)
        RegisterEventHotKey(UInt32(23), modifiers, toolbarID,
                           GetApplicationEventTarget(), 0, &toolbarHotKeyRef)

        CaptureLog.info("[ScreenshotShortcutHandler] System screenshot hotkeys overridden")
    }

    func stop() {
        if let ref = fullScreenHotKeyRef {
            UnregisterEventHotKey(ref)
            fullScreenHotKeyRef = nil
        }
        if let ref = regionHotKeyRef {
            UnregisterEventHotKey(ref)
            regionHotKeyRef = nil
        }
        if let ref = toolbarHotKeyRef {
            UnregisterEventHotKey(ref)
            toolbarHotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }

        if let obs = terminationObserver {
            NotificationCenter.default.removeObserver(obs)
            terminationObserver = nil
        }

        CGSSetSymbolicHotKeyEnabled(Self.fullScreenFileKey, true)
        CGSSetSymbolicHotKeyEnabled(Self.regionFileKey, true)
        CGSSetSymbolicHotKeyEnabled(Self.toolbarFileKey, true)

        DistributedNotificationCenter.default().postNotificationName(
            .init("com.apple.symbolichotkeys.changed"),
            object: nil, userInfo: nil, deliverImmediately: true
        )

        CaptureLog.info("[ScreenshotShortcutHandler] System screenshot hotkeys restored")
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

    // MARK: - Recording Toolbar Toggle

    private func handleToolbarToggle() {
        // If actively recording → stop recording via the toolbar controller,
        // which owns both the recording state flag and the stop UI.
        if ScreenRecordingCapture.shared.state == .recording {
            RecordingToolbarController.shared.stopRecording()
            return
        }

        // If toolbar visible → dismiss it
        if RecordingToolbarController.shared.isVisible {
            RecordingToolbarController.shared.dismiss()
            return
        }

        // Otherwise → show toolbar
        RecordingToolbarController.shared.show()
    }
}
