import AVFoundation
import Foundation
import Photos

/// The few things the app is allowed to ask PhotoKit to do to a single asset.
///
/// Every function here is deliberately tiny and `nonisolated`: it takes plain
/// `MediaItem.ID` values (which are `PHAsset.localIdentifier` strings), fetches
/// the assets, performs one change, and returns. No `PHAsset` crosses an actor
/// boundary and no view ever holds one.
enum MediaActions {

    // MARK: Favourites

    /// Sets the favourite flag on a set of assets.
    ///
    /// - Returns: `true` when PhotoKit accepted the change.
    @discardableResult
    static func setFavorite(_ isFavorite: Bool, ids: Set<MediaItem.ID>) async -> Bool {
        guard !ids.isEmpty else { return false }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)

        do {
            try await PHPhotoLibrary.shared().performChanges {
                assets.enumerateObjects { asset, _, _ in
                    PHAssetChangeRequest(for: asset).isFavorite = isFavorite
                }
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: Playback

    /// Builds a player for one video asset.
    static func makePlayer(for id: MediaItem.ID) async -> AVPlayer? {
        await withCheckedContinuation { continuation in
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            guard let asset = assets.firstObject else {
                continuation.resume(returning: nil)
                return
            }

            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic

            // PhotoKit calls this handler exactly once for video, but the flag
            // keeps the continuation safe if that ever changes.
            let hasResumed = ResumeFlag()

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard hasResumed.claim() else { return }
                guard let avAsset else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: AVPlayer(playerItem: AVPlayerItem(asset: avAsset)))
            }
        }
    }

    // MARK: Metadata

    /// Everything the inspector panel shows. PhotoKit exposes no content,
    /// caption or place text to third-party apps, so the inspector is honest
    /// about what it can and cannot know.
    struct Metadata: Sendable {
        let creationDate: Date
        let pixelWidth: Int
        let pixelHeight: Int
        let isVideo: Bool
        let duration: TimeInterval
        let isFavorite: Bool
        let isScreenCapture: Bool
        /// Byte size on disk, when PhotoKit will tell us.
        let byteCount: Int64?

        var byteText: String? {
            guard let byteCount, byteCount > 0 else { return nil }
            return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        }

        var kindText: String {
            if isVideo { return "Vidéo" }
            if isScreenCapture { return "Capture d'écran" }
            return "Photo"
        }

        var durationText: String? {
            guard isVideo, duration > 0 else { return nil }
            let total = Int(duration.rounded())
            return String(format: "%d:%02d", total / 60, total % 60)
        }
    }

    /// Reads the on-disk size and exact dimensions for one asset.
    static func metadata(for id: MediaItem.ID) async -> Metadata? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assets.firstObject else { return nil }

        return Metadata(
            creationDate: asset.creationDate ?? .distantPast,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            isVideo: asset.mediaType == .video,
            duration: asset.duration,
            isFavorite: asset.isFavorite,
            isScreenCapture: asset.mediaSubtypes.contains(.photoScreenshot),
            byteCount: byteCount(of: asset)
        )
    }

    /// The size of the original resource.
    ///
    /// PhotoKit has no public byte-size API, so this reads the undocumented
    /// `fileSize` key — but only after checking the resource actually responds
    /// to it, because key-value coding on an unknown key raises an Objective-C
    /// exception, which Swift cannot catch and which would crash the viewer.
    private static func byteCount(of asset: PHAsset) -> Int64? {
        let selector = NSSelectorFromString("fileSize")
        let sizes: [Int64] = PHAssetResource.assetResources(for: asset).compactMap { resource in
            guard resource.responds(to: selector),
                  let number = resource.value(forKey: "fileSize") as? NSNumber
            else { return nil }
            return number.int64Value
        }
        guard let largest = sizes.max(), largest > 0 else { return nil }
        return largest
    }
}

/// A one-shot flag shared between a continuation and a callback that may fire
/// more than once.
final class ResumeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
