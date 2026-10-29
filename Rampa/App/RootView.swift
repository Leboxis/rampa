import SwiftUI

/// The app shell: a drifting backdrop, the stage for the current tab, and the
/// floating Liquid Glass bar pinned above the home indicator.
///
/// The bar is laid out by the parent rather than with `.safeAreaInset`, so it
/// floats clear of the home indicator and content can pass behind it. The stage
/// reserves the bar's height at the bottom, which keeps its empty state centred
/// in the space you can actually see.
struct RootView: View {
    @State private var selection: AppTab = .home
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            AmbientBackdrop(tab: selection)

            TabStageView(tab: selection)
                .id(selection)
                .transition(stageTransition)
                .padding(.bottom, Theme.Metrics.barHeight + Theme.Metrics.barInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            GlassTabBar(selection: selection) { tab in
                guard tab != selection else { return }
                if reduceMotion {
                    selection = tab
                } else {
                    withAnimation(Theme.Motion.stage) { selection = tab }
                }
            }
            .padding(.horizontal, Theme.Metrics.barInset)
            .padding(.bottom, 6)
        }
        .background(Theme.canvas)
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
