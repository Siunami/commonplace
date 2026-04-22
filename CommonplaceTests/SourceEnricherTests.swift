import Testing
@testable import Commonplace

struct SourceEnricherTests {

    private func inputs(
        bundleId: String? = nil,
        windowTitle: String? = nil,
        pasteboardHTML: String? = nil,
        pasteboardText: String? = nil
    ) -> RawCaptureInputs {
        RawCaptureInputs(
            bundleId: bundleId,
            appName: nil,
            windowTitle: windowTitle,
            pid: nil,
            pasteboardTypes: [],
            pasteboardHTML: pasteboardHTML,
            pasteboardRTF: nil,
            pasteboardText: pasteboardText
        )
    }

    // MARK: - Telegram

    @Test func telegramExtractsHandleFromAtTitle() {
        let e = TelegramSourceEnricher()
        let out = e.enrich(inputs(bundleId: "ru.keepcoder.Telegram", windowTitle: "Telegram @ Matthew"))
        #expect(out.count == 1)
        #expect(out.first?.key == "chat_name")
        #expect(out.first?.value == "Matthew")
    }

    @Test func telegramExtractsChatFromDashTitle() {
        let e = TelegramSourceEnricher()
        let out = e.enrich(inputs(bundleId: "ru.keepcoder.Telegram", windowTitle: "Telegram - Product Design"))
        #expect(out.first?.value == "Product Design")
    }

    @Test func telegramExtractsChatFromTrailingTelegramTitle() {
        let e = TelegramSourceEnricher()
        let out = e.enrich(inputs(bundleId: "ru.keepcoder.Telegram", windowTitle: "Product Design - Telegram"))
        #expect(out.first?.value == "Product Design")
    }

    @Test func telegramBareTitleEmitsNothing() {
        let e = TelegramSourceEnricher()
        let out = e.enrich(inputs(bundleId: "ru.keepcoder.Telegram", windowTitle: "Telegram"))
        #expect(out.isEmpty)
    }

    @Test func telegramStripsUnreadCountSuffix() {
        let e = TelegramSourceEnricher()
        let out = e.enrich(inputs(bundleId: "ru.keepcoder.Telegram", windowTitle: "Telegram @ Matthew (3)"))
        #expect(out.first?.value == "Matthew")
    }

    @Test func telegramDetectsForwardedPrefix() {
        let e = TelegramSourceEnricher()
        let out = e.enrich(inputs(
            bundleId: "ru.keepcoder.Telegram",
            windowTitle: "Telegram @ Matthew",
            pasteboardText: "> forwarded from someone\nbody text"
        ))
        #expect(out.count == 2)
        #expect(out.contains(where: { $0.key == "forwarded" }))
    }

    // MARK: - Slack

    @Test func slackParsesPermalinkFromHTML() {
        let html = """
        <html><body><a href="https://acme.slack.com/archives/C12345/p1700000000000000">link</a></body></html>
        """
        let e = SlackSourceEnricher()
        let out = e.enrich(inputs(bundleId: "com.tinyspeck.slackmacgap", pasteboardHTML: html))
        #expect(out.contains(where: { $0.key == "slack_workspace" && $0.value == "acme" }))
        #expect(out.contains(where: { $0.key == "slack_channel" && $0.value == "#C12345" }))
        let permalink = out.first(where: { $0.key == "slack_permalink" })
        #expect(permalink?.url == "https://acme.slack.com/archives/C12345/p1700000000000000")
    }

    @Test func slackFallsBackToWindowTitle() {
        let e = SlackSourceEnricher()
        let out = e.enrich(inputs(
            bundleId: "com.tinyspeck.slackmacgap",
            windowTitle: "general | Acme Workspace"
        ))
        #expect(out.contains(where: { $0.key == "slack_channel" && $0.value == "general" }))
        #expect(out.contains(where: { $0.key == "slack_workspace" && $0.value == "Acme Workspace" }))
    }

