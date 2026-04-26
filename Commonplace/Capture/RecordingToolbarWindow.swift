import Cocoa
import Combine
import AVFoundation
import ScreenCaptureKit

// MARK: - Capture Mode

enum CaptureToolbarMode: Int {
    case captureEntireScreen = 0
    case captureSelectedWindow = 1
    case captureSelectedPortion = 2
    case recordEntireScreen = 3
    case recordSelectedPortion = 4

    var isRecording: Bool { self == .recordEntireScreen || self == .recordSelectedPortion }
    var isRegion: Bool { self == .captureSelectedPortion || self == .recordSelectedPortion }
    var isWindow: Bool { self == .captureSelectedWindow }
    var actionLabel: String { isRecording ? "Record" : "Capture" }

    var sfSymbol: String {
        switch self {
        case .captureEntireScreen:  return "rectangle.inset.filled"
        case .captureSelectedWindow: return "macwindow"
        case .captureSelectedPortion: return "rectangle.dashed"
        case .recordEntireScreen:   return "circle.inset.filled"
        case .recordSelectedPortion: return "circle.dashed"
        }
    }

    var tooltip: String {
        switch self {
        case .captureEntireScreen:  return "Capture Entire Screen"
        case .captureSelectedWindow: return "Capture Selected Window"
        case .captureSelectedPortion: return "Capture Selected Portion"
        case .recordEntireScreen:   return "Record Entire Screen"
        case .recordSelectedPortion: return "Record Selected Portion"
        }
    }
}

// MARK: - Toolbar Preferences

final class CaptureToolbarPrefs {
    static let shared = CaptureToolbarPrefs()

    private let defaults = UserDefaults.standard
    private let prefix = "captureToolbar_"

    var selectedMode: CaptureToolbarMode {
        get { CaptureToolbarMode(rawValue: defaults.integer(forKey: prefix + "mode")) ?? .captureEntireScreen }
        set { defaults.set(newValue.rawValue, forKey: prefix + "mode") }
    }
    var timer: Int {
        get { defaults.integer(forKey: prefix + "timer") }
        set { defaults.set(newValue, forKey: prefix + "timer") }
    }
    var showMousePointer: Bool {
        get { defaults.object(forKey: prefix + "showPointer") as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefix + "showPointer") }
    }
    var useMicrophone: Bool {
        get { defaults.bool(forKey: prefix + "useMic") }
        set { defaults.set(newValue, forKey: prefix + "useMic") }
    }
    var rememberLastSelection: Bool {
        get { defaults.object(forKey: prefix + "rememberSelection") as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefix + "rememberSelection") }
    }
    var showFloatingThumbnail: Bool {
        get { defaults.object(forKey: prefix + "showThumbnail") as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefix + "showThumbnail") }
    }
    var lastRegionRect: NSRect? {
        get {
            guard let data = defaults.data(forKey: prefix + "lastRect"),
                  let r = try? JSONDecoder().decode(CodableRect.self, from: data) else { return nil }
            return r.nsRect
        }
        set {
            if let r = newValue, let data = try? JSONEncoder().encode(CodableRect(nsRect: r)) {
                defaults.set(data, forKey: prefix + "lastRect")
            } else {
                defaults.removeObject(forKey: prefix + "lastRect")
            }
        }
    }
    private struct CodableRect: Codable {
        let x, y, w, h: CGFloat
        init(nsRect r: NSRect) { x = r.origin.x; y = r.origin.y; w = r.width; h = r.height }
        var nsRect: NSRect { NSRect(x: x, y: y, width: w, height: h) }
    }
}

// MARK: - Toolbar Content View (AppKit)

final class CaptureToolbarContentView: NSView {
    private let prefs = CaptureToolbarPrefs.shared
    private var selectedMode: CaptureToolbarMode
    private var modeButtons: [CaptureToolbarMode: NSButton] = [:]
    private var actionButton: NSButton!
    private let onAction: (CaptureToolbarMode) -> Void
    private let onDismiss: () -> Void

    init(onAction: @escaping (CaptureToolbarMode) -> Void, onDismiss: @escaping () -> Void) {
        self.selectedMode = prefs.selectedMode
        self.onAction = onAction
        self.onDismiss = onDismiss
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        // Background effect
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effect)

        // Main stack
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        // Close button
        let closeBtn = makeIconButton(symbol: "xmark", size: 12, weight: .medium)
        closeBtn.toolTip = "Close"
        closeBtn.target = self
        closeBtn.action = #selector(dismissClicked)
        closeBtn.alphaValue = 0.5

