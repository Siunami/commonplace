import Foundation

/// Pulls workspace/channel/permalink from the HTML pasteboard flavor Slack
/// attaches to copied messages. The permalink pattern is public and stable:
/// `https://{workspace}.slack.com/archives/{channelId}/p{timestampMicros}`.
/// Falls back to `windowTitle` parsing when HTML is absent.
final class SlackSourceEnricher: SourceEnricher {
    let supportedBundleIds: Set<String> = [
        "com.tinyspeck.slackmacgap",
    ]

    func enrich(_ inputs: RawCaptureInputs) -> [SourceContextEntry] {
        if let fromHTML = parseFromHTML(inputs.pasteboardHTML), !fromHTML.isEmpty {
            return fromHTML
        }
        if let chat = parseWorkspaceAndChat(from: inputs.windowTitle) {
            return chat
        }
        return []
    }

    // MARK: - HTML permalink parsing

    /// Matches `https://{workspace}.slack.com/archives/{channelId}/p{ts}`
    /// anywhere inside the HTML blob.
    private static let permalinkRegex: NSRegularExpression? = {
        let pattern = #"https://([a-z0-9-]+)\.slack\.com/archives/([A-Z0-9]+)/p(\d+)"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    func parseFromHTML(_ html: String?) -> [SourceContextEntry]? {
        guard let html, !html.isEmpty,
              let regex = Self.permalinkRegex else { return nil }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: nsRange),
              match.numberOfRanges == 4,
              let workspaceRange = Range(match.range(at: 1), in: html),
              let channelRange = Range(match.range(at: 2), in: html),
              let fullRange = Range(match.range(at: 0), in: html) else { return nil }

        let workspace = String(html[workspaceRange])
        let channelId = String(html[channelRange])
        let permalink = String(html[fullRange])

        return [
            SourceContextEntry(
                key: "slack_workspace",
                label: "Workspace",
                value: workspace,
                icon: "building.2"
            ),
            SourceContextEntry(
                key: "slack_channel",
                label: "Channel",
                value: "#\(channelId)",
                icon: "number"
            ),
            SourceContextEntry(
                key: "slack_permalink",
                label: "Message",
                value: "Open in Slack",
                icon: "arrow.up.right.square",
                url: permalink
            ),
        ]
    }

    // MARK: - Window-title fallback

    /// Slack titles typically look like `"Slack | {channel} | {workspace}"`
    /// or `"Slack - #channel - workspace"`. When the HTML permalink is
    /// missing we surface whatever we can pull out of that string.
    func parseWorkspaceAndChat(from windowTitle: String?) -> [SourceContextEntry]? {
        guard let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty,
              title.caseInsensitiveCompare("Slack") != .orderedSame else { return nil }

        let separators: CharacterSet = CharacterSet(charactersIn: "|-–—")
        let parts = title.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare("Slack") != .orderedSame }

        guard !parts.isEmpty else { return nil }

        var entries: [SourceContextEntry] = []
        if let channel = parts.first {
            entries.append(
                SourceContextEntry(
                    key: "slack_channel",
                    label: "Channel",
                    value: channel,
                    icon: "number"
                )
            )
        }
        if parts.count >= 2 {
            entries.append(
                SourceContextEntry(
                    key: "slack_workspace",
                    label: "Workspace",
                    value: parts[1],
                    icon: "building.2"
                )
            )
        }
        return entries
    }
}
