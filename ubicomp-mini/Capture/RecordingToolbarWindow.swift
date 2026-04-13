import SwiftUI
import AppKit
import ScreenCaptureKit
import AVKit

// Panel subclass that accepts first-mouse clicks so buttons work
// even when the panel isn't key (e.g., launched from a hotkey while
// another app is focused).
private class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class RecordingToolbarController {
    static let shared = RecordingToolbarController()

    private var panel: NSPanel?
    private var escapeMonitor: Any?
    private var audioEnabled: Bool = true
    private var isSelectingRegion: Bool = false
    private var isRecording: Bool = false

    // Pre-selected region (set before recording starts)
    private var selectedRegionRect: CGRect?
    private var selectedRegionScreen: NSScreen?

    var isVisible: Bool { panel?.isVisible ?? false }

    // Window level above the region-selection overlay (.screenSaver)
    private static let aboveScreenSaverLevel: NSWindow.Level =
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)

    func show() {
        if panel?.isVisible == true {
            dismiss()
            return
        }

        selectedRegionRect = nil
        selectedRegionScreen = nil
        showToolbar(mode: .fullScreen, regionInfo: nil)
    }

    func dismiss() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
        if isSelectingRegion {
            RegionSelectionWindow.dismiss()
        }
        RecordingRegionOverlay.shared.dismiss()
        panel?.orderOut(nil)
        panel = nil
        isSelectingRegion = false
        isRecording = false
        selectedRegionRect = nil
        selectedRegionScreen = nil
    }

    // MARK: - Internal

    private func showToolbar(mode: ToolbarMode, regionInfo: String?) {
        // Dismiss old panel if any
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil

        let toolbarView = RecordingToolbarView(
            mode: mode,
            regionInfo: regionInfo,
            audioEnabled: audioEnabled,
            onFullScreen: { [weak self] in
                guard let self else { return }
                // If we were mid-selection, tear that down first.
                if self.isSelectingRegion {
                    RegionSelectionWindow.dismiss()
                    self.isSelectingRegion = false
                    self.panel?.level = .floating
                }
                self.selectedRegionRect = nil
                self.selectedRegionScreen = nil
                RecordingRegionOverlay.shared.dismiss()
                self.showToolbar(mode: .fullScreen, regionInfo: nil)
            },
            onSelectRegion: { [weak self] in
                self?.startRegionSelection()
            },
            onAudioToggle: { [weak self] enabled in
                self?.audioEnabled = enabled
            },
            onRecord: { [weak self] in
                self?.startRecording(mode: mode)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: toolbarView)
        let panelWidth: CGFloat = 440
        let panelHeight: CGFloat = 56
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        let p = ClickablePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.contentView = hostingView
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.minY + 60
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }

        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        self.panel = p

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            if self.isSelectingRegion {
                // Let RegionSelectionView handle ESC (cancel selection only)
                return event
            }
            if self.isRecording {
                self.handleStop()
                return nil
            }
            self.dismiss()
            return nil
        }
    }

    private func startRegionSelection() {
        // Flip the toolbar into Region mode immediately so the button
        // visually highlights before the drag even starts.
        selectedRegionRect = nil
        selectedRegionScreen = nil
        RecordingRegionOverlay.shared.dismiss()
        showToolbar(mode: .region, regionInfo: nil)

        // Keep the toolbar visible, but raise it above the region-selection
        // overlay so the user can see they're in video mode and still click it.
        isSelectingRegion = true
        panel?.level = Self.aboveScreenSaverLevel

        RegionSelectionWindow.present { [weak self] rect, screen, _ in
            RegionSelectionWindow.dismiss()
            guard let self else { return }
            self.isSelectingRegion = false
            self.panel?.level = .floating

            guard let rect, let screen else {
                // Cancelled — stay in Region mode, no dimensions.
                self.showToolbar(mode: .region, regionInfo: nil)
                return
            }

            // Store the selected region
            self.selectedRegionRect = rect
            self.selectedRegionScreen = screen

            // Show the dim overlay around the selected area
            RecordingRegionOverlay.shared.show(rect: rect)

            // Rebuild toolbar with region info
            let w = Int(rect.width)
            let h = Int(rect.height)
            self.showToolbar(mode: .region, regionInfo: "\(w) x \(h)")
        }
    }

    private func startRecording(mode: ToolbarMode) {
        let audio = audioEnabled
        let regionRect = selectedRegionRect
        let regionScreen = selectedRegionScreen
        let excluded = currentExcludedWindowIDs()

        Task {
            do {
                switch mode {
                case .fullScreen:
                    let displayID = displayForActiveWindow()
                    try await ScreenRecordingCapture.shared.startFullScreen(
                        displayID: displayID, audio: audio, excludedWindowIDs: excluded)

                case .region:
                    guard let rect = regionRect, let screen = regionScreen else {
                        CaptureLog.error("[RecordingToolbar] No region selected")
                        return
                    }
                    try await ScreenRecordingCapture.shared.startRegion(
                        rect: rect, on: screen, audio: audio, excludedWindowIDs: excluded)
                    await MainActor.run {
                        RecordingRegionOverlay.shared.show(rect: rect)
                    }
                }

                await MainActor.run {
                    self.swapToRecordingControls()
                }
            } catch {
                CaptureLog.error("[RecordingToolbar] Failed to start recording: \(error.localizedDescription)")
                await MainActor.run {
                    self.presentRecordingError(error)
                }
            }
        }
    }

    // MARK: - Error alert

    private func presentRecordingError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning

        if Self.isScreenRecordingPermissionError(error) {
            alert.messageText = "Screen Recording Permission Needed"
            alert.informativeText = """
            macOS is blocking Capture from recording the screen. This usually means permission was denied or has expired (macOS 15 requires periodic re-approval).

            Open System Settings → Privacy & Security → Screen & System Audio Recording, enable Capture, then try again.
            """
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                Self.openScreenRecordingSettings()
            }
            return
        }

        if Self.isMicrophonePermissionError(error) {
            alert.messageText = "Microphone Permission Needed"
            alert.informativeText = """
            Capture needs permission to use the microphone for audio recording. You can still record without audio, or grant access in System Settings → Privacy & Security → Microphone.
            """
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                Self.openMicrophoneSettings()
            }
            return
        }

        alert.messageText = "Recording Failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func isScreenRecordingPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        // Our own preflight error
        if ns.domain == "ScreenRecordingCapture", ns.code == 2 { return true }
        // SCStream declined error — code -3801 is userDeclined
        if ns.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" { return true }
        let message = error.localizedDescription.lowercased()
        return message.contains("declined")
            || message.contains("tcc")
            || (message.contains("screen") && message.contains("permission"))
    }

    static func isMicrophonePermissionError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("microphone") && message.contains("permission")
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Window exclusion

    /// Window IDs that should never be captured by ScreenCaptureKit — the
    /// toolbar panel itself and any region dim overlays.
    private func currentExcludedWindowIDs() -> [CGWindowID] {
        var ids: [CGWindowID] = []
        if let number = panel?.windowNumber, number > 0 {
            ids.append(CGWindowID(number))
        }
        ids.append(contentsOf: RecordingRegionOverlay.shared.windowNumbers)
        return ids
    }

    // MARK: - Swap to recording controls (in-place)

    private func swapToRecordingControls() {
        guard let panel else { return }
        isRecording = true

        let indicatorView = RecordingActiveToolbarView(
            onStop: { [weak self] in
                self?.handleStop()
            }
        )

        let newWidth: CGFloat = 220
        let newHeight: CGFloat = 48

        let hostingView = NSHostingView(rootView: indicatorView)
        hostingView.frame = NSRect(x: 0, y: 0, width: newWidth, height: newHeight)
        panel.contentView = hostingView

        // Resize panel around its current position (keep bottom-center)
        let oldFrame = panel.frame
        let newX = oldFrame.midX - newWidth / 2
        let newY = oldFrame.minY
        panel.setFrame(NSRect(x: newX, y: newY, width: newWidth, height: newHeight), display: true, animate: true)
    }

    /// Stop an in-progress recording and dismiss all toolbar UI.
    /// Safe to call from anywhere (hotkey, app termination, Stop button).
    func stopRecording() {
        handleStop()
    }

    private func handleStop() {
        guard isRecording else { return }
        isRecording = false

        Task {
            let result = await ScreenRecordingCapture.shared.stopRecording()
            await MainActor.run {
                self.dismiss()
            }
            if let result {
                HighlightCapture.shared.captureFromRecording(result: result)
            }
        }
    }

    enum ToolbarMode {
        case fullScreen
        case region
    }

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
}

