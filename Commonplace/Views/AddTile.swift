import SwiftUI
import AppKit

/// Simple text note "+" tile pinned to the top-left of the Browse masonry.
/// Click to start typing, ⌘+Enter to save, Esc to cancel. Inherits the
/// current tag filter so notes land in the collection the user is viewing.
struct AddTile: View {
    let tagIds: [String]

    @State private var text: String = ""
    @State private var isEditing: Bool = false

    var body: some View {
        Group {
            if isEditing {
                expandedBody
            } else {
                collapsedBody
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            if !isEditing {
                isEditing = true
            }
        }
    }

    // MARK: - Collapsed

    private var collapsedBody: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Add note")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Expanded

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            NoteTextView(
                text: $text,
                onSubmit: save,
                onCancel: cancel
            )
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if hasText {
                Divider().opacity(0.5)
                AddButton(action: save)
            }
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { cancel(); return }
        HighlightCapture.shared.captureFromUserAdd(text: trimmed, tagIds: tagIds)
        text = ""
        isEditing = false
    }

    private func cancel() {
        text = ""
        isEditing = false
    }
}

// MARK: - Add Button (full-width footer, shown only when text is present)

private struct AddButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("Add")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovered ? Color.primary : Color.primary.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

// MARK: - NSTextView Wrapper

/// Wraps `NSTextView` in an `NSScrollView` with an overlay (thin, autohiding)
/// scroller style. SwiftUI's `TextEditor` uses the system's default scroller
/// style, which on most user systems is the fat legacy scrollbar that's always
/// visible even when the text fits — hence this wrapper. Also surfaces
/// ⌘+Return and Escape as callbacks, which `TextEditor` can't cleanly expose.
private struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = KeyTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = Self.serifFont(size: 13)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.autoresizingMask = [.width]

        if let container = textView.textContainer {
            container.widthTracksTextView = true
        }

        textView.onCmdReturn = onSubmit
        textView.onEscape = onCancel

        scrollView.documentView = textView

        // SwiftUI creates a fresh NSView each time `isEditing` flips to true,
        // so makeNSView fires exactly when the user just tapped to enter
        // editing mode — focus on next runloop tick.
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? KeyTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        // Closures re-capture current SwiftUI state each render; keep the
        // NSTextView pointing at the fresh ones.
        textView.onCmdReturn = onSubmit
        textView.onEscape = onCancel
    }

    private static func serifFont(size: CGFloat) -> NSFont {
        // Prefer the system "New York" serif; fall back to the system font
        // if it's unavailable. Matches the `.serif` design used elsewhere.
        if let serif = NSFont(name: "New York", size: size) { return serif }
        return .systemFont(ofSize: size)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        init(_ parent: NoteTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// `NSTextView` subclass that surfaces ⌘+Return and Escape as callbacks.
/// Plain Return still inserts a newline (normal prose behavior).
private final class KeyTextView: NSTextView {
    var onCmdReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // ⌘+Return or ⌘+Keypad-Enter → submit
        if event.modifierFlags.contains(.command) &&
           (event.keyCode == 36 || event.keyCode == 76) {
            onCmdReturn?()
            return
        }
        // Escape → cancel
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
