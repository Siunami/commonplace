import AppKit

// MARK: - Protocol

protocol ManagedWindowController: AnyObject {
    /// Remove event monitors, close managed windows, and release resources.
    func teardown()
}

// MARK: - HotkeyMonitorSet

/// Encapsulates a global + local NSEvent monitor pair.
/// Calling `install()` always removes existing monitors first, preventing leaks.
final class HotkeyMonitorSet {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Install a hotkey handler. Returns `true` from the handler to swallow the event.
    func install(handler: @escaping (NSEvent) -> Bool) {
        remove()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = handler(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event) ? nil : event
        }
    }

    func remove() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    deinit { remove() }
}

// MARK: - PanelWindowDelegate

/// Lightweight NSWindowDelegate that nils out a panel reference on close.
/// Use this for window controllers that are not NSObject subclasses.
final class PanelWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
