import SwiftUI

/// The floating Liquid Glass navigation bar.
///
/// One glass surface holds five buttons. A tinted "lens" slides between them,
/// so the bar reads as a single physical object rather than five chips. The
/// lens follows the finger during a horizontal drag and settles on the nearest
/// destination when the drag ends, which is what makes the bar feel slidable
/// rather than merely animated.
struct GlassTabBar: View {
    let selection: AppTab
    let onSelect: (AppTab) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Live horizontal travel of a drag over the bar. Kept as `@State` rather
    /// than `@GestureState` so the settle-back can be wrapped in an explicit
    /// animation instead of snapping.
    @State private var dragOffset: CGFloat = 0

    private var count: CGFloat { CGFloat(AppTab.allCases.count) }

    var body: some View {
        GeometryReader { proxy in
            let itemWidth = (proxy.size.width - Theme.Metrics.pillInset * 2) / count

            ZStack(alignment: .leading) {
                lens(itemWidth: itemWidth)
                buttons(itemWidth: itemWidth)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Capsule())
            .simultaneousGesture(dragGesture(itemWidth: itemWidth))
        }
        .frame(height: Theme.Metrics.barHeight)
        .glassSurface(
            in: Capsule(),
            tint: reduceTransparency ? nil : Theme.flare.opacity(0.06)
        )
        .sensoryFeedback(.selection, trigger: selection)
        .animation(reduceMotion ? Theme.Motion.reduced : Theme.Motion.pill, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation principale")
    }

    // MARK: Lens

    /// The sliding highlight. It is deliberately *not* glass: glass cannot
    /// sample glass, so a second glass surface inside the bar muddies the
    /// material. A tinted capsule with a hairline rim reads as a lens set into
    /// the bar instead.
    private func lens(itemWidth: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Theme.flare.opacity(0.26),
                        Theme.flare.opacity(0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                    .blendMode(.plusLighter)
            }
            .frame(
                width: max(itemWidth - 8, 0),
                height: Theme.Metrics.barHeight - Theme.Metrics.pillInset * 2
            )
            .offset(x: Theme.Metrics.pillInset + itemWidth * CGFloat(selection.rawValue) + 4 + dragOffset)
            .allowsHitTesting(false)
    }

    // MARK: Buttons

    private func buttons(itemWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                TabBarButton(
                    tab: tab,
                    isSelected: tab == selection,
                    itemWidth: itemWidth
                ) {
                    select(tab)
                }
            }
        }
        .padding(.horizontal, Theme.Metrics.pillInset)
    }

    // MARK: Gestures

    private func dragGesture(itemWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !reduceMotion else { return }
                dragOffset = clamped(value.translation.width, itemWidth: itemWidth)
            }
            .onEnded { value in
                // `predictedEndTranslation` carries the flick's momentum, so a
                // quick swipe skips a tab the way a scroll view would.
                let steps = Int((value.predictedEndTranslation.width / itemWidth).rounded())
                let target = min(max(selection.rawValue + steps, 0), AppTab.allCases.count - 1)
                let next = AppTab(rawValue: target) ?? selection

                withAnimation(reduceMotion ? Theme.Motion.reduced : Theme.Motion.pill) {
                    dragOffset = 0
                    if next != selection { onSelect(next) }
                }
            }
    }

    /// Rubber-band: the lens tracks the finger but never runs past the first or
    /// the last destination.
    private func clamped(_ translation: CGFloat, itemWidth: CGFloat) -> CGFloat {
        let lower = -itemWidth * CGFloat(selection.rawValue)
        let upper = itemWidth * CGFloat(AppTab.allCases.count - 1 - selection.rawValue)
        return min(max(translation, lower), upper)
    }

    private func select(_ tab: AppTab) {
        guard tab != selection else { return }
        onSelect(tab)
    }
}

// MARK: - Button

/// One destination in the bar: a glyph that lifts and tints when active, with
/// its label always visible so the bar is readable without guessing at symbols.
private struct TabBarButton: View {
    let tab: AppTab
    let isSelected: Bool
    let itemWidth: CGFloat
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.flare : Theme.inkSecondary)
                    .symbolEffect(.bounce, value: isSelected)
                    .offset(y: isSelected && !reduceMotion ? -2 : 0)

                Text(tab.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.flare : Theme.inkSecondary)
                    .opacity(isSelected ? 1 : 0.7)
            }
            .frame(width: itemWidth, height: Theme.Metrics.barHeight - Theme.Metrics.pillInset * 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
