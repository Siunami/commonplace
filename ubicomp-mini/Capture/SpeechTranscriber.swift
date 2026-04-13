import Foundation
import Combine
import Speech
import AVFoundation

@MainActor
final class SpeechTranscriber: ObservableObject {

    enum PermissionStatus {
        case unknown, granted, denied, unavailable
    }

    @Published var transcribedText = ""
    @Published var isRecording = false
    @Published var audioLevels: [Float] = []
    @Published var isProcessing = false
    @Published private(set) var permissionStatus: PermissionStatus = .unknown

    private let speechRecognizer = SFSpeechRecognizer(locale: .current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var autoStopTimer: Timer?
    private var processingTimeout: Timer?
    private let maxLevelSamples = 50

    private static let maxDuration: TimeInterval = 60

    func requestPermissions() {
        guard speechRecognizer?.isAvailable == true else {
            permissionStatus = .unavailable
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch authStatus {
                case .authorized:
                    self.requestMicrophoneAccess()
                case .denied, .restricted:
                    self.permissionStatus = .denied
                default:
                    self.permissionStatus = .denied
                }
            }
        }
    }

    private func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.permissionStatus = granted ? .granted : .denied
            }
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard permissionStatus == .granted,
              let speechRecognizer, speechRecognizer.isAvailable else { return }

        recognitionTask?.cancel()
        recognitionTask = nil
        audioLevels.removeAll()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sumOfSquares: Float = 0
            for i in 0..<frameLength {
                let sample = channelData[i]
                sumOfSquares += sample * sample
            }
            let rms = sqrtf(sumOfSquares / Float(max(frameLength, 1)))
            let db = 20 * log10f(max(rms, 1e-7))
            let normalized = max(0, min(1, (db + 50) / 50))
            Task { @MainActor [weak self] in
                self?.appendAudioLevel(normalized)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
            recognitionRequest = nil
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcribedText = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finishProcessing()
                    }
                }
                if error != nil && self.isRecording {
                    self.stopRecording()
                }
            }
        }

        isRecording = true

        autoStopTimer = Timer.scheduledTimer(withTimeInterval: Self.maxDuration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopRecording()
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        autoStopTimer?.invalidate()
        autoStopTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        isRecording = false
        isProcessing = true

        processingTimeout = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finishProcessing()
            }
        }
    }

    private func finishProcessing() {
        processingTimeout?.invalidate()
        processingTimeout = nil
        isProcessing = false
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func appendAudioLevel(_ level: Float) {
        audioLevels.append(level)
        if audioLevels.count > maxLevelSamples {
            audioLevels.removeFirst(audioLevels.count - maxLevelSamples)
        }
    }

    deinit {
        // Only invalidate timers here (safe from any thread).
        // Audio cleanup (audioEngine.stop, removeTap, recognitionTask.cancel)
        // is handled by the explicit stopRecording() call from CopyToastController
        // BEFORE this object is released. Never rely on deinit for audio teardown
        // because deinit is nonisolated and races with the audio render thread.
        autoStopTimer?.invalidate()
        processingTimeout?.invalidate()
    }
}
