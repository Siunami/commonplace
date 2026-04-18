import Foundation

final class DatabaseBackupManager {
    static let shared = DatabaseBackupManager()

    private let backupDir: URL
    private let sourceFile: URL
    private let maxBackups = 20
    private var timer: Timer?

    /// Resolve the app support URL directly (same logic as DatabaseManager)
    /// to avoid a circular dependency during initialization.
    private static let appSupportURL: URL = {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
         ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("com.dubberly.Capture", isDirectory: true)
    }()

    private init() {
        backupDir = Self.appSupportURL.appendingPathComponent("backups", isDirectory: true)
        sourceFile = Self.appSupportURL.appendingPathComponent("capture.sqlite")
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
    }

    /// Create a timestamped backup copy of the database.
    func backupNow(label: String = "auto") {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceFile.path) else { return }

        // Skip if file is empty/tiny (just schema, no real data)
        let fileSize = (try? fm.attributesOfItem(atPath: sourceFile.path)[.size] as? Int) ?? 0
        guard fileSize > 50_000 else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let backupFile = backupDir.appendingPathComponent("capture_\(label)_\(timestamp).sqlite")

        do {
            try fm.copyItem(at: sourceFile, to: backupFile)

            // Also copy WAL if it exists (contains uncommitted data)
            let walFile = URL(fileURLWithPath: sourceFile.path + "-wal")
            if fm.fileExists(atPath: walFile.path) {
                let walBackup = URL(fileURLWithPath: backupFile.path + "-wal")
                try fm.copyItem(at: walFile, to: walBackup)
            }

            CaptureLog.info("[Backup] Created: \(backupFile.lastPathComponent) (\(fileSize / 1024) KB)")
        } catch {
            CaptureLog.warning("[Backup] Failed: \(error.localizedDescription)")
        }

        pruneOldBackups()
    }

    /// Start the periodic backup timer (every 30 minutes).
    func startPeriodicBackups() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.backupNow()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pruneOldBackups() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sqliteFiles = contents
            .filter { $0.pathExtension == "sqlite" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return dateA > dateB // newest first
            }

        // Keep the newest maxBackups, delete the rest
        for file in sqliteFiles.dropFirst(maxBackups) {
            try? fm.removeItem(at: file)
            // Also remove associated WAL/SHM files
            try? fm.removeItem(at: URL(fileURLWithPath: file.path + "-wal"))
            try? fm.removeItem(at: URL(fileURLWithPath: file.path + "-shm"))
            CaptureLog.info("[Backup] Pruned old backup: \(file.lastPathComponent)")
        }
    }
}
