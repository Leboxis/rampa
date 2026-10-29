import SwiftUI

extension View {

    /// Applies Liquid Glass on iOS 26+, and a translucent material on anything
    /// older.
    ///
    /// The modifier is always applied *after* the layout and appearance
    /// modifiers on the receiver, because glass samples the content behind the
    /// final frame: applying it before `.padding()` or `.frame()` gives it the
    /// wrong sampling region.
    ///
    /// - Parameters:
    ///   - shape: Shape of the glass surface. Keep one shape family per feature.
    ///   - tint: Optional tint. Use it to signal prominence, not decoration.
    ///   - interactive: Pass `true` only for surfaces that respond to touch.
    @ViewBuilder
    func glassSurface<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26, *) {
            glassEffect(
                Self.glassValue(tint: tint, interactive: interactive),
                in: shape
            )
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }

    @available(iOS 26, *)
    private static func glassValue(tint: Color?, interactive: Bool) -> Glass {
        var value = Glass.regular
        if let tint {
            value = value.tint(tint)
        }
        if interactive {
            value = value.interactive()
        }
        return value
    }
}
