import SwiftUI

/// A press style that shrinks and dims slightly, so every tap on the bar has a
/// visible answer even before the pill finishes travelling.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.smooth(duration: 0.18, extraBounce: 0.1), value: configuration.isPressed)
    }
}
