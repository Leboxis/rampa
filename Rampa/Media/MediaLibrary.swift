import Foundation
import Photos

/// Everything the app knows about the user's photo library.
///
/// Reads are cached in a single `[MediaItem]` snapshot so filtering, grouping
/// and search all run on plain value types off the main actor. PhotoKit is
/// only consulted again when the library actually changes.
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
    ///
    /// The fetch runs on the main actor because PhotoKit's synchronous fetch is
    /// already fast for a metadata-only request; the expensive part (thumbnails)
    /// happens later, per cell, off the main thread.
    func reload() async {
        guard access == .granted || access == .limited else {
            items = []
            return
        }
        isLoading = items.isEmpty

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        // Trashed assets are excluded: PhotoKit keeps them in the library for
        // 30 days, and the app must never show them as if they were still here.
        options.includeTrashedAssets = false

        let result = PHAsset.fetchAssets(with: options)
        var snapshot: [MediaItem] = []
        snapshot.reserveCapacity(result.count)

        result.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            let kind: MediaKind = asset.mediaType == .video ? .video : .photo
            // Audio-only and unknown media are not photos or videos.
            guard asset.mediaType == .image || asset.mediaType == .video else { return }

            let screenCapture = asset.mediaSubtypes.contains(.photoScreenshot)
                || asset.mediaSubtypes.contains(.photoScreenRecording)

            snapshot.append(
                MediaItem(
                    id: asset.localIdentifier,
                    creationDate: date,
                    mediaType: kind,
                    duration: asset.duration,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    isFavorite: asset.isFavorite,
                    isScreenCapture: screenCapture
                )
            )
        }

        items = snapshot
        isLoading = false
        loadError = nil
    }

    /// Re-reads a single asset's state after a change, without refetching all.
    func remove(ids: Set<MediaItem.ID>) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
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

    deinit {
        if let changeObserver {
            PHPhotoLibrary.shared().unregisterChangeObserver(changeObserver)
        }
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
