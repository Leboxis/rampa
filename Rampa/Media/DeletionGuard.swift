import Foundation
import Photos

/// The safety rails between "I tapped delete" and "the asset is gone".
///
/// Rampa never deletes anything straight from a tap. An item must first enter
/// the trash, then survive a hold-to-confirm, then pass a biometric check,
/// and even then PhotoKit only moves it to *its own* Recently Deleted album,
/// where the system keeps it for 30 days. Four independent chances to change
/// your mind.
@MainActor
@Observable
final class DeletionGuard {

    /// Assets waiting in the trash. Ordered most-recently-added first so the
    /// trash reads like an undo stack.
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

    /// Adds items to the trash. Adding is always safe: nothing leaves the library.
    ///
    /// - Returns: the items that were not already staged, so the caller can
    ///   offer to undo exactly what this call changed.
    @discardableResult
    func stage(_ items: [MediaItem]) -> [MediaItem] {
        let known = Set(staged.map(\.id))
        var seen = known
        var fresh: [MediaItem] = []
        for item in items where !seen.contains(item.id) {
            seen.insert(item.id)
            fresh.append(item)
        }
        guard !fresh.isEmpty else { return [] }
        staged.insert(contentsOf: fresh, at: 0)
        return fresh
    }

    func unstage(_ ids: Set<MediaItem.ID>) {
        staged.removeAll { ids.contains($0.id) }
    }

    /// Puts back items that were just removed from the trash, keeping the order
    /// the caller had. Used by undo, which is why it restores the array rather
    /// than re-inserting items one by one — re-inserting at the front reverses
    /// a multi-item undo.
    func restore(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }
        let present = Set(staged.map(\.id))
        let missing = items.filter { !present.contains($0.id) }
        guard !missing.isEmpty else { return }
        staged.insert(contentsOf: missing, at: 0)
    }

    /// Restores the trash to an exact previous state. This is what "Annuler"
    /// after "Vider" needs: a verbatim array, not a merge.
    func restoreExact(_ items: [MediaItem]) {
        staged = items
    }

    func unstageAll() {
        staged.removeAll()
    }

    // MARK: Commit

    /// Deletes everything in the trash from the system library.
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
            errorMessage = "Certains éléments ont changé entre-temps. La corbeille a été rechargée."
            let surviving = Set(Self.existingIdentifiers(batch.map(\.id)))
            staged.removeAll { !surviving.contains($0.id) }
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

    /// One PhotoKit round-trip for the whole batch instead of one per asset,
    /// which is what the previous version did inside a `removeAll` predicate.
    private nonisolated static func existingIdentifiers(_ ids: [MediaItem.ID]) -> [MediaItem.ID] {
        let found = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var present: [MediaItem.ID] = []
        present.reserveCapacity(found.count)
        found.enumerateObjects { asset, _, _ in
            present.append(asset.localIdentifier)
        }
        return present
    }
}
