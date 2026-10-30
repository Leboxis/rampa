import SwiftUI
import UIKit

/// Rampa's visual tokens.
///
/// The palette is deliberately tiny: one graphite ink that recedes, one vivid
/// "flare" that is only ever allowed to mean *this is the active tab*, and a
/// canvas that gives the Liquid Glass something to refract. Every colour has a
/// light and a dark value tuned so the accent keeps a contrast ratio above
/// 4.5:1 against the canvas in both appearances.
enum Theme {

    // MARK: Colour

    /// Page background. Warm off-white in light, near-black in dark.
    static let canvas = Color(light: 0xF7F6F3, dark: 0x08090B)

    /// Primary text.
    static let ink = Color(light: 0x0F1115, dark: 0xF2F3F5)

    /// Secondary text and inactive tab glyphs.
    static let inkSecondary = Color(light: 0x5A5F6A, dark: 0x9AA1AD)

    /// The single accent. Used for the active tab and its ambient light only.
    static let flare = Color(light: 0x2F5BEA, dark: 0x7DA2FF)

    /// Reserved exclusively for destructive intent. Never used for decoration,
    /// so seeing it always means "this removes something".
    static let danger = Color(light: 0xC2352F, dark: 0xFF7B72)

    /// Neutral surface behind unloaded thumbnails and empty grids.
    static let placeholder = Color(light: 0xE7E5E0, dark: 0x16181D)

    /// Hairline separator on the canvas.
    static let hairline = Color(light: 0x000000, dark: 0xFFFFFF).opacity(0.10)

    // MARK: Metrics

    enum Metrics {
        /// Height of the floating glass bar. Comfortably above the 44 pt
        /// minimum touch target once the button's own frame is considered.
        static let barHeight: CGFloat = 60

        /// Horizontal inset of the bar from the screen edges.
        static let barInset: CGFloat = 20

        /// Inset of the active pill inside the bar.
        static let pillInset: CGFloat = 4
    }

    // MARK: Motion

    enum Motion {
        /// Drives the lens sliding between tabs *and* the stage cross-fade.
        /// Sharing one curve matters: the bar and the content are two views of
        /// the same state change, so they must land together. 0.34 s with a
        /// 0.06 bounce is roughly 40 frames at 120 Hz — long enough to read as
        /// movement, short enough to feel instant.
        static let pill = Animation.smooth(duration: 0.34, extraBounce: 0.06)

        /// Ambient light drifting behind the canvas when the tab changes.
        /// Slower than the lens so the background lags the foreground, which is
        /// what gives the motion depth.
        static let ambient = Animation.smooth(duration: 0.65, extraBounce: 0)

        /// Used instead of the springs when Reduce Motion is on.
        static let reduced = Animation.easeOut(duration: 0.16)
    }
}

// MARK: - Colour helpers

extension Color {
    /// Builds a colour that resolves differently in light and dark appearance.
    ///
    /// - Parameters:
    ///   - light: 24-bit sRGB hex used in light appearance.
    ///   - dark: 24-bit sRGB hex used in dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(
                hex: traits.userInterfaceStyle == .dark ? dark : light,
                alpha: 1
            )
        })
    }
}

extension UIColor {
    /// Builds an opaque sRGB colour from a 24-bit hex value such as `0x2F5BEA`.
    convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
