import SwiftUI
import AppKit
import Carbon.HIToolbox

final class BrowseWindowController: NSObject, NSWindowDelegate, ManagedWindowController {
    static let shared = BrowseWindowController()

    private var window: NSWindow?
    private var toggleHotKey: CarbonHotKey?

    /// Posted when the browse window becomes visible.
    static let windowDidShowNotification = Notification.Name("BrowseWindowDidShow")

    /// Posted to open a specific highlight's detail view. UserInfo contains ["highlightId": String].
    static let showHighlightDetailNotification = Notification.Name("BrowseWindowShowHighlightDetail")

    /// Posted to open the Browse window with the Settings panel showing.
    static let showSettingsNotification = Notification.Name("BrowseWindowShowSettings")

    func registerHotkey() {
        // Carbon RegisterEventHotKey — fires system-wide without Accessibility
        // permission, unlike NSEvent global monitors.
        toggleHotKey = CarbonHotKey(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(cmdKey | controlKey)
        ) { [weak self] in
            DispatchQueue.main.async { self?.toggle() }
        }
        if toggleHotKey == nil {
            CaptureLog.warning("[BrowseWindowController] Failed to register Ctrl+Cmd+A — combo may be in use by another app")
        }
    }

    func toggle() {
        if let window = window, window.isVisible, window.isKeyWindow {
            dismiss()
        } else {
            show()
        }
    }

    @discardableResult
    func show() -> Bool {
        if !AppEnvironment.isRunningUITests,
           PermissionsWindowController.shared.needsSetup {
            PermissionsWindowController.shared.show()
            return false
        }

        // Create the window once. After that, just show/hide it.
        // The SwiftUI view hierarchy is never destroyed, preventing
        // the use-after-free crash that occurs during NSHostingController teardown.
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: true
            )
            w.title = "Commonplace"
            w.minSize = NSSize(width: 400, height: 300)
            w.isMovableByWindowBackground = false
            w.delegate = self
            // Standard macOS title bar with traffic lights in their own
            // row. Tabs render in a SwiftUI row directly below it (see
            // WorkspaceView), starting flush at x=0 — no inset needed
            // because traffic lights are above the tab row, not beside it.
            w.titleVisibility = .hidden
            w.collectionBehavior = [.moveToActiveSpace]
            let hc = NSHostingController(rootView: BrowseView())
            hc.sizingOptions = []
            w.contentViewController = hc

            // 70% of screen, centered
            if let screen = NSScreen.main?.visibleFrame {
                let width = screen.width * 0.7
                let height = screen.height * 0.7
                let x = screen.midX - width / 2
                let y = screen.midY - height / 2
                w.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
            } else {
                w.center()
            }
            window = w
        }

        // Order matters here:
        //   1. Flip activation policy FIRST so the app can fully take
        //      focus from another foreground app. Calling activate
        //      while still `.accessory` sometimes leaves the window
        //      behind whatever was previously active.
        //   2. Activate, then makeKeyAndOrderFront, then a defensive
        //      orderFrontRegardless to win against edge cases where
        //      the previous frontmost app refuses to yield focus.
        // Net effect: the archive window reliably surfaces as the
        // topmost window on the desktop on every show().
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()

        // Tell BrowseView to refresh its data
        NotificationCenter.default.post(name: Self.windowDidShowNotification, object: nil)
        return true
    }

    /// Opens the browse window and shows a specific highlight's detail view.
    func showHighlight(_ highlightId: String) {
        guard show() else { return }
        // Give SwiftUI a moment to set up, then post the detail notification
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            NotificationCenter.default.post(
                name: Self.showHighlightDetailNotification,
                object: nil,
                userInfo: ["highlightId": highlightId]
            )
            // Re-activate after the toast dismiss animation to ensure the window is on top
            self?.window?.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func showSettings() {
        guard show() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: Self.showSettingsNotification, object: nil)
        }
    }

    func dismiss() {
        // Drop back to accessory mode (no Dock icon, no menu bar)
        // before hiding so the transition is clean — the menu bar
        // vanishes along with the window instead of lingering for a
        // frame.
        NSApp.setActivationPolicy(.accessory)
        // Hide — don't close. Window and SwiftUI hierarchy stay alive.
        window?.orderOut(nil)
    }

    // Intercept the title bar close button: hide instead of close.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
    }

    func teardown() {
        toggleHotKey?.unregister()
        toggleHotKey = nil
        // Only on app quit: actually close and release
        window?.delegate = nil
        window?.close()
        window = nil
    }
}
