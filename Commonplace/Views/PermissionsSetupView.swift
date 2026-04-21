import SwiftUI
import AppKit

// Stepwise permissions gate. Presents one permission at a time; auto-advances
// when the user grants it. Blocks access to the rest of the app until both
// required permissions are granted.
struct PermissionsSetupView: View {
    let onComplete: () -> Void
    @ObservedObject private var perms = PermissionsMonitor.shared
    @State private var didFinish = false

    private enum Step {
        case screenRecording
        case accessibility
        case done
    }

    private var step: Step {
        if !perms.screenRecordingGranted { return .screenRecording }
        if !perms.accessibilityGranted { return .accessibility }
        return .done
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.4).padding(.top, 8)

            stepIndicator
                .padding(.top, 18)
                .padding(.bottom, 8)

            Group {
                switch step {
                case .screenRecording:
                    permissionStep(
                        icon: "rectangle.dashed.badge.record",
                        iconColor: .red,
                        title: "Enable Screen Recording",
                        description: "Commonplace needs this to capture screenshots and record your screen.",
                        buttonTitle: "Open System Settings",
                        action: openScreenRecordingSettings
                    )
                case .accessibility:
                    permissionStep(
                        icon: "accessibility",
                        iconColor: .blue,
                        title: "Enable Accessibility",
                        description: "Lets Commonplace intercept ⌘⇧3, ⌘⇧4, and ⌘⇧5 so screenshots flow into your archive instead of your desktop.",
                        buttonTitle: "Open System Settings",
                        action: openAccessibilitySettings
                    )
                case .done:
                    doneStep
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .animation(.easeInOut(duration: 0.25), value: step)

            Spacer(minLength: 0)

            footer
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
        }
        .frame(width: 460, height: 520)
        .onChange(of: perms.allGranted) { _, granted in
            guard granted, !didFinish else { return }
            didFinish = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { onComplete() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
                .padding(.top, 28)

            Text("Welcome to Commonplace")
                .font(.title3.weight(.semibold))

            Text("Two quick permissions and you're set.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 10) {
            stepDot(filled: true, done: perms.screenRecordingGranted, label: "Screen Recording")
            Rectangle()
                .fill(perms.screenRecordingGranted ? Color.green.opacity(0.6) : Color.primary.opacity(0.15))
                .frame(width: 30, height: 1)
            stepDot(
                filled: perms.screenRecordingGranted,
                done: perms.accessibilityGranted,
                label: "Accessibility"
            )
        }
    }

    private func stepDot(filled: Bool, done: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(filled ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.25), lineWidth: 1)
                    .frame(width: 14, height: 14)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                } else if filled {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(filled ? .primary : .tertiary)
        }
    }

    private func permissionStep(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(iconColor)
                .frame(width: 72, height: 72)
                .background(iconColor.opacity(0.1))
                .clipShape(Circle())

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: action) {
                Text(buttonTitle)
                    .font(.callout.weight(.medium))
                    .frame(minWidth: 200)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for permission…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("All set")
                .font(.title2.weight(.semibold))

            Text("Commonplace is ready.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(action: onComplete) {
                Text("Get Started")
                    .font(.callout.weight(.medium))
                    .frame(minWidth: 200)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var footer: some View {
        HStack {
            Text("You can revisit these anytime in Settings.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
        }
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Window Controller

final class PermissionsWindowController {
    static let shared = PermissionsWindowController()

    private var window: NSWindow?
    private var revocationObserver: NSObjectProtocol?

    var needsSetup: Bool {
        !PermissionsMonitor.shared.allGranted
    }

    func showIfNeeded() {
        guard needsSetup else { return }
        show()
    }

    func startWatchingForRevocation() {
        guard revocationObserver == nil else { return }
        revocationObserver = NotificationCenter.default.addObserver(
            forName: .permissionsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if !PermissionsMonitor.shared.allGranted {
                self.showIfNeeded()
            }
        }
    }

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PermissionsSetupView { [weak self] in
            self?.window?.close()
            self?.window = nil
            BrowseWindowController.shared.show()
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        w.isReleasedWhenClosed = false
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.level = .floating
        w.contentViewController = NSHostingController(rootView: view)
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}