        let closeContainer = wrapWithPadding(closeBtn, leading: 12, trailing: 8)
        stack.addArrangedSubview(closeContainer)

        // Screenshot mode buttons (group of 3)
        let screenshotGroup = makeButtonGroup([
            .captureEntireScreen, .captureSelectedWindow, .captureSelectedPortion
        ])
        stack.addArrangedSubview(screenshotGroup)

        // Divider
        stack.addArrangedSubview(makeDivider())

        // Recording mode buttons (group of 2)
        let recordGroup = makeButtonGroup([.recordEntireScreen, .recordSelectedPortion])
        stack.addArrangedSubview(recordGroup)

        // Divider
        stack.addArrangedSubview(makeDivider())

        // Options button
        let optionsBtn = NSButton(title: "Options", target: self, action: #selector(optionsClicked(_:)))
        optionsBtn.bezelStyle = .inline
        optionsBtn.isBordered = false
        optionsBtn.font = NSFont.systemFont(ofSize: 13)
        optionsBtn.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        optionsBtn.translatesAutoresizingMaskIntoConstraints = false
        optionsBtn.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let optionsContainer = wrapWithPadding(optionsBtn, leading: 2, trailing: 0)
        stack.addArrangedSubview(optionsContainer)

        // Action button
        actionButton = NSButton(title: selectedMode.actionLabel, target: self, action: #selector(actionClicked))
        actionButton.bezelStyle = .inline
        actionButton.isBordered = false
        actionButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        actionButton.contentTintColor = .white
        actionButton.wantsLayer = true
        actionButton.layer?.cornerRadius = 6
        updateActionButtonAppearance()
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let actionContainer = wrapWithPadding(actionButton, leading: 8, trailing: 12)
        stack.addArrangedSubview(actionContainer)

        // Constraints
        NSLayoutConstraint.activate([
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor),
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),

            heightAnchor.constraint(equalToConstant: 52),
        ])

