import SwiftUI

/// One shared, app-wide state for what the user is looking at and what they
/// have staged. Passed through the environment so the five tabs agree without
/// prop-drilling a dozen bindings.
///
/// Selection is **per tab**. Sharing one `Set` meant switching from the library
/// to the bin with twelve photos ticked left a selection bar hanging over a
/// screen whose items had nothing to do with it.
@MainActor
@Observable
final class AppState {
    var library = MediaLibrary()
    var bin = DeletionGuard()

    /// Sections of the library screen, derived off the view body.
    var grouping: Grouping = .month
    var sort: SortOrder = .newest

    /// Tab the bar is currently showing.
    var tab: AppTab = .library

    // MARK: Selection

    /// Assets the user has ticked, per screen.
    var selection: [AppTab: Set<MediaItem.ID>] = [:]

    /// Screens currently in multi-select mode. Ticking the first item enters
    /// it, leaving it with nothing ticked or pressing Terminé exits.
    ///
    /// Spelled `Set<AppTab>()`, not `[:]`: the empty-dictionary literal is not
    /// a `Set` literal, and the macro expansion of `@Observable` rejects it.
    var selecting = Set<AppTab>()

    /// The asset shown full-screen, if any.
    var viewerItem: MediaItem?

    /// Bumped on every `openViewer`, so tapping the *same* photo twice opens
    /// the viewer both times. `fullScreenCover(item:)` keys on identity, and a
    /// `MediaItem.ID` that has not changed would otherwise be treated as "still
    /// presented" and silently ignored.
    var viewerToken = 0

    /// Something that just happened, with a way to take it back.
    var undo: UndoAction?

    /// Cleanup groups, computed once per library load.
    var cleanupGroups: [CleanupGroup] = []

    // MARK: Undo

    struct UndoAction: Identifiable {
        let id = UUID()
        let message: String
        let restore: () -> Void
    }

    // MARK: Derived

    var stagedCount: Int { bin.staged.count }

    var totalItems: Int { library.items.count }

    /// Items still available to browse — the library minus anything already
    /// staged, so the same asset never appears in two places at once.
    ///
    /// Computed, not stored: the library can change under us (a PhotoKit
    /// notification, a deletion) and a cached copy would go stale.
    var browsableItems: [MediaItem] {
        let staged = Set(bin.staged.map(\.id))
        guard !staged.isEmpty else { return library.items }
        return library.items.filter { !staged.contains($0.id) }
    }

    /// How many assets are browsable, without building the array.
    ///
    /// The library header shows this number, so it runs on every pass through
    /// `body` — and `browsableItems` allocates a whole filtered copy. Counting
    /// is the same O(n) without the allocation.
    var browsableCount: Int {
        let staged = Set(bin.staged.map(\.id))
        guard !staged.isEmpty else { return library.items.count }
        return library.items.count(where: { !staged.contains($0.id) })
    }

    // MARK: Selection API

    func isSelecting(_ tab: AppTab) -> Bool {
        selecting.contains(tab)
    }

    func isSelected(_ id: MediaItem.ID, in tab: AppTab) -> Bool {
        selection[tab]?.contains(id) ?? false
    }

    func selectedCount(in tab: AppTab) -> Int {
        selection[tab]?.count ?? 0
    }

    /// The selected items of a screen, resolved against a list the screen owns.
    /// Ids that are no longer in the list (staged or deleted elsewhere) are
    /// dropped, so an action can never operate on a stale selection.
    func selectedItems(in tab: AppTab, from items: [MediaItem]) -> [MediaItem] {
        guard let ids = selection[tab], !ids.isEmpty else { return [] }
        return items.filter { ids.contains($0.id) }
    }

    /// An id → item map over the current library snapshot, rebuilt only when
    /// the library actually changes.
    ///
    /// This exists because the selection is resolved on every pass through a
    /// view body. Filtering a 20 000-item array to find twelve ticked photos
    /// was fine once, but it ran on every frame of every scroll.
    @ObservationIgnored
    private var itemIndexRevision = -1

    @ObservationIgnored
    private var itemIndex: [MediaItem.ID: MediaItem] = [:]

