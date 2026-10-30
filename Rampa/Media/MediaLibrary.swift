import Foundation
import Photos

/// Everything the app knows about the user's photo library.
///
/// Reads are cached in a single `[MediaItem]` snapshot so filtering, grouping
/// and search all run on plain value types off the main actor. PhotoKit is
/// only consulted again when the library actually changes.
///
/// The PhotoKit fetch itself runs `nonisolated`: enumerating 20 000 assets on
/// the main actor at launch is a visible hitch, and none of the work needs the
/// main thread. Only the finished snapshot crosses back.
@MainActor
@Observable
final class MediaLibrary {

    enum Access: Equatable {
        case unknown
        case granted
        case limited
        case denied
    }

    private(set) var access: Access = .unknown
    private(set) var items: [MediaItem] = []
    private(set) var isLoading = false
    /// Set when a fetch fails so the UI can say something true instead of
    /// showing an empty library.
    private(set) var loadError: String?

    /// Bumped after every load and every PhotoKit change notification. Views
    /// derive from this instead of `.task(id: items.count)`, which misses any
    /// change that keeps the count the same.
    private(set) var revision = 0

    private var changeObserver: (any PHPhotoLibraryChangeObserver)?
    private var hasStarted = false

    /// Number of assets the user has chosen to share under limited access.
    var isLimited: Bool { access == .limited }

    // MARK: Authorisation

    /// Requests read access once. Safe to call from every screen's `.task`.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await requestAccess()
        await reload()
        observeChanges()
    }

    /// Re-reads the authorisation status.
    ///
    /// The first prompt is only ever shown once per install, so this is the
    /// path that matters afterwards: the user goes to Settings, grants access,
    /// comes back, and the library fills in instead of staying empty until the
    /// next launch.
    ///
    /// - Returns: `true` when access changed and a reload happened.
    @discardableResult
    func refreshAccess() async -> Bool {
        let before = access
        await requestAccess()
        guard access != before else { return false }
        await reload()
        return true
    }

    func requestAccess() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        access = Self.map(status)

        guard status == .notDetermined else { return }

        let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        access = Self.map(granted)
    }

    private static func map(_ status: PHAuthorizationStatus) -> Access {
        switch status {
        case .authorized: .granted
        case .limited: .limited
        case .denied, .restricted: .denied
        case .notDetermined: .unknown
        @unknown default: .denied
        }
    }

    // MARK: Fetching

    /// Rebuilds the snapshot from PhotoKit.
    func reload() async {
        guard access == .granted || access == .limited else {
            items = []
            revision += 1
            return
        }
        isLoading = items.isEmpty

        let snapshot = await Self.fetchSnapshot()

        items = snapshot
        isLoading = false
        loadError = nil
        revision += 1
    }

    /// The PhotoKit enumeration, off the main actor.
    ///
    /// Only plain values leave this function — no `PHAsset` is ever returned —
    /// so nothing has to be `Sendable` that is not already a value type.
    private nonisolated static func fetchSnapshot() async -> [MediaItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false

        let result = PHAsset.fetchAssets(with: options)
        var snapshot: [MediaItem] = []
        snapshot.reserveCapacity(result.count)

        result.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            // Audio-only and unknown media are not photos or videos.
            guard asset.mediaType == .image || asset.mediaType == .video else { return }

            snapshot.append(
                MediaItem(
                    id: asset.localIdentifier,
                    creationDate: date,
                    mediaType: asset.mediaType == .video ? .video : .photo,
                    duration: asset.duration,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    isFavorite: asset.isFavorite,
                    isScreenCapture: asset.mediaSubtypes.contains(.photoScreenshot)
                )
            )
        }

        return snapshot
    }

    /// Drops assets from the cached snapshot without refetching the library.
    func remove(ids: Set<MediaItem.ID>) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        revision += 1
    }

    /// Applies a favourite change locally, so the star responds to the tap
    /// instead of waiting for the PhotoKit change notification.
    func setFavorite(_ isFavorite: Bool, ids: Set<MediaItem.ID>) {
        guard !ids.isEmpty else { return }
        items = items.map { item in
            guard ids.contains(item.id), item.isFavorite != isFavorite else { return item }
            return item.withFavorite(isFavorite)
        }
        revision += 1
    }

    // MARK: Change observation

    private func observeChanges() {
        guard changeObserver == nil else { return }
        let observer = LibraryObserver { [weak self] in
            Task { @MainActor in
                await self?.reload()
            }
        }
        changeObserver = observer
        PHPhotoLibrary.shared().register(observer)
    }
}

/// Bridges PhotoKit's nonisolated change callback back to the main actor.
private final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}