// MARK: - Region Dim Overlay (Apple-style: dim outside, transparent inside)

final class RecordingRegionOverlay {
    static let shared = RecordingRegionOverlay()

    private var windows: [NSWindow] = []

    /// Window IDs for all dim-overlay windows, for SCContentFilter exclusion.
    var windowNumbers: [CGWindowID] {
        windows.compactMap { $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil }
    }

    func show(rect: CGRect) {
        dismiss()

        for screen in NSScreen.screens {
            let w = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            w.level = .screenSaver - 1
            w.backgroundColor = .clear
            w.isOpaque = false
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let overlayView = RegionDimView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                clearRect: NSRect(
                    x: rect.origin.x - screen.frame.origin.x,
                    y: rect.origin.y - screen.frame.origin.y,
                    width: rect.width,
                    height: rect.height
                )
            )
            w.contentView = overlayView
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    func dismiss() {
        for w in windows {
            w.orderOut(nil)
        }
        windows.removeAll()
    }
}

// Also expose old name for compatibility
typealias RecordingRegionBorder = RecordingRegionOverlay

private class RegionDimView: NSView {
    let clearRect: NSRect

    init(frame: NSRect, clearRect: NSRect) {
        self.clearRect = clearRect
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Dim the entire screen
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
        ctx.fill(bounds)

        // Punch a transparent hole for the recorded region
        ctx.clear(clearRect)

        // Thin white border around the clear area
        NSColor.white.withAlphaComponent(0.5).setStroke()
        let borderPath = NSBezierPath(rect: clearRect)
        borderPath.lineWidth = 1
        borderPath.stroke()
    }
}

// MARK: - Toolbar SwiftUI View

private struct RecordingToolbarView: View {
    let mode: RecordingToolbarController.ToolbarMode
    let regionInfo: String?
    let audioEnabled: Bool
    let onFullScreen: () -> Void
    let onSelectRegion: () -> Void
    let onAudioToggle: (Bool) -> Void
    let onRecord: () -> Void
    let onDismiss: () -> Void

