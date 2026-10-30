import SwiftUI

/// One shared, app-wide state for what the user is looking at and what they
/// have staged. Passed through the environment so the five tabs agree without
/// prop-drilling a dozen bindings.
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

    /// Assets the user has ticked in multi-select mode, per screen.
    var selected: Set<MediaItem.ID> = []
    var isSelecting = false

    /// Review deck position.
    var reviewIndex = 0

    /// Cleanup groups, computed once per library load.
    var cleanupGroups: [CleanupGroup] = []

    // MARK: Derived

    var stagedCount: Int { bin.staged.count }

    var totalItems: Int { library.items.count }

    /// Items still available to browse — the library minus anything already
    /// staged, so the same asset never appears in two places at once.
    var browsableItems: [MediaItem] {
        let staged = Set(bin.staged.map(\.id))
        guard !staged.isEmpty else { return library.items }
        return library.items.filter { !staged.contains($0.id) }
    }

    // MARK: Actions

    func stage(_ items: [MediaItem]) {
        bin.stage(items)
        selected.subtract(items.map(\.id))
    }

    func toggleSelection(_ id: MediaItem.ID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    func clearSelection() {
        selected.removeAll()
        isSelecting = false
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

        selected.subtract(ids)
    }
}
