import Photos
import SwiftUI
import UIKit

/// Caches downsampled thumbnails for the grid and the review deck.
///
/// Two things matter here and both are about staying smooth at 120 Hz: every
/// thumbnail is downsampled to the exact point size it will be drawn at (a
/// full-resolution 48 MP decode is over 200 MB), and the decode happens off the
/// main actor. `NSCache` drops the whole thing under memory pressure, which is
/// the right trade: re-decoding is cheaper than being jetsammed mid-scroll.
///
/// The class is `@MainActor` because it publishes to the UI, but the PhotoKit
/// work is handed to a `nonisolated` helper so no `PHAsset` ever crosses an
/// actor boundary.
@MainActor
final class ThumbnailLoader {

    static let shared = ThumbnailLoader()

    /// Which surface a thumbnail is for. Determines the decode size.
    enum Target {
        case grid
        case deck
        case strip
    }

    private let cache = NSCache<NSString, UIImage>()
    private let manager = PHCachingImageManager()

    private init() {
        cache.countLimit = 900
        cache.totalCostLimit = 120 * 1024 * 1024
    }

    /// Point size a target is drawn at. Kept in one place so the decode size and
    /// the layout size can never drift apart.
    nonisolated static func pointSize(for target: Target) -> CGSize {
        switch target {
        case .grid: CGSize(width: 160, height: 160)
        case .deck: CGSize(width: 900, height: 900)
        case .strip: CGSize(width: 88, height: 88)
        }
    }

    private func key(for id: String, target: Target, scale: CGFloat) -> NSString {
        let size = Self.pointSize(for: target)
        return "\(id)|\(Int(size.width))|\(Int(scale))" as NSString
    }

    /// Returns a cached thumbnail if present, without touching the network or disk.
    func cached(id: String, target: Target, scale: CGFloat) -> UIImage? {
        cache.object(forKey: key(for: id, target: target, scale: scale))
    }

    /// Loads and downsamples one thumbnail.
    func image(
        for assetID: String,
        target: Target,
        scale: CGFloat
    ) async -> UIImage? {
        let cacheKey = key(for: assetID, target: target, scale: scale)
        if let hit = cache.object(forKey: cacheKey) { return hit }

        let pointSize = Self.pointSize(for: target)
        let pixel = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)

        let image = await Self.requestImage(assetID: assetID, pixelSize: pixel)
        guard let image else { return nil }

        // `image.size` is in points; cost is the real byte count of the backing
        // bitmap, which is what NSCache should budget against.
        let cost = Int(image.size.width * image.size.height * scale * scale * 4)
        cache.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }

    /// The PhotoKit call, isolated away from the main actor so the decode does
    /// not block scrolling.
    private nonisolated static func requestImage(
        assetID: String,
        pixelSize: CGSize
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            // Synchronous delivery keeps the resize exact and avoids the
            // two-phase degraded-then-full dance.
            options.isSynchronous = true

            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            guard let asset = assets.firstObject else {
                continuation.resume(returning: nil)
                return
            }

            let manager = PHImageManager.default()
            manager.requestImage(
                for: asset,
                targetSize: pixelSize,
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                continuation.resume(returning: result)
            }
        }
    }

    /// Warms the cache for the cells just off screen, so a fast scroll does not
    /// outrun the decoder.
    func prefetch(ids: [String], target: Target, scale: CGFloat) {
        guard !ids.isEmpty else { return }
        let pointSize = Self.pointSize(for: target)
        let pixel = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)

        Task.detached(priority: .utility) {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var list: [PHAsset] = []
            list.reserveCapacity(assets.count)
            assets.enumerateObjects { asset, _, _ in list.append(asset) }
            guard !list.isEmpty else { return }

            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            PHCachingImageManager().startCachingImages(
                for: list,
                targetSize: pixel,
                contentMode: .aspectFill,
                options: options
            )
        }
    }
}
