import AppKit

/// Messages.app lacks pasteboard permalinks and its AX tree keeps
/// conversation names inside the window title most of the time. We try a
/// short AppleScript query for the focused conversation first (200 ms
/// budget — the registry also enforces 300 ms on the whole enricher) and
/// fall back to parsing the window title.
///
/// Observed title shapes:
///   - `Messages`
///   - `{conversation name}`
///   - `{conversation name} ({n})`   (unread suffix)
final class MessagesSourceEnricher: SourceEnricher {
    let supportedBundleIds: Set<String> = [
        "com.apple.MobileSMS",
    ]

    func enrich(_ inputs: RawCaptureInputs) -> [SourceContextEntry] {
        if let scripted = conversationName(), !scripted.isEmpty {
            return [
                SourceContextEntry(
                    key: "conversation",
                    label: "Conversation",
                    value: scripted,
                    icon: "bubble.left.fill"
                )
            ]
        }
        if let fromTitle = parseWindowTitle(inputs.windowTitle) {
            return [
                SourceContextEntry(
                    key: "conversation",
                    label: "Conversation",
                    value: fromTitle,
                    icon: "bubble.left.fill"
                )
            ]
        }
        return []
    }

    func parseWindowTitle(_ windowTitle: String?) -> String? {
        guard var title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty,
              title.caseInsensitiveCompare("Messages") != .orderedSame else { return nil }

        if let r = title.range(of: #" \(\d+\)\s*$"#, options: .regularExpression) {
            title.removeSubrange(r)
        }
        return title.trimmingCharacters(in: .whitespaces).isEmpty ? nil : title
    }

    // MARK: - AppleScript

    private func conversationName() -> String? {
        // `name of front window` is the most reliable way to recover the
        // selected conversation, since Messages mirrors it into the title
        // bar but often adds decorative suffixes. Short script, 200 ms
        // hard timeout so we never block the capture hot path.
        let script = "tell application \"Messages\" to return name of front window"
        return runAppleScript(script, timeout: 0.2)
    }

    private func runAppleScript(_ source: String, timeout: TimeInterval) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }

        var result: String?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let output = script.executeAndReturnError(&error)
            if error == nil {
                result = output.stringValue
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            return nil
        }
        return result
    }
}