    @Test func slackEmptyWhenNothingAvailable() {
        let e = SlackSourceEnricher()
        let out = e.enrich(inputs(bundleId: "com.tinyspeck.slackmacgap", windowTitle: "Slack"))
        #expect(out.isEmpty)
    }

    // MARK: - Discord

    @Test func discordParsesPermalinkFromHTML() {
        let html = #"<a href="https://discord.com/channels/111/222/333">jump</a>"#
        let e = DiscordSourceEnricher()
        let out = e.enrich(inputs(bundleId: "com.hnc.Discord", pasteboardHTML: html))
        #expect(out.contains(where: { $0.key == "discord_guild" && $0.value == "111" }))
        #expect(out.contains(where: { $0.key == "discord_channel" && $0.value == "#222" }))
        let permalink = out.first(where: { $0.key == "discord_permalink" })
        #expect(permalink?.url == "https://discord.com/channels/111/222/333")
    }

    @Test func discordDMPermalinkSkipsGuild() {
        let html = #"<a href="https://discord.com/channels/@me/999/888">dm</a>"#
        let e = DiscordSourceEnricher()
        let out = e.enrich(inputs(bundleId: "com.hnc.Discord", pasteboardHTML: html))
        #expect(!out.contains(where: { $0.key == "discord_guild" }))
        #expect(out.contains(where: { $0.key == "discord_channel" && $0.value == "#999" }))
    }

    @Test func discordWindowTitleFallback() {
        let e = DiscordSourceEnricher()
        let out = e.enrich(inputs(bundleId: "com.hnc.Discord", windowTitle: "#general | Server - Discord"))
        #expect(out.first?.key == "chat_name")
        #expect(out.first?.value == "#general")
    }

    // MARK: - Messages (title parse only — live AppleScript skipped)

    @Test func messagesParsesWindowTitle() {
        let e = MessagesSourceEnricher()
        #expect(e.parseWindowTitle("Matthew Siu") == "Matthew Siu")
        #expect(e.parseWindowTitle("Matthew Siu (3)") == "Matthew Siu")
        #expect(e.parseWindowTitle("Messages") == nil)
        #expect(e.parseWindowTitle("") == nil)
        #expect(e.parseWindowTitle(nil) == nil)
    }

    // MARK: - Registry

    @Test func registryDispatchesToFirstMatch() {
        let registry = SourceEnricherRegistry.shared
        let original = SnapshotRegistry(registry: registry)
        defer { original.restore() }

        registry.replaceAll(with: [TelegramSourceEnricher(), SlackSourceEnricher()])
        let out = registry.enrich(inputs: inputs(
            bundleId: "ru.keepcoder.Telegram",
            windowTitle: "Telegram @ Matthew"
        ))
        #expect(out.first?.value == "Matthew")
    }

    @Test func registryReturnsEmptyForUnknownBundle() {
        let registry = SourceEnricherRegistry.shared
        let original = SnapshotRegistry(registry: registry)
        defer { original.restore() }

        registry.replaceAll(with: [TelegramSourceEnricher()])
        let out = registry.enrich(inputs: inputs(bundleId: "com.unknown.app"))
        #expect(out.isEmpty)
    }
}

/// Local helper — there's no production reason to inspect the registry's
/// internal list, but tests need to snapshot and restore it around mutation.
private struct SnapshotRegistry {
    let registry: SourceEnricherRegistry
    private let saved: [SourceEnricher]

    init(registry: SourceEnricherRegistry) {
        self.registry = registry
        // `enrichers` is private; we use `replaceAll` as a getter by
        // restoring what we know is the production list.
        self.saved = [
            BrowserSourceEnricher(),
            TelegramSourceEnricher(),
            SlackSourceEnricher(),
            DiscordSourceEnricher(),
            MessagesSourceEnricher(),
        ]
    }

    func restore() {
        registry.replaceAll(with: saved)
    }
}
