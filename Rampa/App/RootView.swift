import SwiftUI

/// The app shell: a drifting backdrop, the stage for the current tab, and the
/// floating Liquid Glass bar pinned above the home indicator.
///
/// The bar is laid out by the parent rather than with `.safeAreaInset`, so it
/// floats clear of the home indicator and content can pass behind it. The stage
/// reserves the bar's height at the bottom, which keeps content out from under
/// the glass.
///
/// The bottom strip has three possible occupants that must never overlap: the
/// navigation bar, the selection bar, and an undo confirmation. They share one
/// slot and one height, so switching between them reads as the bar changing
/// its mind rather than three bars fighting for the same pixels.
struct RootView: View {
    @State private var state = AppState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                AmbientBackdrop(tab: state.tab)

                // The stage is given an explicit size and clipped. Without this
                // a single oversized child (an image claiming its native pixel
                // size, say) expands the ZStack, which pushes the bar off
                // screen and zooms the whole app.
                stage
                    .id(state.tab)
                    .transition(stageTransition)
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height - Theme.Metrics.barHeight - Theme.Metrics.barInset
                    )
                    .clipped()

                bottomStrip
                    .padding(.horizontal, Theme.Metrics.barInset)
                    .padding(.bottom, 6)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.canvas)
        .environment(state)
        .fullScreenCover(item: $state.viewerItem) { item in
            MediaViewer(item: item)
                .environment(state)
                // A fresh viewer per open, so tapping a second photo while one
                // is still dismissing does not reuse the previous asset.
                .id(state.viewerToken)
        }
        .onChange(of: state.tab) { oldTab, _ in
            // Leaving a screen abandons its selection: coming back to a bar
            // still counting photos you had forgotten about is worse than
            // losing the ticks.
            state.clearSelection(in: oldTab)
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from Settings after granting access used to show an
            // empty library until the next launch.
            guard phase == .active else { return }
            Task { await state.library.refreshAccess() }
        }
    }

    // MARK: Stage

    @ViewBuilder
    private var stage: some View {
        switch state.tab {
        case .library: LibraryScreen()
        case .review: ReviewScreen()
        case .cleanup: CleanupScreen()
        case .search: SearchScreen()
        case .bin: BinScreen()
        }
    }

    // MARK: Bottom strip

    private var bottomStrip: some View {
        VStack(spacing: 8) {
            if let undo = state.undo {
                UndoBanner(
                    message: undo.message,
                    onUndo: {
                        withAnimation(Theme.Motion.pill) { state.performUndo() }
                    },
                    onDismiss: {
                        withAnimation(Theme.Motion.pill) { state.dismissUndo() }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: undo.id) {
                    // Auto-dismiss, but long enough to actually reach.
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled, state.undo?.id == undo.id else { return }
                    withAnimation(Theme.Motion.pill) { state.dismissUndo() }
                }
            }

            if state.isSelecting(state.tab) {
                SelectionBar(
                    count: state.selectedCount(in: state.tab),
                    allSelected: state.allSelected(in: state.tab),
                    actions: selectionActions(for: state.tab),
                    onSelectAll: {
                        withAnimation(.smooth(duration: 0.2)) {
                            state.toggleSelectAll(in: state.tab)
                        }
                    },
                    onDone: {
                        withAnimation(Theme.Motion.pill) {
                            state.clearSelection(in: state.tab)
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            } else {
                GlassTabBar(
                    selection: state.tab,
                    badge: state.stagedCount
                ) { tab in
                    guard tab != state.tab else { return }
                    // One curve for everything that moves: the lens, the stage
                    // and the ambient pool are three views of the same state
                    // change.
                    if reduceMotion {
                        state.tab = tab
                    } else {
                        withAnimation(Theme.Motion.pill) { state.tab = tab }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
        }
    }

    /// The actions offered on the current selection.
    ///
    /// Each screen gets the ones that make sense on it: offering "mettre au
    /// panier" on the bin's own contents would be a loop, and offering "retirer
    /// du panier" anywhere else would be a lie.
    private func selectionActions(for tab: AppTab) -> [MediaAction] {
        let items = state.selectedItems(in: tab)
        guard !items.isEmpty else { return [] }
        let allFavorite = items.allSatisfy(\.isFavorite)

        switch tab {
        case .library, .search, .cleanup:
            return [
                MediaAction(
                    id: "favorite",
                    title: allFavorite ? "Retirer des favoris" : "Ajouter aux favoris",
                    symbol: allFavorite ? "heart.slash" : "heart"
                ) {
                    withAnimation(Theme.Motion.pill) {
                        state.toggleFavorite(items)
                        state.clearSelection(in: tab)
                    }
                },
                MediaAction(
                    id: "stage",
                    title: "Mettre au panier",
                    symbol: "tray.and.arrow.down",
                    tint: Theme.danger
                ) {
                    withAnimation(Theme.Motion.pill) {
                        state.stage(items)
                        state.clearSelection(in: tab)
                    }
                }
            ]

        case .bin:
            return [
                MediaAction(
                    id: "unstage",
                    title: "Retirer du panier",
                    symbol: "arrow.uturn.backward",
                    tint: Theme.flare
                ) {
                    withAnimation(Theme.Motion.pill) {
                        state.unstage(items)
                        state.clearSelection(in: tab)
                    }
                }
            ]

        case .review:
            return []
        }
    }
}

#Preview {
    RootView()
}
