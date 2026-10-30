import SwiftUI

/// The grid used by the library, the search results, the cleanup groups and
/// the bin.
///
/// It exists for two reasons. Every screen used to re-implement its own
/// `LazyVGrid` with its own tap handling, so a fix in one never reached the
/// others; and the tap handling was wrong in all of them. A tap either staged
/// the photo immediately (library, search) or did nothing useful, when the
/// obvious gesture on a photo is to look at it.
///
/// Here a tap opens the viewer, the viewer offers the actions, and a long press
/// is a shortcut straight into multi-select — the same grammar as Photos.
struct MediaGrid: View {
    let items: [MediaItem]
    /// The screen this grid belongs to, used to key its own selection.
    let tab: AppTab
    var columns: Int = 4
    var spacing: CGFloat = Theme.Metrics.gridSpacing

    @Environment(AppState.self) private var state
    @Environment(\.displayScale) private var displayScale

    /// Position of each asset, so the prefetcher can find "the next 24" without
    /// scanning the list. Built once per list: `firstIndex(where:)` inside the
    /// cell was O(n) per cell, which is O(n²) for one screen of a 20 000-asset
    /// library.
    @State private var indexByID: [MediaItem.ID: Int] = [:]

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)
    }

    private var selecting: Bool { state.isSelecting(tab) }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: spacing) {
            ForEach(items) { item in
                cell(for: item)
                    .onAppear { prefetch(after: item) }
            }
        }
        .padding(.horizontal, 2)
        .task(id: indexKey) {
            indexByID = Dictionary(
                uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) }
            )
        }
    }

    /// Cheap fingerprint of the list, so the index is rebuilt when the content
    /// changes and not on every unrelated state update.
    private var indexKey: String {
        "\(items.count)|\(items.first?.id ?? "-")|\(items.last?.id ?? "-")"
    }

    private func cell(for item: MediaItem) -> some View {
        let isSelected = state.isSelected(item.id, in: tab)

        return Button {
            handleTap(on: item)
        } label: {
            MediaCell(
                item: item,
                isStaged: tab == .bin,
                isSelected: isSelected,
                selectionMode: selecting
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            // A long press is the shortcut the app was missing: from here you
            // can act on one asset without leaving the grid.
            Button {
                state.toggleFavorite([item])
            } label: {
                Label(
                    item.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris",
                    systemImage: item.isFavorite ? "heart.slash" : "heart"
                )
            }

            if tab == .bin {
                Button {
                    state.unstage([item])
                } label: {
                    Label("Retirer du panier", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button {
                    state.stage([item])
                } label: {
                    Label("Mettre au panier", systemImage: "tray.and.arrow.down")
                }
            }

            Button {
                withAnimation(Theme.Motion.pill) {
                    state.beginSelection(tab)
                    state.toggleSelection(item.id, in: tab)
                }
            } label: {
                Label("Sélectionner", systemImage: "checkmark.circle")
            }
        }
    }

    private func handleTap(on item: MediaItem) {
        if selecting {
            withAnimation(.smooth(duration: 0.2)) {
                state.toggleSelection(item.id, in: tab)
            }
        } else {
            state.openViewer(item)
        }
    }

    /// Warms the next couple of dozen thumbnails, once per run of twelve cells
    /// rather than on every cell.
    private func prefetch(after item: MediaItem) {
        guard let index = indexByID[item.id], index % 12 == 0 else { return }

        let upper = min(index + 24, items.count)
        guard upper > index + 1 else { return }
        ThumbnailLoader.shared.prefetch(
            ids: items[(index + 1)..<upper].map(\.id),
            target: .grid,
            scale: displayScale
        )
    }
}
