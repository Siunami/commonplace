import SwiftUI
import AppKit

/// Full-window image viewer with zoom and pan.
///
/// Gestures:
///   - Trackpad pinch / magnify — zoom 1x–5x
///   - Scroll wheel — zoom 1x–5x
///   - Double-click — toggle between 1x and 2.5x
///   - Drag when zoomed — pan
///   - Click backdrop at 1x — dismiss; click backdrop when zoomed — reset zoom
///   - Esc — dismiss
struct FullImageViewer: View {
    let image: NSImage
    var onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var closeButtonHovered = false

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if scale > 1.01 {
                        resetZoom()
                    } else {
                        onDismiss()
                    }
                }

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let proposed = lastScale * value
                            scale = min(max(proposed, minScale), maxScale)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= minScale + 0.01 {
                                resetZoom()
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1.0 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    if scale > 1.01 {
                        resetZoom()
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }
                .background(
                    ScrollWheelZoomCatcher { delta in
                        let step = 1.0 + (delta * 0.01)
                        let proposed = scale * step
                        let clamped = min(max(proposed, minScale), maxScale)
                        scale = clamped
                        lastScale = clamped
                        if clamped <= minScale + 0.01 {
                            lastOffset = .zero
                            offset = .zero
                        }
                    }
                )

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle().fill(.black.opacity(closeButtonHovered ? 0.75 : 0.5))
                            )
                            .overlay(
                                Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { closeButtonHovered = $0 }
                    .help("Close (Esc)")
                    .padding(20)
                }
                Spacer()
            }
        }
        .onExitCommand(perform: onDismiss)
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
}

/// Captures scroll-wheel events as zoom deltas. Transparent to other input.
private struct ScrollWheelZoomCatcher: NSViewRepresentable {
    let onDelta: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollCatcherView()
        view.onDelta = onDelta
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollCatcherView)?.onDelta = onDelta
    }

    final class ScrollCatcherView: NSView {
        var onDelta: ((CGFloat) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            let delta = event.scrollingDeltaY
            guard delta != 0 else { return }
            onDelta?(delta)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Stay transparent to mouse clicks — only capture scroll events.
            return nil
        }
    }
}

// MARK: - Expand Button Overlay

/// Small expand icon that appears in the top-right on hover. Use as an
/// overlay on thumbnails/heroes inside tap-to-open cards — calling the
/// expand handler presents the full viewer without triggering the card tap.
struct ExpandImageButton: View {
    var isHovered: Bool
    var action: () -> Void
    @State private var buttonHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(.black.opacity(buttonHovered ? 0.75 : 0.55))
                )
                .overlay(
                    Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { buttonHovered = $0 }
        .help("View full size")
        .padding(6)
        .opacity(isHovered ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