    @State private var localAudio: Bool

    init(mode: RecordingToolbarController.ToolbarMode, regionInfo: String?,
         audioEnabled: Bool,
         onFullScreen: @escaping () -> Void,
         onSelectRegion: @escaping () -> Void,
         onAudioToggle: @escaping (Bool) -> Void,
         onRecord: @escaping () -> Void,
         onDismiss: @escaping () -> Void) {
        self.mode = mode
        self.regionInfo = regionInfo
        self.audioEnabled = audioEnabled
        self.onFullScreen = onFullScreen
        self.onSelectRegion = onSelectRegion
        self.onAudioToggle = onAudioToggle
        self.onRecord = onRecord
        self.onDismiss = onDismiss
        self._localAudio = State(initialValue: audioEnabled)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Full Screen button
            Button(action: onFullScreen) {
                VStack(spacing: 2) {
                    Image(systemName: "rectangle.inset.filled")
                        .font(.system(size: 18))
                    Text("Full Screen")
                        .font(.system(size: 9))
                }
                .frame(width: 70, height: 38)
                .background(mode == .fullScreen ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // Region button
            Button(action: onSelectRegion) {
                VStack(spacing: 2) {
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 18))
                    if let info = regionInfo {
                        Text(info)
                            .font(.system(size: 9))
                    } else {
                        Text("Region")
                            .font(.system(size: 9))
                    }
                }
                .frame(width: 70, height: 38)
                .background(mode == .region ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 28)

            // Audio toggle
            Button(action: {
                localAudio.toggle()
                onAudioToggle(localAudio)
            }) {
                Image(systemName: localAudio ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(localAudio ? .primary : .secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(localAudio ? "System audio: on" : "System audio: off")

            Divider()
                .frame(height: 28)

            // Record button
            Button(action: onRecord) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text("Record")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Close button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

// MARK: - Recording Active Toolbar (shown in place of setup toolbar while recording)

private struct RecordingActiveToolbarView: View {
    let onStop: () -> Void

    @State private var elapsedSeconds: Double = 0
    @State private var dotOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 12, height: 12)
                .opacity(dotOpacity)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        dotOpacity = 0.3
                    }
                }

            Text(formattedTime)
                .font(.system(.body, design: .monospaced).bold())
                .foregroundStyle(.primary)

            Divider()
                .frame(height: 20)

            Button(action: onStop) {
                HStack(spacing: 5) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                    Text("Stop")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .onReceive(NotificationCenter.default.publisher(for: .recordingElapsedTick)) { _ in
            elapsedSeconds = ScreenRecordingCapture.shared.elapsedSeconds
        }
        .onAppear {
            elapsedSeconds = ScreenRecordingCapture.shared.elapsedSeconds
        }
    }

    private var formattedTime: String {
        let minutes = Int(elapsedSeconds) / 60
        let seconds = Int(elapsedSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Visual Effect View

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
