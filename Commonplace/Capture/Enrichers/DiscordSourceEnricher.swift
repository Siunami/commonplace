import Foundation

/// Pulls guild/channel/permalink from the HTML pasteboard flavor Discord
/// attaches to copied messages. The canonical permalink shape is
/// `https://discord.com/channels/{guildId}/{channelId}/{messageId}`.
/// Falls back to `windowTitle` parsing when HTML is absent.
final class DiscordSourceEnricher: SourceEnricher {
    let supportedBundleIds: Set<String> = [
        "com.hnc.Discord",
    ]

    func enrich(_ inputs: RawCaptureInputs) -> [SourceContextEntry] {
        if let fromHTML = parseFromHTML(inputs.pasteboardHTML), !fromHTML.isEmpty {
            return fromHTML
        }
        if let fallback = parseWindowTitle(inputs.windowTitle) {
            return [fallback]
        }
        return []
    }

    // Matches both `discord.com/channels/...` and `discordapp.com/...`.
    private static let permalinkRegex: NSRegularExpression? = {
        let pattern = #"https://(?:[a-z]+\.)?discord(?:app)?\.com/channels/(\d+|@me)/(\d+)/(\d+)"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    func parseFromHTML(_ html: String?) -> [SourceContextEntry]? {
        guard let html, !html.isEmpty,
              let regex = Self.permalinkRegex else { return nil }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: nsRange),
              match.numberOfRanges == 4,
              let guildRange = Range(match.range(at: 1), in: html),
              let channelRange = Range(match.range(at: 2), in: html),
              let fullRange = Range(match.range(at: 0), in: html) else { return nil }

        let guildId = String(html[guildRange])
        let channelId = String(html[channelRange])
        let permalink = String(html[fullRange])

        var entries: [SourceContextEntry] = []
        if guildId != "@me" {
            entries.append(
                SourceContextEntry(
                    key: "discord_guild",
                    label: "Server",
                    value: guildId,
                    icon: "server.rack"
                )
            )
        }
        entries.append(
            SourceContextEntry(
                key: "discord_channel",
                label: "Channel",
                value: "#\(channelId)",
                icon: "number"
            )
        )
        entries.append(
            SourceContextEntry(
                key: "discord_permalink",
                label: "Message",
                value: "Open in Discord",
                icon: "arrow.up.right.square",
                url: permalink
            )
        )
        return entries
    }

    /// Discord titles tend to read like `"#channel | Server - Discord"` or
    /// `"@user - Discord"`. When permalink HTML is missing we keep the
    /// most distinctive fragment.
    func parseWindowTitle(_ windowTitle: String?) -> SourceContextEntry? {
        guard var title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty,
              title.caseInsensitiveCompare("Discord") != .orderedSame else { return nil }

        if let range = title.range(of: #"\s*[-–—]\s*Discord\s*$"#, options: .regularExpression) {
            title = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        let firstSegment = title
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first ?? title

        guard !firstSegment.isEmpty else { return nil }

        return SourceContextEntry(
            key: "chat_name",
            label: "Channel",
            value: firstSegment,
            icon: "bubble.left.fill"
        )
    }
}
