import AppKit

final class BrowserURLExtractor {
    static let shared = BrowserURLExtractor()

    private static let knownBrowsers: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser", // Arc
    ]

    private var urlCache: [String: (url: String, timestamp: Date)] = [:]
    private let cacheTimeout: TimeInterval = 2.0

    func extractURL(bundleId: String) -> String? {
        guard Self.knownBrowsers.contains(bundleId) else { return nil }

        // Return cached value if fresh
        if let cached = urlCache[bundleId],
           Date().timeIntervalSince(cached.timestamp) < cacheTimeout {
            return cached.url
        }

        let script: String
        switch bundleId {
        case "com.apple.Safari":
            script = "tell application \"Safari\" to get URL of current tab of front window"
        case "org.mozilla.firefox":
            // Firefox doesn't support AppleScript URL queries reliably
            return urlCache[bundleId]?.url
        default:
            // Chrome-based browsers (Chrome, Brave, Edge, Arc)
            let appName = appName(for: bundleId)
            script = "tell application \"\(appName)\" to get URL of active tab of front window"
        }

        guard let url = runAppleScript(script) else {
            return urlCache[bundleId]?.url
        }

        urlCache[bundleId] = (url: url, timestamp: Date())
        return url
    }

    private func appName(for bundleId: String) -> String {
        switch bundleId {
        case "com.google.Chrome": return "Google Chrome"
        case "com.google.Chrome.canary": return "Google Chrome Canary"
        case "com.brave.Browser": return "Brave Browser"
        case "com.microsoft.edgemac": return "Microsoft Edge"
        case "company.thebrowser.Browser": return "Arc"
        default: return "Google Chrome"
        }
    }

    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }

        var result: String?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let output = script.executeAndReturnError(&error)
            if error != nil {
                // Don't log here — caller handles fallback
            } else {
                result = output.stringValue
            }
            semaphore.signal()
        }

        let timeout = semaphore.wait(timeout: .now() + 0.5)
        if timeout == .timedOut {
            CaptureLog.warning("AppleScript timed out for browser URL extraction")
            return nil
        }

        return result
    }
}
