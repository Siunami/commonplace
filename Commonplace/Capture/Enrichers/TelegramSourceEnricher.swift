import Foundation

/// Parses Telegram Desktop window titles to recover the active chat name.
/// Telegram doesn't expose any AppleScript dictionary and its AX tree only
/// surfaces titles; the window title is the most reliable signal.
///
/// Observed title shapes (macOS Telegram Desktop, macOS Telegram):
///   - `Telegram`
///   - `Telegram @ {handle}`       (1:1 chat, username known)
///   - `Telegram - {chat name}`
///   - `{chat name} - Telegram`
///   - `Telegram ({n})`            (unread-count prefix; strip trailing `({n})`)
final class TelegramSourceEnricher: SourceEnricher {
    let supportedBundleIds: Set<String> = [
        "ru.keepcoder.Telegram",
        "org.telegram.desktop",
    ]

    func enrich(_ inputs: RawCaptureInputs) -> [SourceContextEntry] {
        var entries: [SourceContextEntry] = []

        if let chat = parseChatName(from: inputs.windowTitle) {
            entries.append(
                SourceContextEntry(
                    key: "chat_name",
                    label: "Chat",
                    value: chat,
                    icon: "bubble.left.fill"
                )
            )
        }

        if isForwardedMessage(text: inputs.pasteboardText) {
            entries.append(
                SourceContextEntry(
                    key: "forwarded",
                    label: "Forwarded",
                    value: "yes",
                    icon: "arrowshape.turn.up.right"
                )
            )
        }

        return entries
    }

    // MARK: - Parsers

    func parseChatName(from windowTitle: String?) -> String? {
        guard var title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }

        // Strip unread-count suffix: `Telegram (3)` → `Telegram`
        if let r = title.range(of: #" \(\d+\)\s*$"#, options: .regularExpression) {
            title.removeSubrange(r)
        }

        // `Telegram` alone — no chat to report.
        if title.caseInsensitiveCompare("Telegram") == .orderedSame { return nil }

        // `Telegram @ handle` → handle
        if let range = title.range(of: #"^Telegram\s*@\s*"#, options: .regularExpression) {
            let rest = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }

        // `Telegram - chat` → chat
        if let range = title.range(of: #"^Telegram\s*[-–—]\s*"#, options: .regularExpression) {
            let rest = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }

        // `chat - Telegram` → chat
        if let range = title.range(of: #"\s*[-–—]\s*Telegram\s*$"#, options: .regularExpression) {
            let rest = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }

        // Unknown format — surface the whole title rather than drop signal.
        return title
    }

    func isForwardedMessage(text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        let firstLine = text.split(whereSeparator: \.isNewline).first ?? Substring(text)
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        // Telegram inserts a `>` quote prefix on forwarded copies.
        return trimmed.hasPrefix(">")
    }
}
