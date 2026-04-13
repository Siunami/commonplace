import SwiftUI
import AppKit

/// First-run permissions setup window. Shows required permissions with
/// live status updates. Auto-closes when all required permissions are granted.
struct PermissionsSetupView: View {
    let onComplete: () -> Void
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false
    @State private var pollTimer: Timer?

    private var allRequired: Bool {
        screenRecordingGranted
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 8)

            // Header
            VStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text("Permissions Required")
                    .font(.title2.weight(.semibold))

                Text("Commonplace needs a couple of permissions to work properly.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Permission cards
            VStack(spacing: 12) {
                permissionCard(
                    icon: "rectangle.dashed.badge.record",
                    iconColor: .red,
                    title: "Screen & System Audio Recording",
                    description: "Required to capture screenshots and record your screen.",
                    isGranted: screenRecordingGranted,
                    action: {
                        CGRequestScreenCaptureAccess()
                        openScreenRecordingSettings()
                    }
                )

                permissionCard(
                    icon: "accessibility",
                    iconColor: .blue,
                    title: "Accessibility",
                    description: "Enables capturing window titles and browser context.",
                    isGranted: accessibilityGranted,
                    action: openAccessibilitySettings,
                    isOptional: true
                )
            }

            // Continue button
            Button(action: onComplete) {
                Text(allRequired ? "Get Started" : "Continue Anyway")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(allRequired ? .accentColor : .gray)
            .padding(.horizontal, 20)

            Spacer().frame(height: 8)
        }
        .padding(32)
        .frame(width: 420)
        .onAppear { startPolling() }
        .onDisappear { pollTimer?.invalidate() }
    }

    // MARK: - Permission Card

    private func permissionCard(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        isGranted: Bool,
        action: @escaping () -> Void,
        isOptional: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor.opacity(0.8))
                .frame(width: 44, height: 44)
                .background(iconColor.opacity(0.1))
                .clipShape(Circle())

            // Text
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.callout.weight(.medium))
                    if isOptional {
                        Text("optional")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary.opacity(0.3))
                            .clipShape(Capsule())
                    }
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Status
                if isGranted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("Granted")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.green)
                } else {
                    Button(action: action) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 9))
                            Text("Open Settings")
                                .font(.caption)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isGranted ? Color.green.opacity(0.2) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Polling

    private func startPolling() {
        checkPermissions()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            checkPermissions()
        }
    }

    private func checkPermissions() {
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        accessibilityGranted = AXIsProcessTrusted()

        if allRequired {
            pollTimer?.invalidate()
            // Small delay so the user sees the green checkmarks
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onComplete()
            }
        }
    }

    // MARK: - Open Settings

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

    private static let hasCompletedKey = "hasCompletedPermissionsSetup"

    var needsSetup: Bool {
        !UserDefaults.standard.bool(forKey: Self.hasCompletedKey)
        && !CGPreflightScreenCaptureAccess()
    }

    func showIfNeeded() {
        guard needsSetup else { return }
        show()
    }

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PermissionsSetupView {
            UserDefaults.standard.set(true, forKey: Self.hasCompletedKey)
            self.window?.close()
            self.window = nil
            BrowseWindowController.shared.show()
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        w.isReleasedWhenClosed = false
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.contentViewController = NSHostingController(rootView: view)
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}
