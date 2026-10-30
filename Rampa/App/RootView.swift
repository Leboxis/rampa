import SwiftUI

/// The app shell: a drifting backdrop, the stage for the current tab, and the
/// floating Liquid Glass bar pinned above the home indicator.
///
/// The bar is laid out by the parent rather than with `.safeAreaInset`, so it
/// floats clear of the home indicator and content can pass behind it. The stage
/// reserves the bar's height at the bottom, which keeps content out from under
/// the glass.
struct RootView: View {
    @State private var state = AppState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .padding(.horizontal, Theme.Metrics.barInset)
                .padding(.bottom, 6)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.canvas)
        .environment(state)
    }

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

    /// A short vertical glide with a fade. Deliberately restrained: the bar's
    /// travelling lens is the loud moment, the content only has to get out of
    /// the way.
    private var stageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 14)),
            removal: .opacity.combined(with: .offset(y: -14))
        )
    }
}

#Preview {
    RootView()
}