    private var itemsByID: [MediaItem.ID: MediaItem] {
        if itemIndexRevision != library.revision {
            itemIndex = Dictionary(
                library.items.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            itemIndexRevision = library.revision
        }
        return itemIndex
    }

    /// The items a screen can select from. One definition, so select-all and
    /// the action bar can never disagree about what "everything" means.
    private func selectableSource(in tab: AppTab) -> [MediaItem] {
        switch tab {
        case .library, .search: browsableItems
        case .cleanup: cleanupGroups.flatMap(\.items)
        case .bin: bin.staged
        case .review: []
        }
    }

    /// How many items a screen can select from, without building the list.
    private func selectableCount(in tab: AppTab) -> Int {
        switch tab {
        case .library, .search: browsableCount
        case .cleanup: cleanupGroups.reduce(0) { $0 + $1.items.count }
        case .bin: bin.staged.count
        case .review: 0
        }
    }

    /// The selected items of a screen, resolved against the library.
    ///
    /// Walks the *selection* (a dozen ids at most) rather than the library, so
    /// it is O(k) and safe to call from a view body.
    func selectedItems(in tab: AppTab) -> [MediaItem] {
        guard let ids = selection[tab], !ids.isEmpty else { return [] }

        switch tab {
        case .library, .search:
            let index = itemsByID
            let staged = Set(bin.staged.map(\.id))
            return ids.compactMap { index[$0] }.filter { !staged.contains($0.id) }
        case .cleanup:
            let index = Dictionary(
                cleanupGroups.flatMap(\.items).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            return ids.compactMap { index[$0] }
        case .bin:
            let index = Dictionary(
                bin.staged.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            return ids.compactMap { index[$0] }
        case .review:
            return []
        }
    }

    /// Whether everything on a screen is ticked. Drives the select-all control.
    ///
    /// A count check runs first: the selection is pruned to ids that exist, so
    /// it can never be *larger* than the screen's contents. Only when the counts
    /// match is the exact set comparison worth doing — and by then the answer is
    /// almost always "yes".
    func allSelected(in tab: AppTab) -> Bool {
        guard let ids = selection[tab], !ids.isEmpty else { return false }
        let total = selectableCount(in: tab)
        guard total > 0, ids.count >= total else { return false }
        let source = selectableSource(in: tab)
        return !source.isEmpty && ids.isSuperset(of: Set(source.map(\.id)))
    }

    /// Ticking an item is what puts a screen into multi-select mode, so there is
    /// no separate mode to discover.
    func toggleSelection(_ id: MediaItem.ID, in tab: AppTab) {
        var ids = selection[tab] ?? []
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
            selecting.insert(tab)
        }
        setSelection(ids, in: tab)
    }

    /// Shifts a whole screen into selection mode without ticking anything, so
    /// the mode is reachable before the first tap.
    func beginSelection(_ tab: AppTab) {
        selecting.insert(tab)
    }

    /// Selects or deselects everything currently visible on a screen.
    func toggleSelectAll(in tab: AppTab) {
        let ids = Set(selectableSource(in: tab).map(\.id))
        guard !ids.isEmpty else { return }
        if (selection[tab] ?? []).isSuperset(of: ids) {
            clearSelection(in: tab)
        } else {
            selection[tab] = ids
            selecting.insert(tab)
        }
    }

    func clearSelection(in tab: AppTab) {
        selection[tab] = nil
        selecting.remove(tab)
    }

    /// Writes a selection and keeps the mode flag consistent with it: an empty
    /// selection is not a mode, and leaving it "on" is what made the bar hang
    /// around over nothing.
    private func setSelection(_ ids: Set<MediaItem.ID>, in tab: AppTab) {
        if ids.isEmpty {
            selection[tab] = nil
            selecting.remove(tab)
        } else {
            selection[tab] = ids
            selecting.insert(tab)
        }
    }

    // MARK: Actions

    /// Clears a set of ids from every screen's selection. Mutating a dictionary
    /// while iterating its own `keys` is undefined behaviour in Swift, so this
    /// walks a snapshot of the keys.
    private func removeFromSelection(_ ids: Set<MediaItem.ID>) {
        for tab in Array(selection.keys) {
            guard let current = selection[tab] else { continue }
            setSelection(current.subtracting(ids), in: tab)
        }
    }

    func stage(_ items: [MediaItem]) {
        let added = bin.stage(items)
        guard !added.isEmpty else { return }
        let ids = Set(added.map(\.id))
        removeFromSelection(ids)
        offerUndo(
            added.count == 1
                ? "Ajouté au panier."
                : "\(added.count) éléments ajoutés au panier.",
            restore: { [weak self] in self?.bin.unstage(ids) }
        )
    }

    /// Removes items from the bin, with an undo that puts them back where they
    /// were.
    func unstage(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }
        let ids = Set(items.map(\.id))
        bin.unstage(ids)
        offerUndo(
            items.count == 1
                ? "Retiré du panier."
                : "\(items.count) éléments retirés du panier.",
            restore: { [weak self] in self?.bin.restore(items) }
        )
    }

    func unstageAll() {
        let previous = bin.staged
        guard !previous.isEmpty else { return }
        bin.unstageAll()
        offerUndo("Panier vidé.") { [weak self] in
            self?.bin.restoreExact(previous)
        }
    }

    /// Flips the favourite flag on a set of assets, locally and in PhotoKit.
    ///
    /// The local snapshot is updated first so the heart responds to the tap
    /// instead of waiting for a change notification, and rolled back only if
    /// PhotoKit refused *and* nothing else has touched the flag since.
    func toggleFavorite(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }
        let ids = Set(items.map(\.id))
        let target = !items.allSatisfy(\.isFavorite)
        library.setFavorite(target, ids: ids)

        Task {
            let ok = await MediaActions.setFavorite(target, ids: ids)
            guard !ok else { return }
            let stillTarget = library.items
                .filter { ids.contains($0.id) }
                .allSatisfy { $0.isFavorite == target }
            guard stillTarget else { return }
            library.setFavorite(!target, ids: ids)
        }
    }

    /// After a confirmed deletion, drop the assets from every cached list.
    func applyRemoval(_ ids: Set<MediaItem.ID>) {
        guard !ids.isEmpty else { return }
        library.remove(ids: ids)
        cleanupGroups = cleanupGroups.map { group in
            CleanupGroup(
                id: group.id,
                title: group.title,
                reason: group.reason,
                symbol: group.symbol,
                items: group.items.filter { !ids.contains($0.id) }
            )
        }
        .filter { !$0.items.isEmpty }

        removeFromSelection(ids)
    }

    // MARK: Viewer

    func openViewer(_ item: MediaItem) {
        viewerItem = item
        viewerToken &+= 1
    }

    func closeViewer() {
        viewerItem = nil
    }

    // MARK: Undo

    private func offerUndo(_ message: String, restore: @escaping () -> Void) {
        undo = UndoAction(message: message, restore: restore)
    }

    func performUndo() {
        guard let action = undo else { return }
        undo = nil
        action.restore()
    }

    func dismissUndo() {
        undo = nil
    }
}
