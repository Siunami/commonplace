import SwiftUI
import AppKit

/// Wraps SwiftUI canvas content in an `NSView` that captures macOS
/// scroll-wheel and magnify events. SwiftUI's `MagnificationGesture`
/// and `DragGesture` don't see trackpad two-finger scroll, and pinch
/// gets eaten when the cursor lands on a card with its own gestures
/// — both of those make the canvas feel broken next to TLDraw/Figma.
///
/// **Event routing**: scrollWheel and magnify events on macOS are
/// delivered to the view under the cursor first; if that view doesn't
/// implement the event, AppKit walks the view hierarchy upward until
/// something handles it. SwiftUI cards don't implement scrollWheel or
/// magnify, so events bubble out of the inner `NSHostingView` and into
/// our wrapper class. Mouse clicks still hit the SwiftUI views inside.
///
/// Usage:
/// ```
/// CanvasInputWrapper(onScroll: { ... }, onMagnify: { ... }) {
///     // SwiftUI canvas content
/// }
/// ```
struct CanvasInputWrapper<Content: View>: NSViewRepresentable {
    /// (deltaX, deltaY, isCommandHeld, locationInView)
    /// - With natural scrolling: positive deltas mean the user wants the
    ///   canvas to pan in that direction (swipe right → see content to
    ///   the right → cameraOffset.x should decrease).
    /// - `isCommandHeld` lets the canvas treat ⌘+scroll as zoom (Figma
    ///   convention) instead of pan.
    let onScroll: (CGFloat, CGFloat, Bool, CGPoint) -> Void
    /// (relativeMagnification, locationInView)
    /// `relativeMagnification` is the per-event delta from
    /// `NSEvent.magnification`; the receiver multiplies its current
    /// zoom by `(1 + relativeMagnification)`.
    let onMagnify: (CGFloat, CGPoint) -> Void
    /// Latest cursor location in the wrapper's local coord space (top-
    /// left origin, SwiftUI convention). Fires on every `mouseMoved`
    /// while the cursor is inside the wrapper. `WorkspaceCanvasView`
    /// uses this to know where to land a `⌘V` paste — keyboard events
    /// don't carry a cursor position, so we cache the latest one.
    let onMouseMove: (CGPoint) -> Void
    @ViewBuilder var content: Content

    init(
        onScroll: @escaping (CGFloat, CGFloat, Bool, CGPoint) -> Void,
        onMagnify: @escaping (CGFloat, CGPoint) -> Void,
        onMouseMove: @escaping (CGPoint) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.onScroll = onScroll
        self.onMagnify = onMagnify
        self.onMouseMove = onMouseMove
        self.content = content()
    }

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        view.onScroll = onScroll
        view.onMagnify = onMagnify
        view.onMouseMove = onMouseMove

        let host = NSHostingView(rootView: content)
        host.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host)
        view.hostingView = host
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.topAnchor.constraint(equalTo: view.topAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return view
    }

    func updateNSView(_ nsView: InputView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onMagnify = onMagnify
        nsView.onMouseMove = onMouseMove
        nsView.hostingView?.rootView = content
    }

    final class InputView: NSView {
        var onScroll: (CGFloat, CGFloat, Bool, CGPoint) -> Void = { _, _, _, _ in }
        var onMagnify: (CGFloat, CGPoint) -> Void = { _, _ in }
        var onMouseMove: (CGPoint) -> Void = { _ in }
        var hostingView: NSHostingView<Content>? = nil

        override var acceptsFirstResponder: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            // Replace any prior areas — `updateTrackingAreas` fires on
            // every bounds change, and AppKit doesn't dedupe.
            for area in trackingAreas { removeTrackingArea(area) }
            // `.activeInKeyWindow` is enough — paste only matters when
            // the user is focused on this window. `.inVisibleRect` keeps
            // the area auto-sized to the view's visible bounds, so a
            // resize doesn't strand the tracking rect.
            let opts: NSTrackingArea.Options = [
                .activeInKeyWindow,
                .mouseMoved,
                .inVisibleRect
            ]
            addTrackingArea(NSTrackingArea(rect: .zero, options: opts, owner: self, userInfo: nil))
        }

        override func mouseMoved(with event: NSEvent) {
            let local = convert(event.locationInWindow, from: nil)
            let flipped = CGPoint(x: local.x, y: bounds.height - local.y)
            onMouseMove(flipped)
        }

        override func scrollWheel(with event: NSEvent) {
            // AppKit window coords are bottom-left origin; SwiftUI is
            // top-left. Flip Y so callers can use the location in the
            // same coord system the rest of the canvas (GeometryReader,
            // .position, etc.) uses.
            let local = convert(event.locationInWindow, from: nil)
            let flipped = CGPoint(x: local.x, y: bounds.height - local.y)
            let isCmd = event.modifierFlags.contains(.command)
            onScroll(event.scrollingDeltaX, event.scrollingDeltaY, isCmd, flipped)
            // Don't call super — we own the event. Otherwise the event
            // continues up the responder chain and a parent NSScrollView
            // (if any) would also pan.
        }

        override func magnify(with event: NSEvent) {
            let local = convert(event.locationInWindow, from: nil)
            let flipped = CGPoint(x: local.x, y: bounds.height - local.y)
            onMagnify(event.magnification, flipped)
        }
    }
}