        updateSelection()
    }

    // MARK: - Button Factories

    private func makeButtonGroup(_ modes: [CaptureToolbarMode]) -> NSView {
        let group = NSStackView()
        group.orientation = .horizontal
        group.spacing = 1
        group.translatesAutoresizingMaskIntoConstraints = false

        for mode in modes {
            let btn = makeIconButton(symbol: mode.sfSymbol, size: 18, weight: .regular)
            btn.toolTip = mode.tooltip
            btn.tag = mode.rawValue
            btn.target = self
            btn.action = #selector(modeClicked(_:))
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: 44).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 36).isActive = true
            modeButtons[mode] = btn
            group.addArrangedSubview(btn)
        }

        return group
    }

    private func makeIconButton(symbol: String, size: CGFloat, weight: NSFont.Weight) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        let btn = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.imagePosition = .imageOnly
        btn.contentTintColor = .white
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        return btn
    }

    private func makeDivider() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: 21).isActive = true

        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)

        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 28),
            line.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    private func wrapWithPadding(_ view: NSView, leading: CGFloat, trailing: CGFloat) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leading),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -trailing),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    // MARK: - Selection State

    private func updateSelection() {
        for (mode, btn) in modeButtons {
            let isSelected = mode == selectedMode
            btn.layer?.backgroundColor = isSelected
                ? NSColor.white.withAlphaComponent(0.2).cgColor
                : NSColor.clear.cgColor
            btn.contentTintColor = isSelected
                ? NSColor.white
                : NSColor.white.withAlphaComponent(0.5)
        }
        actionButton.title = selectedMode.actionLabel
        updateActionButtonAppearance()
        prefs.selectedMode = selectedMode
    }

    private func updateActionButtonAppearance() {
        if selectedMode.isRecording {
            actionButton.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.8).cgColor
        } else {
            actionButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        }
    }

    // MARK: - Actions

    @objc private func modeClicked(_ sender: NSButton) {
        guard let mode = CaptureToolbarMode(rawValue: sender.tag) else { return }
        selectedMode = mode
        updateSelection()
    }

    @objc private func actionClicked() {
        onAction(selectedMode)
    }

    @objc private func dismissClicked() {
        onDismiss()
    }

    @objc private func optionsClicked(_ sender: NSButton) {
        let menu = buildOptionsMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    // MARK: - Options Menu

    private func buildOptionsMenu() -> NSMenu {
        let menu = NSMenu()

        // Timer section
        let timerHeader = NSMenuItem(title: "Timer", action: nil, keyEquivalent: "")
        timerHeader.isEnabled = false
        menu.addItem(timerHeader)
        for (label, value) in [("None", 0), ("5 Seconds", 5), ("10 Seconds", 10)] {
            let item = NSMenuItem(title: label, action: #selector(setTimer(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            item.state = prefs.timer == value ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Microphone section (only for recording modes)
        if selectedMode.isRecording {
            let micHeader = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
            micHeader.isEnabled = false
            menu.addItem(micHeader)

            let noneItem = NSMenuItem(title: "None", action: #selector(setMicNone), keyEquivalent: "")
            noneItem.target = self
            noneItem.state = prefs.useMicrophone ? .off : .on
            menu.addItem(noneItem)

            let micName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Built-in Microphone"
            let micItem = NSMenuItem(title: micName, action: #selector(setMicOn), keyEquivalent: "")
            micItem.target = self
            micItem.state = prefs.useMicrophone ? .on : .off
            menu.addItem(micItem)

            menu.addItem(.separator())
        }

        // Toggles
        let pointerItem = NSMenuItem(title: "Show Mouse Pointer", action: #selector(togglePointer), keyEquivalent: "")
        pointerItem.target = self
        pointerItem.state = prefs.showMousePointer ? .on : .off
        menu.addItem(pointerItem)

        let rememberItem = NSMenuItem(title: "Remember Last Selection", action: #selector(toggleRemember), keyEquivalent: "")
        rememberItem.target = self
        rememberItem.state = prefs.rememberLastSelection ? .on : .off
        menu.addItem(rememberItem)

        let thumbnailItem = NSMenuItem(title: "Show Floating Thumbnail", action: #selector(toggleThumbnail), keyEquivalent: "")
        thumbnailItem.target = self
        thumbnailItem.state = prefs.showFloatingThumbnail ? .on : .off
        menu.addItem(thumbnailItem)

        return menu
    }

    @objc private func setTimer(_ sender: NSMenuItem) { prefs.timer = sender.tag }
    @objc private func setMicNone() { prefs.useMicrophone = false }
    @objc private func setMicOn() { prefs.useMicrophone = true }
    @objc private func togglePointer() { prefs.showMousePointer.toggle() }
    @objc private func toggleRemember() { prefs.rememberLastSelection.toggle() }
    @objc private func toggleThumbnail() { prefs.showFloatingThumbnail.toggle() }

    // MARK: - Key handling

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onDismiss()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Recording Toolbar Controller

final class RecordingToolbarController {
    static let shared = RecordingToolbarController()

    private var panel: NSPanel?
    private var stopStatusItem: NSStatusItem?
    private var countdownWindow: NSWindow?
    private let prefs = CaptureToolbarPrefs.shared

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        if isVisible { dismiss() } else { show() }
    }

    func show() {
        dismiss()

        let contentView = CaptureToolbarContentView(
            onAction: { [weak self] mode in
                self?.handleAction(mode: mode)
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )

        let fittingSize = contentView.fittingSize
        let panelFrame = NSRect(origin: .zero, size: NSSize(width: max(fittingSize.width, 480), height: 52))

        let p = NSPanel(
            contentRect: panelFrame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isOpaque = false
        p.appearance = NSAppearance(named: .darkAqua)
        p.contentView = contentView

        // Position: bottom-center of the screen with the cursor
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first
        if let screen {
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.midX - panelFrame.width / 2
            let y = visibleFrame.origin.y + 80
            p.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            p.center()
        }

        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(contentView)
        self.panel = p
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }

    // MARK: - Action Handling

    private func handleAction(mode: CaptureToolbarMode) {
        prefs.selectedMode = mode

        let timerDelay = prefs.timer
        if timerDelay > 0 {
            dismiss()
            showCountdown(seconds: timerDelay) { [weak self] in
                self?.executeAction(mode: mode)
            }
        } else {
            dismiss()
            executeAction(mode: mode)
        }
    }

    private func executeAction(mode: CaptureToolbarMode) {
        switch mode {
        case .captureEntireScreen:
            Task {
                guard let result = await ScreenshotCapture.shared.captureFullScreen() else { return }
                let image = NSImage(cgImage: result.cgImage, size: NSSize(width: result.cgImage.width, height: result.cgImage.height))
                HighlightCapture.shared.captureFromUserScreenshot(
                    filePath: result.filePath, image: image,
                    screenshotId: result.screenshotId, context: result.context,
                    sources: result.sources
                )
            }

        case .captureSelectedWindow:
            // Window capture — falls back to full screen for now (TODO: window picker with hover highlight)
            Task {
                guard let result = await ScreenshotCapture.shared.captureFullScreen() else { return }
                let image = NSImage(cgImage: result.cgImage, size: NSSize(width: result.cgImage.width, height: result.cgImage.height))
                HighlightCapture.shared.captureFromUserScreenshot(
                    filePath: result.filePath, image: image,
                    screenshotId: result.screenshotId, context: result.context,
                    sources: result.sources
                )
            }

        case .captureSelectedPortion:
            let frontApp = NSWorkspace.shared.frontmostApplication
            RegionSelectionWindow.present { rect, screen, overlayWindowIDs in
                guard let rect else { RegionSelectionWindow.dismiss(); return }
                Task {
                    let preContext = CaptureContext.current(frontApp: frontApp)
                    let result = await ScreenshotCapture.shared.captureRegion(
                        rect, on: screen, excludingWindowIDs: overlayWindowIDs, context: preContext
                    )
                    await MainActor.run { RegionSelectionWindow.dismiss() }
                    guard let result else { return }
                    let image = NSImage(cgImage: result.cgImage, size: NSSize(width: result.cgImage.width, height: result.cgImage.height))
                    HighlightCapture.shared.captureFromUserScreenshot(
                        filePath: result.filePath, image: image,
                        screenshotId: result.screenshotId, context: result.context,
                        sources: result.sources
                    )
                }
            }

        case .recordEntireScreen:
            startRecording(fullScreen: true)

        case .recordSelectedPortion:
            RegionSelectionWindow.present { [weak self] rect, screen, _ in
                guard let rect, let screen else { RegionSelectionWindow.dismiss(); return }
                RegionSelectionWindow.dismiss()
                if self?.prefs.rememberLastSelection == true {
                    self?.prefs.lastRegionRect = rect
                }
                self?.startRecording(fullScreen: false, regionRect: rect, regionScreen: screen)
            }
        }
    }

    // MARK: - Recording

    private func startRecording(fullScreen: Bool, regionRect: NSRect? = nil, regionScreen: NSScreen? = nil) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = regionScreen
            ?? NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first
        let displayID: CGDirectDisplayID = screen?.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID ?? CGMainDisplayID()

        Task {
            do {
                if fullScreen {
                    try await ScreenRecordingCapture.shared.startFullScreen(
                        displayID: displayID, audio: prefs.useMicrophone
                    )
                } else if let rect = regionRect, let screen = regionScreen {
                    try await ScreenRecordingCapture.shared.startRegion(
                        rect: rect, on: screen, audio: prefs.useMicrophone
                    )
                }
                await MainActor.run { self.showMenuBarStopButton() }
            } catch {
                CaptureLog.error("Failed to start recording: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Menu Bar Stop Button

    private func showMenuBarStopButton() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
            button.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop Recording")?
                .withSymbolConfiguration(config)
            button.action = #selector(stopRecordingFromMenuBar)
            button.target = self
        }
        stopStatusItem = item
    }

    @objc private func stopRecordingFromMenuBar() {
        Task {
            let result = await ScreenRecordingCapture.shared.stopRecording()
            await MainActor.run {
                self.removeMenuBarStopButton()
                if let result {
                    HighlightCapture.shared.captureFromRecording(result: result)
                }
            }
        }
    }

    private func removeMenuBarStopButton() {
        if let item = stopStatusItem {
            NSStatusBar.system.removeStatusItem(item)
            stopStatusItem = nil
        }
    }

    // MARK: - Timer Countdown

    private func showCountdown(seconds: Int, completion: @escaping () -> Void) {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .screenSaver
        w.center()

        var remaining = seconds
        let label = NSTextField(labelWithString: "\(remaining)")
        label.font = NSFont.systemFont(ofSize: 72, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.frame = w.contentView!.bounds
        label.autoresizingMask = [.width, .height]

        let bg = NSVisualEffectView(frame: w.contentView!.bounds)
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 20
        bg.autoresizingMask = [.width, .height]

        w.contentView?.addSubview(bg)
        w.contentView?.addSubview(label)
        w.makeKeyAndOrderFront(nil)
        countdownWindow = w

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                self?.countdownWindow?.close()
                self?.countdownWindow = nil
                completion()
            } else {
                label.stringValue = "\(remaining)"
            }
        }
    }
}
