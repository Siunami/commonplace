import Cocoa

private class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        NSCursor.crosshair.set()
    }

    // Forward the first click to the content view instead of consuming it for activation
    override var acceptsMouseMovedEvents: Bool {
        get { true }
        set { super.acceptsMouseMovedEvents = newValue }
    }
}

final class RegionSelectionWindow {
    private static var windows: [NSWindow] = []
    private static var activationObserver: NSObjectProtocol?

    /// Window IDs for all overlay windows (used to exclude them from screenshot capture)
    static var overlayWindowIDs: [CGWindowID] {
        windows.compactMap { CGWindowID($0.windowNumber) }
    }

    static func present(completion: @escaping (CGRect?, NSScreen?, [CGWindowID]) -> Void) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            completion(nil, nil, [])
            return
        }

        var overlayWindows: [NSWindow] = []

        for screen in screens {
            let w = KeyableWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            w.level = .screenSaver
            w.backgroundColor = .clear
            w.isOpaque = false
            w.hasShadow = false
            w.ignoresMouseEvents = false
            w.acceptsMouseMovedEvents = true

            let overlay = RegionSelectionView(frame: screen.frame, screen: screen) { rect, selectedScreen in
                // Don't dismiss — caller will dismiss after capture completes.
                // Pass overlay window IDs so they can be excluded from the screenshot.
                let windowIDs = self.overlayWindowIDs
                completion(rect, selectedScreen, windowIDs)
            }
            w.contentView = overlay

            overlayWindows.append(w)
        }

        self.windows = overlayWindows

        NSApp.activate(ignoringOtherApps: true)
        for w in overlayWindows {
            w.makeKeyAndOrderFront(nil)
            w.makeFirstResponder(w.contentView)
        }
        NSCursor.crosshair.set()

        // Re-establish overlay state when app regains focus after Cmd-Tab / click-away
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { _ in
            guard !windows.isEmpty else { return }
            for w in windows {
                w.makeKeyAndOrderFront(nil)
                w.makeFirstResponder(w.contentView)
            }
            NSCursor.crosshair.set()
        }
    }

    /// Dismiss all overlay windows. Call after capture completes.
    static func dismiss() {
        if let obs = activationObserver {
            NotificationCenter.default.removeObserver(obs)
            activationObserver = nil
        }
        NSCursor.arrow.set()
        for w in windows {
            w.orderOut(nil)
        }
        windows.removeAll()
    }
}

private class RegionSelectionView: NSView {
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var mouseLocation: NSPoint?
    private var onComplete: ((CGRect?, NSScreen?) -> Void)?
    private let screen: NSScreen
    private var isDragging = false
    private var captureCompleted = false  // prevents redraw after mouseUp

