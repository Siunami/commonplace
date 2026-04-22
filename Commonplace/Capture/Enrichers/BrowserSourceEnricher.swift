import Foundation

/// Wraps the existing `BrowserURLExtractor` facade so browser captures flow
/// through the same enricher registry as chat apps. Emits a single
/// `page_url` row; `CardDetailView` skips it because `EmbeddedLinkPreview`
/// already renders the URL in its own section.
final class BrowserSourceEnricher: SourceEnricher {
    let supportedBundleIds: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser", // Arc
    ]

    func enrich(_ inputs: RawCaptureInputs) -> [SourceContextEntry] {
        guard let bundleId = inputs.bundleId,
              let url = BrowserURLExtractor.shared.extractURL(bundleId: bundleId),
              !url.isEmpty else { return [] }

        let host = URL(string: url)?.host ?? url
        let display = (inputs.windowTitle?.isEmpty == false) ? inputs.windowTitle! : host

        return [
            SourceContextEntry(
                key: "page_url",
                label: "Page",
                value: display,
                icon: "globe",
                url: url
            )
        ]
    }
}
