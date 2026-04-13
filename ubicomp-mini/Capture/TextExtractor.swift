import Foundation
import Vision
import AppKit

final class TextExtractor {
    static let shared = TextExtractor()

    private static let uiTerms: Set<String> = [
        "file", "edit", "view", "window", "help", "finder", "dock",
        "menu", "close", "minimize", "zoom", "quit", "hide",
        "back", "forward", "reload", "stop", "home", "share",
        "copy", "paste", "undo", "redo", "select", "delete",
    ]

    func extract(from cgImage: CGImage) async -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("[TextExtractor] OCR failed: \(error.localizedDescription)")
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else {
            return nil
        }

        let filtered = observations.filter { obs in
            if obs.boundingBox.minY > 0.93 { return false }
            if obs.boundingBox.maxY < 0.05 { return false }
            guard let text = obs.topCandidates(1).first?.string else { return false }
            if text.count < 4 { return false }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.contains(" ") && Self.uiTerms.contains(trimmed.lowercased()) {
                return false
            }
            return true
        }

        let text = filtered
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return text
    }
}
