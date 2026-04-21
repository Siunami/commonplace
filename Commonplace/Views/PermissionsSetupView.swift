import SwiftUI
import AppKit
import ApplicationServices

// Stepwise permissions gate. Presents one permission at a time; auto-advances
// when the user grants it. Blocks access to the rest of the app until both
// required permissions are granted.
struct PermissionsSetupView: View {
    let onComplete: () -> Void
    @ObservedObject private var perms = PermissionsMonitor.shared
    @State private var didFinish = false
    @State private var shortcutCheckPassed = false
    @State private var lastVerificationAt: Date?

    private enum Step {
        case screenRecording
        case accessibility
        case verification
    }

    private var step: Step {
        if !perms.screenRecordingGranted { return .screenRecording }
        if !perms.accessibilityGranted { return .accessibility }
        return .verification
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
                        buttonTitle: "Request Access",
                        action: requestScreenRecordingAccess
                    )
                case .accessibility:
                    permissionStep(
                        icon: "accessibility",
                        iconColor: .blue,
                        title: "Enable Accessibility",
                        description: "Lets Commonplace intercept ⌘⇧3 and ⌘⇧4 so screenshots flow into your archive instead of your desktop.",
                        buttonTitle: "Request Access",
                        action: requestAccessibilityAccess
                    )
                case .verification:
                    verificationStep
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
        .frame(width: 500, height: 560)
        .onAppear {
            if perms.allGranted {
                refreshVerification()
            }
        }
        .onChange(of: perms.allGranted) { _, granted in
            guard granted else {
                shortcutCheckPassed = false
                lastVerificationAt = nil
                return
            }
            refreshVerification()
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

            VStack(spacing: 4) {
                Text("Grant access to this build")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(Bundle.main.bundleURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.top, 4)
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

            Button("Open System Settings") {
                switch step {
                case .screenRecording:
                    openScreenRecordingSettings()
                case .accessibility:
                    openAccessibilitySettings()
                case .verification:
                    break
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for permission…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)
        }
    }

    private var verificationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Check this copy")
                    .font(.title3.weight(.semibold))
                Text("Commonplace found both permissions. Verify that this running build can actually use them before continuing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                verificationRow(
                    label: "Screen Recording",
                    detail: "Authorized for this app bundle",
                    passed: perms.screenRecordingGranted
                )
                verificationRow(
                    label: "Accessibility",
                    detail: "Trusted by macOS",
                    passed: perms.accessibilityGranted
                )
                verificationRow(
                    label: "Screenshot Shortcuts",
                    detail: shortcutCheckPassed
                        ? "Hotkeys are armed and ready"
                        : "Commonplace has not armed ⌘⇧3 / ⌘⇧4 yet",
                    passed: shortcutCheckPassed
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            if let lastVerificationAt {
                Text("Last checked \(lastVerificationAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                Button("Refresh Checks", action: refreshVerification)
                    .buttonStyle(.bordered)

                Button(action: finishSetup) {
                    Text("Open Commonplace")
                        .font(.callout.weight(.medium))
                        .frame(minWidth: 180)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!perms.allGranted || !shortcutCheckPassed)
            }

            Text("If the shortcut check does not turn green, reopen Accessibility for this exact app path and try Refresh Checks again.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func verificationRow(label: String, detail: String, passed: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(passed ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    private func requestScreenRecordingAccess() {
        let granted = CGRequestScreenCaptureAccess()
        PermissionsMonitor.shared.refresh()
        if !granted {
            openScreenRecordingSettings()
        }
    }

    private func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        PermissionsMonitor.shared.refresh()
    }

    private func refreshVerification() {
        PermissionsMonitor.shared.refresh()
        if perms.accessibilityGranted {
            ScreenshotShortcutHandler.shared.start()
            shortcutCheckPassed = ScreenshotShortcutHandler.shared.isInstalled
        } else {
            shortcutCheckPassed = false
        }
        lastVerificationAt = Date()
    }

    private func finishSetup() {
        guard !didFinish else { return }
        didFinish = true
        onComplete()
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
