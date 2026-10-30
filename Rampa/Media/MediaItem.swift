import Foundation
import Photos

/// A lightweight, `Sendable` snapshot of one library asset.
///
/// `PHAsset` is not `Sendable` and is expensive to hand around, so the app
/// copies the handful of fields it actually renders into this value type once
/// per fetch. Everything downstream — sorting, filtering, grouping, the review
/// deck — works on these structs and never touches PhotoKit again.
struct MediaItem: Identifiable, Hashable, Sendable {
    /// `PHAsset.localIdentifier`. Stable across launches, unlike `UUID`.
    let id: String
    let creationDate: Date
    let mediaType: MediaKind
    /// Seconds. Zero for stills.
    let duration: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
    let isFavorite: Bool
    /// Screenshots and screen recordings carry a subtype bit in PhotoKit.
    let isScreenCapture: Bool

    var isVideo: Bool { mediaType == .video }

    /// Megapixels, used by the cleanup heuristics.
    var megapixels: Double {
        Double(pixelWidth * pixelHeight) / 1_000_000
    }

    /// Pixel dimensions, for the inspector line in the viewer.
    var resolutionText: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    /// Returns a copy with a different favourite flag. `MediaItem` is a value
    /// type, so a favourite change is one cheap map over the snapshot.
    func withFavorite(_ isFavorite: Bool) -> MediaItem {
        MediaItem(
            id: id,
            creationDate: creationDate,
            mediaType: mediaType,
            duration: duration,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            isFavorite: isFavorite,
            isScreenCapture: isScreenCapture
        )
    }
}

enum MediaKind: String, Sendable, CaseIterable {
    case photo
    case video

    var label: String {
        switch self {
        case .photo: "Photos"
        case .video: "Vidéos"
        }
    }

    var symbol: String {
        switch self {
        case .photo: "photo"
        case .video: "video"
        }
    }
}

// MARK: - Formatting

extension MediaItem {
    /// Human duration for videos, `nil` for stills.
    var durationText: String? {
        guard isVideo, duration > 0 else { return nil }
        let total = Int(duration.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
