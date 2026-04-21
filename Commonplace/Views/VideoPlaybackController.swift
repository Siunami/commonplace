import Foundation
import AVFoundation
import Combine

/// Shared controller for the two video players (StableVideoPlayer /
/// InlineVideoPlayer). A `VideoPlaybackController` is owned by a parent
/// view (currently CardDetailView) and passed into the player; the player
/// attaches its AVPlayer via `attach(_:)` and publishes `currentTime` via
/// a periodic time observer. The parent can call `seek(to:)` to jump the
/// player — used for timestamped notes on video highlights.
@MainActor
final class VideoPlaybackController: ObservableObject {
    @Published private(set) var currentTime: Double = 0
    private weak var player: AVPlayer?

    func attach(_ player: AVPlayer) {
        self.player = player
        currentTime = player.currentTime().seconds
    }

    func updateCurrentTime(_ seconds: Double) {
        guard seconds.isFinite else { return }
        currentTime = max(0, seconds)
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in
                player.play()
            }
        }
    }
}

/// Human-readable "M:SS" or "H:MM:SS" formatting for a duration in seconds.
enum VideoTimestampFormatter {
    static func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
