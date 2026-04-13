import Foundation
import GRDB

/// Periodically imports Chrome's browsing history and bookmarks into the page_visit table.
/// History is read from a copy of Chrome's SQLite database (to avoid lock conflicts).
/// Bookmarks are read from Chrome's JSON bookmarks file.
final class ChromeHistoryImporter {
    static let shared = ChromeHistoryImporter()

    private var importTimer: Timer?
    private var bookmarkTimer: Timer?
    private let db = DatabaseManager.shared

    /// Last imported Chrome timestamp (microseconds since Jan 1, 1601).
    /// Persisted across app launches via UserDefaults.
    private var lastImportedChromeTimestamp: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: "chromeHistoryLastImport")) }
        set { UserDefaults.standard.set(Int(newValue), forKey: "chromeHistoryLastImport") }
    }

    /// Chrome epoch offset: microseconds between Jan 1, 1601 and Jan 1, 1970.
    private static let chromeEpochOffset: Int64 = 11644473600 * 1_000_000

    private static let chromeHistoryURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default/History")
    }()

    private static let chromeBookmarksURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default/Bookmarks")
    }()

    func start() {
        // Import history on launch
        importHistory()
        syncBookmarks()

        // Then every 5 minutes
        importTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.importHistory()
        }
        // Bookmarks every 30 minutes
        bookmarkTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.syncBookmarks()
        }

        CaptureLog.info("[ChromeImporter] Started — history every 5min, bookmarks every 30min")
    }

    func stop() {
        importTimer?.invalidate()
        importTimer = nil
        bookmarkTimer?.invalidate()
        bookmarkTimer = nil
    }

    // MARK: - History Import

    private func importHistory() {
        let sourceURL = Self.chromeHistoryURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            CaptureLog.info("[ChromeImporter] Chrome history not found — skipping")
            return
        }

        // Copy the DB to a temp file to avoid lock conflicts
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chrome_history_\(UUID().uuidString).sqlite")

        do {
            try FileManager.default.copyItem(at: sourceURL, to: tempURL)
        } catch {
            CaptureLog.info("[ChromeImporter] Could not copy Chrome history (likely locked): \(error.localizedDescription)")
            return
        }

        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            let chromeDB = try DatabaseQueue(path: tempURL.path)
            let rows = try chromeDB.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT u.url, u.title, v.visit_time
                    FROM urls u JOIN visits v ON u.id = v.url
                    WHERE v.visit_time > ?
                    ORDER BY v.visit_time ASC
                    LIMIT 1000
                    """, arguments: [lastImportedChromeTimestamp])
            }

            var imported = 0
            var maxTimestamp = lastImportedChromeTimestamp

            for row in rows {
                guard let url: String = row["url"],
                      let chromeTimestamp: Int64 = row["visit_time"] else { continue }

                let title: String? = row["title"]
                let unixTimestamp = Double(chromeTimestamp - Self.chromeEpochOffset) / 1_000_000.0

                // Skip if we already have this visit from AppleScript polling
                if db.pageVisitExists(url: url, nearTimestamp: unixTimestamp, tolerance: 10.0) {
                    if chromeTimestamp > maxTimestamp { maxTimestamp = chromeTimestamp }
                    continue
                }

                let domain = PageVisit.extractDomain(from: url)
                var visit = PageVisit(
                    url: url,
                    title: title,
                    domain: domain,
                    sourceApp: "Google Chrome",
                    bundleId: "com.google.Chrome",
                    startedAt: unixTimestamp,
                    endedAt: unixTimestamp,
                    duration: 0,
                    isBookmarked: false,
                    captureCount: 0
                )
                db.insertPageVisit(&visit)
                imported += 1

                if chromeTimestamp > maxTimestamp { maxTimestamp = chromeTimestamp }
            }

            if maxTimestamp > lastImportedChromeTimestamp {
                lastImportedChromeTimestamp = maxTimestamp
            }

            if imported > 0 {
                CaptureLog.info("[ChromeImporter] Imported \(imported) new history entries")
            }
        } catch {
            CaptureLog.error("[ChromeImporter] Failed to read Chrome history: \(error.localizedDescription)")
        }
    }

    // MARK: - Bookmarks Sync

    private func syncBookmarks() {
        let bookmarksURL = Self.chromeBookmarksURL
        guard FileManager.default.fileExists(atPath: bookmarksURL.path) else { return }

        guard let data = try? Data(contentsOf: bookmarksURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any] else { return }

        var bookmarkURLs = Set<String>()
        for (_, value) in roots {
            if let folder = value as? [String: Any] {
                collectBookmarkURLs(from: folder, into: &bookmarkURLs)
            }
        }

        if !bookmarkURLs.isEmpty {
            db.markBookmarkedURLs(bookmarkURLs)
            CaptureLog.info("[ChromeImporter] Synced \(bookmarkURLs.count) bookmarks")
        }
    }

    private func collectBookmarkURLs(from node: [String: Any], into urls: inout Set<String>) {
        if let url = node["url"] as? String {
            urls.insert(url)
        }
        if let children = node["children"] as? [[String: Any]] {
            for child in children {
                collectBookmarkURLs(from: child, into: &urls)
            }
        }
    }
}
