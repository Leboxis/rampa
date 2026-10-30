import Foundation
import Photos

/// The safety rails between "I tapped delete" and "the asset is gone".
///
/// Rampa never deletes anything straight from a tap. An item must first enter
/// the staging bin, then survive a hold-to-confirm, then pass a biometric check,
/// and even then PhotoKit only moves it to *its own* Recently Deleted album,
/// where the system keeps it for 30 days. Four independent chances to change
/// your mind.
@MainActor
@Observable
final class DeletionGuard {

    /// Assets waiting in the bin. Ordered most-recently-added first so the bin
    /// reads like an undo stack.
    private(set) var staged: [MediaItem] = []

    /// Assets removed from the system library this session, kept so the user
    /// can see what happened and where it went.
    private(set) var lastRemoved: [MediaItem] = []

    private(set) var isWorking = false
    private(set) var errorMessage: String?

    // MARK: Staging

    func contains(_ id: MediaItem.ID) -> Bool {
        staged.contains { $0.id == id }
    }

    /// Adds items to the bin. Adding is always safe: nothing leaves the library.
    func stage(_ items: [MediaItem]) {
        let known = Set(staged.map(\.id))
        let fresh = items.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        staged.insert(contentsOf: fresh, at: 0)
    }

    func unstage(_ ids: Set<MediaItem.ID>) {
        staged.removeAll { ids.contains($0.id) }
    }

    func unstageAll() {
        staged.removeAll()
    }

    // MARK: Commit

    /// Deletes everything in the bin from the system library.
    ///
    /// PhotoKit moves the assets to the system's Recently Deleted album, so the
    /// user still has 30 days to recover them from Photos itself. This is the
    /// only place in the app that changes the library.
    ///
    /// - Returns: the ids that were actually removed, so the caller can keep
    ///   its own state in sync.
    @discardableResult
    func commit() async -> Set<MediaItem.ID> {
        guard !staged.isEmpty, !isWorking else { return [] }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let batch = staged
        let ids = Set(batch.map(\.id))

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: batch.map(\.id), options: nil)
        guard assets.count == batch.count else {
            // Something changed under us — a second device, or Photos already
            // cleared it. Reload rather than deleting a partial batch blind.
            errorMessage = "Certains éléments ont changé entre-temps. Le panier a été rechargé."
            staged.removeAll { item in
                PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil).count == 0
            }
            return []
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            lastRemoved = batch
            staged.removeAll()
            return ids
        } catch {
            errorMessage = "La suppression a échoué. Rien n'a été retiré de votre photothèque."
            return []
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