    // Reusable label attributes
    private static let labelFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    private static let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: labelFont,
        .foregroundColor: NSColor.white
    ]
    private static let coordFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let coordAttrs: [NSAttributedString.Key: Any] = [
        .font: coordFont,
        .foregroundColor: NSColor.white.withAlphaComponent(0.9)
    ]

    init(frame: NSRect, screen: NSScreen, onComplete: @escaping (CGRect?, NSScreen?) -> Void) {
        self.screen = screen
        self.onComplete = onComplete
        super.init(frame: frame)

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect, .mouseMoved, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        // Accept the very first click even if the window wasn't key yet
        return true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        guard !captureCompleted else { return }
        NSCursor.crosshair.set()
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    private func drawHintBanner(_ ctx: CGContext) {
        let hint = "Drag to capture region   ·   Esc to cancel" as NSString
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = hint.size(withAttributes: hintAttrs)
        let padH: CGFloat = 14
        let padV: CGFloat = 8
        let w = size.width + padH * 2
        let h = size.height + padV * 2
        let x = bounds.midX - w / 2
        let y = bounds.maxY - h - 24
        let rect = NSRect(x: x, y: y, width: w, height: h)
        let path = NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2)
        NSColor.black.withAlphaComponent(0.72).setFill()
        path.fill()
        hint.draw(at: NSPoint(x: rect.minX + padH, y: rect.minY + padV), withAttributes: hintAttrs)
    }

    override func draw(_ dirtyRect: NSRect) {
        // After capture completes, draw nothing (fully transparent) so the
        // crosshair/coordinates don't flash while the overlay is being dismissed.
        if captureCompleted { return }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        if isDragging, let start = startPoint, let current = currentPoint {
            let sel = selectionRect(from: start, to: current)

            // Dark scrim over the entire view
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.fill(bounds)

            // Clear the selected region (punch a hole)
            ctx.clear(sel)

            // White border around selection
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let borderPath = NSBezierPath(rect: sel)
            borderPath.lineWidth = 1.5
            borderPath.stroke()

            // Dimension label — "W × H" centered below selection
            let w = Int(sel.width)
            let h = Int(sel.height)
            let dimStr = "\(w) × \(h)" as NSString
            let dimSize = dimStr.size(withAttributes: Self.labelAttrs)
            let labelPadH: CGFloat = 8
            let labelPadV: CGFloat = 4
            let labelW = dimSize.width + labelPadH * 2
            let labelH = dimSize.height + labelPadV * 2

            // Position: centered below selection, or above if near bottom
            let labelX = sel.midX - labelW / 2
            var labelY = sel.minY - labelH - 6
            if labelY < bounds.minY + 4 {
                labelY = sel.maxY + 6
            }
            let labelRect = NSRect(x: labelX, y: labelY, width: labelW, height: labelH)

            // Pill background
            let pillPath = NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4)
            NSColor.black.withAlphaComponent(0.7).setFill()
            pillPath.fill()

            // Text
            dimStr.draw(
                at: NSPoint(x: labelRect.minX + labelPadH, y: labelRect.minY + labelPadV),
                withAttributes: Self.labelAttrs
            )
        } else if let mouse = mouseLocation {
            // Pre-drag: crosshair lines + coordinate label

            // Subtle full-screen tint so user knows they're in capture mode
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.1).cgColor)
            ctx.fill(bounds)

            // Hint banner so the exit affordance is obvious
            drawHintBanner(ctx)

            // Crosshair lines
            NSColor.white.withAlphaComponent(0.5).setStroke()
            let hLine = NSBezierPath()
            hLine.move(to: NSPoint(x: bounds.minX, y: mouse.y))
            hLine.line(to: NSPoint(x: bounds.maxX, y: mouse.y))
            hLine.lineWidth = 0.5
            hLine.stroke()

            let vLine = NSBezierPath()
            vLine.move(to: NSPoint(x: mouse.x, y: bounds.minY))
            vLine.line(to: NSPoint(x: mouse.x, y: bounds.maxY))
            vLine.lineWidth = 0.5
            vLine.stroke()

            // Coordinate label — screen coordinates
            let screenX = Int(mouse.x + (window?.frame.origin.x ?? 0))
            let screenY = Int(screen.frame.height - mouse.y)  // flip to top-left origin
            let coordStr = "\(screenX), \(screenY)" as NSString
            let coordSize = coordStr.size(withAttributes: Self.coordAttrs)
            let padH: CGFloat = 6
            let padV: CGFloat = 3
            let cW = coordSize.width + padH * 2
            let cH = coordSize.height + padV * 2

            // Offset label from cursor
            var cx = mouse.x + 14
            var cy = mouse.y - cH - 8
            // Keep on screen
            if cx + cW > bounds.maxX - 4 { cx = mouse.x - cW - 8 }
            if cy < bounds.minY + 4 { cy = mouse.y + 14 }
            let coordRect = NSRect(x: cx, y: cy, width: cW, height: cH)

            let coordPill = NSBezierPath(roundedRect: coordRect, xRadius: 4, yRadius: 4)
            NSColor.black.withAlphaComponent(0.65).setFill()
            coordPill.fill()

            coordStr.draw(
                at: NSPoint(x: coordRect.minX + padH, y: coordRect.minY + padV),
                withAttributes: Self.coordAttrs
            )
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !captureCompleted else { return }
        NSCursor.crosshair.set()
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !captureCompleted else { return }
        NSCursor.crosshair.set()
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !captureCompleted else { return }
        guard let start = startPoint else {
            onComplete?(nil, nil)
            return
        }
        let end = convert(event.locationInWindow, from: nil)
        let rect = selectionRect(from: start, to: end)

        // Restore normal cursor immediately on mouse-up
        NSCursor.arrow.set()

        // Mark capture as done BEFORE triggering redraw — this prevents
        // the crosshair/coordinate UI from flashing while the overlay dismisses.
        captureCompleted = true
        startPoint = nil
        currentPoint = nil
        mouseLocation = nil
        isDragging = false
        needsDisplay = true

        if rect.width < 5 || rect.height < 5 {
            onComplete?(nil, nil)
        } else {
            guard let windowFrame = window?.frame else {
                onComplete?(nil, nil)
                return
            }
            let screenRect = CGRect(
                x: windowFrame.origin.x + rect.origin.x,
                y: windowFrame.origin.y + rect.origin.y,
                width: rect.width,
                height: rect.height
            )
            onComplete?(screenRect, screen)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            captureCompleted = true
            needsDisplay = true
            onComplete?(nil, nil)
        }
    }

    private func selectionRect(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }
}
