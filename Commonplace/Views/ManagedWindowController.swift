import AppKit

// MARK: - Protocol

protocol ManagedWindowController: AnyObject {
    /// Remove event monitors, close managed windows, and release resources.
    func teardown()
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
