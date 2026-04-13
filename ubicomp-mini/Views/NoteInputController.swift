import SwiftUI
import AppKit

final class NoteInputController: ManagedWindowController {
    static let shared = NoteInputController()

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
        // Ctrl+Cmd+N
        guard event.modifierFlags.contains([.command, .control]),
              event.keyCode == 45 /* N */ else { return false }

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
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
                styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
                backing: .buffered,
                defer: true
            )
            p.title = "New Note"
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.delegate = delegate
            p.contentView = NSHostingView(rootView: NoteInputView(onDismiss: { [weak self] in
                self?.dismiss()
            }))
            p.center()
            panel = p
        }

        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        // Use orderOut (hide) instead of close (destroy) because dismiss
        // can be called from within NoteInputView's submit/onExitCommand.
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

// MARK: - Note Input View

private struct NoteInputView: View {
    var onDismiss: () -> Void
    @State private var noteText = ""

    private var trimmed: String {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 8) {
            TextEditor(text: $noteText)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Text("Esc to dismiss")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(trimmed.isEmpty ? Color.gray.opacity(0.3) : Color.yellow)
                }
                .buttonStyle(.plain)
                .disabled(trimmed.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
        .frame(width: 380)
        .onExitCommand { onDismiss() }
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        let h = Highlight(
            id: UUID().uuidString,
            timestamp: Date().timeIntervalSince1970,
            contentText: trimmed,
            highlightType: "note"
        )
        DatabaseManager.shared.insertHighlight(h)
        noteText = ""
        onDismiss()
    }
}
