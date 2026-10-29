import SwiftUI

/// A soft pool of accent light that drifts to a new corner each time the tab
/// changes. It is the only decoration on the canvas, and it exists so the glass
/// bar always has something worth refracting — a glass surface over flat colour
/// looks like a grey pill.
struct AmbientBackdrop: View {
    let tab: AppTab

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Theme.canvas

                // Flare, low and wide, drifting with the selection.
                Ellipse()
                    .fill(Theme.flare.opacity(scheme == .dark ? 0.30 : 0.16))
                    .frame(width: size.width * 1.1, height: size.height * 0.55)
                    .blur(radius: 90)
                    .offset(
                        x: (CGFloat(tab.rawValue) / CGFloat(AppTab.allCases.count - 1) - 0.5) * size.width * 0.5,
                        y: size.height * 0.28
                    )

                // A cool counter-light, opposite, so the top of the screen is
                // never dead flat.
                Ellipse()
                    .fill(Color(light: 0x8FB4FF, dark: 0x2A4EA8).opacity(scheme == .dark ? 0.22 : 0.18))
                    .frame(width: size.width * 0.9, height: size.height * 0.4)
                    .blur(radius: 80)
                    .offset(
                        x: (0.5 - CGFloat(tab.rawValue) / CGFloat(AppTab.allCases.count - 1)) * size.width * 0.45,
                        y: -size.height * 0.32
                    )
            }
            .animation(
                reduceMotion ? Theme.Motion.reduced : Theme.Motion.ambient,
                value: tab
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
