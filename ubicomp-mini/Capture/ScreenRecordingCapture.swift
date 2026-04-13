import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class ScreenRecordingCapture: NSObject, @unchecked Sendable {
    static let shared = ScreenRecordingCapture()

    enum State: Sendable {
        case idle
        case recording
        case stopping
    }

    struct RecordingResult: Sendable {
        let filePath: String
        let thumbnailPath: String
        let duration: Double
        let fileSize: Int64
        let recordingId: Int64?
        let context: CaptureContext
        let captureType: String
        let regionRect: CGRect?   // screen-coordinate rect for region recordings
    }

    private(set) var state: State = .idle
    private(set) var elapsedSeconds: Double = 0

    /// The screen-coordinate rect being recorded (nil for full-screen)
    private(set) var activeRegionRect: CGRect?

    // Properties accessed from both main and background (stream output) queues.
    // All access MUST go through writerQueue to prevent data races.
    private let writerQueue = DispatchQueue(label: "com.dubberly.Capture.writerQueue")
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var startTime: CMTime?
    private var lastVideoTime: CMTime = .zero
    private var _state: State = .idle
    private var videoFrameCount: Int = 0

    // Must be retained for the lifetime of the stream
    private var streamOutputHandler: StreamOutputHandler?

    private var elapsedTimer: Timer?
    private var recordingStartDate: Date?
    private var captureContext: CaptureContext?
    private var captureType: String = "full"
    private var displayId: CGDirectDisplayID = CGMainDisplayID()
    private var hasAudio: Bool = false

    private let db = DatabaseManager.shared

    private static let maxDuration: TimeInterval = 600 // 10 minutes

    // MARK: - Recordings directory

    static let recordingsBaseURL: URL = {
        let url = DatabaseManager.appSupportURL.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    // MARK: - Formatters

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH-mm-ss"
        return f
    }()

    // MARK: - Public API

    func startFullScreen(displayID: CGDirectDisplayID, audio: Bool, excludedWindowIDs: [CGWindowID] = []) async throws {
        guard state == .idle else { return }
        if !CGPreflightScreenCaptureAccess() {
            // Try to prompt if macOS hasn't asked yet. If already decided, this
            // is a no-op and preflight will still be false on the next line.
            CGRequestScreenCaptureAccess()
            if !CGPreflightScreenCaptureAccess() {
                CaptureLog.warning("No screen recording permission for recording")
                throw NSError(domain: "ScreenRecordingCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Screen recording permission required. Enable in System Settings → Privacy & Security → Screen & System Audio Recording."])
            }
        }

        self.captureContext = CaptureContext.current()
        self.captureType = "full"
        self.displayId = displayID
        self.hasAudio = audio
        self.activeRegionRect = nil

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first else {
            throw NSError(domain: "ScreenRecordingCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }

        let excludedWindows = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        try await startStream(filter: filter, width: display.width, height: display.height, audio: audio)
    }

    func startRegion(rect: CGRect, on screen: NSScreen, audio: Bool, excludedWindowIDs: [CGWindowID] = []) async throws {
        guard state == .idle else { return }
        if !CGPreflightScreenCaptureAccess() {
            // Try to prompt if macOS hasn't asked yet. If already decided, this
            // is a no-op and preflight will still be false on the next line.
            CGRequestScreenCaptureAccess()
            if !CGPreflightScreenCaptureAccess() {
                CaptureLog.warning("No screen recording permission for recording")
                throw NSError(domain: "ScreenRecordingCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Screen recording permission required. Enable in System Settings → Privacy & Security → Screen & System Audio Recording."])
            }
        }

        self.captureContext = CaptureContext.current()
        self.captureType = "region"
        self.hasAudio = audio
        self.activeRegionRect = rect

        let displayID: CGDirectDisplayID
        if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            displayID = id
        } else {
            displayID = CGMainDisplayID()
        }
        self.displayId = displayID

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first else {
            throw NSError(domain: "ScreenRecordingCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }

        // Convert from AppKit screen coordinates (origin bottom-left) to
        // ScreenCaptureKit display-local coordinates (origin top-left).
        let screenFrame = screen.frame
        let localX = rect.origin.x - screenFrame.origin.x
        let localY = screenFrame.height - (rect.origin.y - screenFrame.origin.y) - rect.height
        let sourceRect = CGRect(x: localX, y: localY, width: rect.width, height: rect.height)

        let excludedWindows = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = Int(rect.width * screen.backingScaleFactor)
        config.height = Int(rect.height * screen.backingScaleFactor)
        config.scalesToFit = true
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        if audio {
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
            if #available(macOS 15.0, *) {
                config.captureMicrophone = true
            }
        }

        try await startStreamWithConfig(filter: filter, config: config, audio: audio)
    }

    func stopRecording() async -> RecordingResult? {
        guard state == .recording else { return nil }
        state = .stopping

        let frameCount = writerQueue.sync { videoFrameCount }
        CaptureLog.info("[ScreenRecordingCapture] Stopping recording (\(frameCount) frames captured)")

        elapsedTimer?.invalidate()
        elapsedTimer = nil

        // 1. Stop the stream first so no more samples arrive
        if let stream = self.stream {
            try? await stream.stopCapture()
        }
        self.stream = nil
        self.streamOutputHandler = nil

        // 2. Mark inputs finished and grab the writer — all on writerQueue to
        //    prevent data races with handleSampleBuffer
        let writer: AVAssetWriter? = writerQueue.sync {
            _state = .stopping
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            micInput?.markAsFinished()
            return assetWriter
        }

        guard let writer, writer.status == .writing else {
            let status = writer?.status
            CaptureLog.error("[ScreenRecordingCapture] Writer not in writing state: \(String(describing: status))")
            writerQueue.sync {
                assetWriter = nil; videoInput = nil; audioInput = nil; micInput = nil
                startTime = nil; lastVideoTime = .zero; _state = .idle
            }
            state = .idle
            return nil
        }

        // 3. Finalize — this flushes the moov atom
        await writer.finishWriting()

        if writer.status == .failed {
            CaptureLog.error("[ScreenRecordingCapture] Writer finishWriting failed: \(writer.error?.localizedDescription ?? "unknown")")
        }

        let outputURL = writer.outputURL
        let filePath = outputURL.path
        let duration = elapsedSeconds
        let context = captureContext ?? CaptureContext.current()
        let regionRect = activeRegionRect
        let type = captureType

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: filePath))?[.size] as? Int64 ?? 0

        // Only save if the file is valid (has actual content)
        guard writer.status == .completed, fileSize > 1000 else {
            CaptureLog.error("[ScreenRecordingCapture] Recording file invalid (status=\(writer.status.rawValue), size=\(fileSize)), discarding")
            try? FileManager.default.removeItem(atPath: filePath)
            writerQueue.sync {
                assetWriter = nil; videoInput = nil; audioInput = nil; micInput = nil
                startTime = nil; lastVideoTime = .zero; _state = .idle
            }
            elapsedSeconds = 0; recordingStartDate = nil; captureContext = nil
            activeRegionRect = nil; state = .idle
            return nil
        }

        let thumbnailPath = generateThumbnail(from: outputURL)

        let dayString = Self.dayFormatter.string(from: recordingStartDate ?? Date())
        var record = RecordingRecord(
            timestamp: (recordingStartDate ?? Date()).timeIntervalSince1970,
            dayString: dayString,
            filePath: filePath,
            thumbnailPath: thumbnailPath,
            fileSize: fileSize,
            duration: duration,
            displayId: String(displayId),
            captureType: type,
            hasAudio: hasAudio,
            windowTitle: context.windowTitle,
            bundleId: context.bundleId
        )
        db.insertRecording(&record)

        CaptureLog.info("[ScreenRecordingCapture] Recording saved: \(filePath), duration: \(String(format: "%.1f", duration))s, size: \(fileSize / 1024)KB")

        // Reset shared state through the writer queue
        writerQueue.sync {
            assetWriter = nil
            videoInput = nil
            audioInput = nil
            micInput = nil
            startTime = nil
            lastVideoTime = .zero
            _state = .idle
        }
        elapsedSeconds = 0
        recordingStartDate = nil
        captureContext = nil
        activeRegionRect = nil
        state = .idle

        return RecordingResult(
            filePath: filePath,
            thumbnailPath: thumbnailPath,
            duration: duration,
            fileSize: fileSize,
            recordingId: record.id,
            context: context,
            captureType: type,
            regionRect: regionRect
        )
    }

    func forceFinalize() {
        guard state == .recording || state == .stopping else { return }
        CaptureLog.info("[ScreenRecordingCapture] Force finalizing recording")

        elapsedTimer?.invalidate()
        elapsedTimer = nil

        stream?.stopCapture { _ in }
        stream = nil
        streamOutputHandler = nil

        // Grab the writer and mark inputs finished on the writer queue
        let writer: AVAssetWriter? = writerQueue.sync {
            _state = .stopping
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            micInput?.markAsFinished()
            return assetWriter
        }

        // finishWriting must complete before we nil things out
        if let writer, writer.status == .writing {
            writer.finishWriting { [weak self] in
                self?.writerQueue.sync {
                    self?.assetWriter = nil
                    self?.videoInput = nil
                    self?.audioInput = nil
                    self?.micInput = nil
                    self?.startTime = nil
                    self?._state = .idle
                }
            }
        } else {
            writerQueue.sync {
                assetWriter = nil
                videoInput = nil
                audioInput = nil
                micInput = nil
                startTime = nil
                _state = .idle
            }
        }
        activeRegionRect = nil
        state = .idle
    }

    // MARK: - Private

    private func startStream(filter: SCContentFilter, width: Int, height: Int, audio: Bool) async throws {
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        if audio {
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
            if #available(macOS 15.0, *) {
                config.captureMicrophone = true
            }
        }

        try await startStreamWithConfig(filter: filter, config: config, audio: audio)
    }

    private func startStreamWithConfig(filter: SCContentFilter, config: SCStreamConfiguration, audio: Bool) async throws {
        let now = Date()
        let dayString = Self.dayFormatter.string(from: now)
        let timeString = Self.timeFormatter.string(from: now)

        let recordingDir = Self.recordingsBaseURL.appendingPathComponent(dayString)
        try FileManager.default.createDirectory(at: recordingDir, withIntermediateDirectories: true)

        let outputURL = recordingDir.appendingPathComponent("\(timeString).mov")

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: config.width * config.height * 4,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ]
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        writer.add(vInput)
        self.videoInput = vInput

        if audio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000,
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            writer.add(aInput)
            self.audioInput = aInput

            let micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            micInput.expectsMediaDataInRealTime = true
            writer.add(micInput)
            self.micInput = micInput
        }

        // Set up writer state through the synchronized queue
        writerQueue.sync {
            self.assetWriter = writer
            self.startTime = nil
            self.lastVideoTime = .zero
            self.videoFrameCount = 0
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Retain the output handler for the stream's lifetime
        let handler = StreamOutputHandler(capture: self)
        self.streamOutputHandler = handler

        let scStream = SCStream(filter: filter, configuration: config, delegate: handler)
        try scStream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.dubberly.Capture.videoQueue"))
        if audio {
            try scStream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.dubberly.Capture.audioQueue"))
            if #available(macOS 15.0, *) {
                do {
                    try scStream.addStreamOutput(handler, type: .microphone, sampleHandlerQueue: DispatchQueue(label: "com.dubberly.Capture.micQueue"))
                } catch {
                    CaptureLog.warning("[ScreenRecordingCapture] Microphone stream output unavailable: \(error.localizedDescription)")
                }
            }
        }
        try await scStream.startCapture()

        self.stream = scStream
        self.state = .recording
        writerQueue.sync { self._state = .recording }
        self.recordingStartDate = now
        self.elapsedSeconds = 0

        self.elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.state == .recording else { return }
            self.elapsedSeconds += 1.0
            NotificationCenter.default.post(name: .recordingElapsedTick, object: nil)

            if self.elapsedSeconds >= Self.maxDuration {
                Task {
                    let result = await self.stopRecording()
                    if let result {
                        HighlightCapture.shared.captureFromRecording(result: result)
                    }
                }
            }
        }

        CaptureLog.info("[ScreenRecordingCapture] Recording started: \(outputURL.path)")
    }

    private func generateThumbnail(from videoURL: URL) -> String {
        let thumbnailURL = videoURL.deletingPathExtension().appendingPathExtension("thumb.jpg")
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)

        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            guard let dest = CGImageDestinationCreateWithURL(
                thumbnailURL as CFURL,
                UTType.jpeg.identifier as CFString, 1, nil
            ) else { return thumbnailURL.path }
            CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
            CGImageDestinationFinalize(dest)
        } catch {
            CaptureLog.error("[ScreenRecordingCapture] Thumbnail generation failed: \(error.localizedDescription)")
        }

        return thumbnailURL.path
    }

    // Called from background stream output queue
    fileprivate func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        writerQueue.sync {
            guard _state == .recording,
                  let writer = assetWriter,
                  writer.status == .writing,
                  sampleBuffer.isValid else { return }

            switch type {
            case .screen:
                guard let videoInput, videoInput.isReadyForMoreMediaData else { return }

                // Skip status-only frames (e.g. idle/blank notifications from SCStream)
                guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                      let statusRaw = attachments.first?[.status] as? Int,
                      let status = SCFrameStatus(rawValue: statusRaw),
                      status == .complete else {
                    return
                }

                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if startTime == nil {
                    startTime = timestamp
                }
                let relativeTime = CMTimeSubtract(timestamp, startTime!)

                if let adjustedBuffer = adjustTimestamp(sampleBuffer, to: relativeTime) {
                    videoInput.append(adjustedBuffer)
                    lastVideoTime = relativeTime
                    videoFrameCount += 1
                    if videoFrameCount == 1 {
                        CaptureLog.info("[ScreenRecordingCapture] First video frame received")
                    }
                }

            case .audio:
                guard let audioInput, audioInput.isReadyForMoreMediaData else { return }

                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                guard let start = startTime else { return }
                let relativeTime = CMTimeSubtract(timestamp, start)

                if let adjustedBuffer = adjustTimestamp(sampleBuffer, to: relativeTime) {
                    audioInput.append(adjustedBuffer)
                }

            default:
                if #available(macOS 15.0, *), type == .microphone {
                    guard let micInput, micInput.isReadyForMoreMediaData else { return }

                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    guard let start = startTime else { return }
                    let relativeTime = CMTimeSubtract(timestamp, start)

                    if let adjustedBuffer = adjustTimestamp(sampleBuffer, to: relativeTime) {
                        micInput.append(adjustedBuffer)
                    }
                }
                break
            }
        }
    }

    fileprivate func handleStreamError(_ error: Error) {
        CaptureLog.error("[ScreenRecordingCapture] Stream stopped with error: \(error.localizedDescription)")
        if _state == .recording {
            Task { @MainActor in
                _ = await self.stopRecording()
            }
        }
    }

    private func adjustTimestamp(_ buffer: CMSampleBuffer, to newTime: CMTime) -> CMSampleBuffer? {
        var timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(buffer),
            presentationTimeStamp: newTime,
            decodeTimeStamp: .invalid
        )
        var newBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: buffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &newBuffer
        )
        return newBuffer
    }
}

// MARK: - Stream Output Handler (runs on background queues)

private class StreamOutputHandler: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private weak var capture: ScreenRecordingCapture?

    init(capture: ScreenRecordingCapture) {
        self.capture = capture
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        capture?.handleSampleBuffer(sampleBuffer, of: type)
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        capture?.handleStreamError(error)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let recordingElapsedTick = Notification.Name("recordingElapsedTick")
    static let recordingDidStop = Notification.Name("recordingDidStop")
}
