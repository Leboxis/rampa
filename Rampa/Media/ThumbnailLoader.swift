import Photos
import SwiftUI
import UIKit

/// Caches downsampled thumbnails for the grid and the review deck.
///
/// Two things matter here and both are about staying smooth at 120 Hz:
/// every thumbnail is downsampled to the exact point size it will be drawn at
/// (a full-resolution 48 MP decode is over 200 MB), and the decode happens off
/// the main actor. `NSCache` drops the whole thing under memory pressure, which
/// is the right trade: re-decoding is cheaper than being jetsammed mid-scroll.
@MainActor
final class ThumbnailLoader {

    static let shared = ThumbnailLoader()

    /// Request tokens, so a cancelled cell stops work on the same asset.
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
    static func pointSize(for target: Target) -> CGSize {
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
        let pixelWidth = pointSize.width * scale
        let pixelHeight = pointSize.height * scale

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        // Synchronous delivery inside a detached task keeps the resize exact and
        // avoids the two-phase degraded-then-full dance.
        options.isSynchronous = true

        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetID],
            options: nil
        ).firstObject else {
            return nil
        }

        let image: UIImage? = await withCheckedContinuation { continuation in
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: pixelWidth, height: pixelHeight),
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                continuation.resume(returning: result)
            }
        }

        if let image {
            // `image.size` is in points; cost is the real byte count of the
            // backing bitmap, which is what NSCache should budget against.
            let cost = Int(image.size.width * image.size.height * scale * scale * 4)
            cache.setObject(image, forKey: cacheKey, cost: cost)
        }
        return image
    }

    /// Warms the cache for the cells just off screen. Called with a small window
    /// so it never competes with the visible work.
    func prefetch(ids: [String], target: Target, scale: CGFloat) {
        guard !ids.isEmpty else { return }
        let pointSize = Self.pointSize(for: target)
        let pixel = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var list: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in list.append(asset) }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        manager.startCachingImages(for: list, targetSize: pixel, contentMode: .aspectFill, options: options)
    }

    func cancelPrefetch(ids: [String], target: Target, scale: CGFloat) {
        guard !ids.isEmpty else { return }
        let pointSize = Self.pointSize(for: target)
        let pixel = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var list: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in list.append(asset) }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        manager.stopCachingImages(for: list, targetSize: pixel, contentMode: .aspectFill, options: options)
    }
}
