import AppKit

/// Polls the active browser tab every few seconds and records page visits
/// with duration tracking. Non-browser apps close the active visit.
final class BrowsingTimelineService {
    static let shared = BrowsingTimelineService()

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 3.0
    private let db = DatabaseManager.shared

    /// The currently open (unfinished) visit, if any.
    private var activeVisitId: Int64?
    private var activeURL: String?

    /// Minimum visit duration to persist (filters transient navigations).
    private let minimumDuration: TimeInterval = 2.0

    func start() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        CaptureLog.info("[BrowsingTimeline] Started polling every \(pollInterval)s")
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        closeActiveVisit()
        CaptureLog.info("[BrowsingTimeline] Stopped")
    }

    // MARK: - Polling

    private func poll() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else {
            closeActiveVisit()
            return
        }

        // Only track known browsers
        guard let url = BrowserURLExtractor.shared.extractURL(bundleId: bundleId),
              !url.isEmpty else {
            closeActiveVisit()
            return
        }

        // Same URL as last poll — visit continues, nothing to do
        if url == activeURL { return }

        // URL changed — close the previous visit and open a new one
        closeActiveVisit()
        openVisit(url: url, app: frontApp.localizedName, bundleId: bundleId)
    }

    // MARK: - Visit Lifecycle

    private func openVisit(url: String, app: String?, bundleId: String) {
        let now = Date().timeIntervalSince1970
        let title = CaptureContext.activeWindowTitlePublic()
        let domain = PageVisit.extractDomain(from: url)

        var visit = PageVisit(
            url: url,
            title: title,
            domain: domain,
            sourceApp: app,
            bundleId: bundleId,
            startedAt: now,
            endedAt: nil,
            duration: nil,
            isBookmarked: false,
            captureCount: 0
        )
        db.insertPageVisit(&visit)

        activeVisitId = visit.id
        activeURL = url
    }

    private func closeActiveVisit() {
        guard let visitId = activeVisitId else { return }
        let now = Date().timeIntervalSince1970

        db.closePageVisit(id: visitId, at: now)

        activeVisitId = nil
        activeURL = nil
    }
}
