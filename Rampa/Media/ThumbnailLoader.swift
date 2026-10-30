import Photos
import SwiftUI
import UIKit

/// Caches downsampled images for the grid, the review deck and the viewer.
///
/// Two things matter here and both are about staying smooth at 120 Hz: every
/// image is downsampled to the exact size it will be drawn at (a full-resolution
/// 48 MP decode is over 200 MB), and the decode happens off the main actor.
/// `NSCache` drops the whole thing under memory pressure, which is the right
/// trade: re-decoding is cheaper than being jetsammed mid-scroll.
///
/// The class is `@MainActor` because it publishes to the UI, but the PhotoKit
/// work is handed to a `nonisolated` helper so no `PHAsset` ever crosses an
/// actor boundary.
@MainActor
final class ThumbnailLoader {

    static let shared = ThumbnailLoader()

    /// Which surface an image is for. Determines the decode size.
    enum Target: Hashable {
        /// Square grid cell.
        case grid
        /// The review deck and the full-screen viewer.
        case deck
    }

    private let cache = NSCache<NSString, UIImage>()

    /// One shared caching manager, kept alive: `startCachingImages` on a
    /// manager that is deallocated immediately does nothing at all, which is
    /// what made prefetching a no-op.
    private nonisolated static let prefetcher = PHCachingImageManager()

    private init() {
        cache.countLimit = 900
        cache.totalCostLimit = 120 * 1024 * 1024
    }

    /// Point size a target is drawn at. Kept in one place so the decode size and
    /// the layout size can never drift apart.
    nonisolated static func pointSize(for target: Target) -> CGSize {
        switch target {
        case .grid: CGSize(width: 160, height: 160)
        case .deck: CGSize(width: 1200, height: 1200)
        }
    }

    private func key(
        for id: String,
        target: Target,
        scale: CGFloat,
        fill: ThumbnailFill
    ) -> NSString {
        let size = Self.pointSize(for: target)
        let mode = fill == .fit ? "fit" : "fill"
        return "\(id)|\(Int(size.width))|\(Int(scale))|\(mode)" as NSString
    }

    /// Returns a cached image if present, without touching the network or disk.
    func cached(id: String, target: Target, scale: CGFloat, fill: ThumbnailFill = .fill) -> UIImage? {
        cache.object(forKey: key(for: id, target: target, scale: scale, fill: fill))
    }

    /// Loads and downsamples one image.
    ///
    /// - Parameter fill: `.fill` crops to the target's square; `.fit` keeps the
    ///   whole frame inside it. The viewer and the deck pass `.fit`, because a
    ///   cropped photo is the one thing they must not show.
    func image(
        for assetID: String,
        target: Target,
        scale: CGFloat,
        fill: ThumbnailFill = .fill
    ) async -> UIImage? {
        let cacheKey = key(for: assetID, target: target, scale: scale, fill: fill)
        if let hit = cache.object(forKey: cacheKey) { return hit }

        let pointSize = Self.pointSize(for: target)
        let pixel = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)

        guard let image = await Self.requestImage(
            assetID: assetID,
            pixelSize: pixel,
            contentMode: fill == .fit ? .aspectFit : .aspectFill
        ) else { return nil }

        store(image, forKey: cacheKey)
        return image
    }

    /// `NSCache` should budget against real bitmap bytes. The previous version
    /// multiplied by the *view's* scale, which over-charged every entry by up to
    /// 9× and evicted the cache constantly.
    private func store(_ image: UIImage, forKey key: NSString) {
        let pixelsWide = image.size.width * image.scale
        let pixelsHigh = image.size.height * image.scale
        let cost = Int(pixelsWide * pixelsHigh * 4)
        cache.setObject(image, forKey: key, cost: cost)
    }

    /// The PhotoKit call, isolated away from the main actor so the decode does
    /// not block scrolling.
    private nonisolated static func requestImage(
        assetID: String,
        pixelSize: CGSize,
        contentMode: PHImageContentMode
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

            // PhotoKit may call this handler more than once (a degraded image,
            // then the final one). Resuming a continuation twice traps, so the
            // first result wins and the rest are ignored.
            let hasResumed = ResumeFlag()

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: pixelSize,
                contentMode: contentMode,
                options: options
            ) { result, _ in
                guard hasResumed.claim() else { return }
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

            Self.prefetcher.startCachingImages(
                for: list,
                targetSize: pixel,
                contentMode: .aspectFill,
                options: options
            )
        }
    }
}
