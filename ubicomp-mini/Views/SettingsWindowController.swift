import SwiftUI
import AppKit

final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        w.isReleasedWhenClosed = false
        w.title = "Commonplace — Settings"
        w.contentViewController = NSHostingController(rootView:
            ScrollView {
                SettingsView()
                    .frame(width: 340)
            }
        )
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}
