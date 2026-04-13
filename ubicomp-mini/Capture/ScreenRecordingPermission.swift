import Foundation
import CoreGraphics
import AppKit

enum ScreenRecordingPermission {
    static var preflight: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private static let noPermissionKey = "screenRecordingNoPermission"

    static func recordNoPermission() {
        if !UserDefaults.standard.bool(forKey: noPermissionKey) {
            UserDefaults.standard.set(true, forKey: noPermissionKey)
            print("[Capture] No screen recording permission")
        }
    }

    private static let staleKey = "screenRecordingStale"
    private static var consecutiveFailures = 0
    private static let staleThreshold = 3

    static var isStale: Bool {
        get { UserDefaults.standard.bool(forKey: staleKey) }
        set { UserDefaults.standard.set(newValue, forKey: staleKey) }
    }

    static func recordCaptureFailure() {
        guard CGPreflightScreenCaptureAccess() else { return }
        consecutiveFailures += 1
        if consecutiveFailures >= staleThreshold && !isStale {
            isStale = true
            print("[Capture] Stale permission detected after \(consecutiveFailures) consecutive failures")
        }
    }

    static func recordCaptureSuccess() {
        consecutiveFailures = 0
        if isStale {
            isStale = false
            print("[Capture] Permission working again, cleared stale flag")
        }
        if UserDefaults.standard.bool(forKey: noPermissionKey) {
            UserDefaults.standard.set(false, forKey: noPermissionKey)
            print("[Capture] Permission granted, cleared no-permission flag")
        }
    }
}
