import SwiftUI
import AppKit

final class ClipboardPanelController: ManagedWindowController {
    static let shared = ClipboardPanelController()

    private var panel: NSPanel?
    private var panelDelegate: PanelWindowDelegate?
    private let hotkeys = HotkeyMonitorSet()

    func registerHotkey() {
        hotkeys.install { [weak self] event in
            self?.handleKeyEvent(event) ?? false
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Ctrl+Cmd+V
        guard event.modifierFlags.contains([.command, .control]),
              event.keyCode == 9 /* V */ else { return false }

        DispatchQueue.main.async { self.toggle() }
        return true
    }

    func toggle() {
        if let panel = panel, panel.isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            let delegate = PanelWindowDelegate { [weak self] in
                self?.panel = nil
                self?.panelDelegate = nil
            }
            self.panelDelegate = delegate

            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 400),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
                backing: .buffered,
                defer: true
            )
            p.title = "Clipboard History"
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.delegate = delegate
            p.contentView = NSHostingView(rootView: ClipboardHistoryView())
            p.center()
            panel = p
        }

        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        // Use orderOut (hide) instead of close (destroy) because dismiss
        // can be called from within a SwiftUI action on this panel's content.
        // Closing the panel from inside its own view hierarchy crashes.
        panel?.orderOut(nil)
    }

    func teardown() {
        hotkeys.remove()
        panel?.delegate = nil
        panel?.close()
        panel = nil
        panelDelegate = nil
    }
}
