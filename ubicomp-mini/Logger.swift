import Foundation
import os

final class CaptureLog {
    static let shared = CaptureLog()

    private let osLog = os.Logger(subsystem: "com.capture.app", category: "general")
    private let logDirectory: URL
    private var fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.capture.logger", qos: .utility)

    private let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private init() {
        logDirectory = DatabaseManager.appSupportURL.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let dayString = Self.dayFormatter.string(from: Date())
        let logFile = logDirectory.appendingPathComponent("capture-\(dayString).log")

        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFile)
        fileHandle?.seekToEndOfFile()

        rotateLogs()
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Public API

    static func info(_ message: String) {
        shared.log(level: .info, message: message)
    }

    static func warning(_ message: String) {
        shared.log(level: .warning, message: message)
    }

    static func error(_ message: String) {
        shared.log(level: .error, message: message)
    }

    // MARK: - Private

    private enum Level: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private func log(level: Level, message: String) {
        let timestamp = timestampFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] \(message)\n"

        switch level {
        case .info: osLog.info("\(message, privacy: .public)")
        case .warning: osLog.warning("\(message, privacy: .public)")
        case .error: osLog.error("\(message, privacy: .public)")
        }

        queue.async { [weak self] in
            if let data = line.data(using: .utf8) {
                self?.fileHandle?.write(data)
            }
        }
    }

    private func rotateLogs() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil) else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        for file in files where file.pathExtension == "log" {
            guard let attrs = try? fm.attributesOfItem(atPath: file.path),
                  let created = attrs[.creationDate] as? Date,
                  created < cutoff else { continue }
            try? fm.removeItem(at: file)
            osLog.info("Rotated old log: \(file.lastPathComponent, privacy: .public)")
        }
    }

    deinit {
        fileHandle?.closeFile()
    }
}
