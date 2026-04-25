import AppKit

/// Everything an enricher is allowed to inspect at capture time. Pure value
/// type so enrichers can be unit-tested with fixture inputs.
struct RawCaptureInputs {
    let bundleId: String?
    let appName: String?
    let windowTitle: String?
    let pid: pid_t?
    let pasteboardTypes: [String]
    let pasteboardHTML: String?
    let pasteboardRTF: String?
    let pasteboardText: String?
}

/// A single row of provenance surfaced in the Source section of the detail
/// view. `key` is a stable identifier for dedup/downstream logic; `label`
/// and `value` are the user-facing strings.
struct SourceContextEntry: Codable, Equatable {
    let key: String
    let label: String
    let value: String
    let icon: String?
    let url: String?

    init(key: String, label: String, value: String, icon: String? = nil, url: String? = nil) {
        self.key = key
        self.label = label
        self.value = value
        self.icon = icon
        self.url = url
    }
}

/// Per-app enricher. Implementations must be pure functions of their input
/// (except for tightly-budgeted AppleScript / AX queries) so they can be
/// exercised from tests without a live capture.
protocol SourceEnricher {
    var supportedBundleIds: Set<String> { get }
    func enrich(_ inputs: RawCaptureInputs) -> [SourceContextEntry]
}

/// Dispatches raw capture inputs to the first enricher whose
/// `supportedBundleIds` contains the active bundle. The registry enforces a
/// hard 300 ms budget so a hanging enricher never blocks the capture path.
final class SourceEnricherRegistry {
    static let shared = SourceEnricherRegistry()

    private var enrichers: [SourceEnricher] = []
    /// Headroom above `BrowserURLExtractor`'s 0.5s AppleScript timeout so
    /// the enricher can surface a URL (or its cached fallback) instead of
    /// getting cut off mid-query when Chrome is slow to answer.
    private let budget: TimeInterval = 0.8

    private init() {}

    func register(_ enricher: SourceEnricher) {
        enrichers.append(enricher)
    }

    /// Replace the registered enricher list wholesale. Primarily used by
    /// tests; production startup should `register(_:)` each enricher once.
    func replaceAll(with enrichers: [SourceEnricher]) {
        self.enrichers = enrichers
    }

    func enrich(inputs: RawCaptureInputs) -> [SourceContextEntry] {
        guard let bundleId = inputs.bundleId,
              let enricher = enrichers.first(where: { $0.supportedBundleIds.contains(bundleId) }) else {
            return []
        }

        let deadline = Date().addingTimeInterval(budget)
        var result: [SourceContextEntry] = []
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            result = enricher.enrich(inputs)
            semaphore.signal()
        }

        let timeout = semaphore.wait(timeout: .now() + budget)
        if timeout == .timedOut {
            CaptureLog.warning("SourceEnricher exceeded \(Int(budget * 1000))ms budget for bundle \(inputs.bundleId ?? "nil")")
            return []
        }

        _ = deadline
        return result
    }
}
