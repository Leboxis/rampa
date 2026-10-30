import SwiftUI

/// The heading every screen wears: one large rounded title, an optional
/// one-line explainer, and a trailing slot for whatever that screen needs
/// (a count, a sort menu, a Terminé button).
///
/// Before this existed, all five screens re-implemented the same three
/// `.padding` calls with slightly different values, which is why the titles did
/// not sit at the same height when you swiped between tabs.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)

                trailing
            }

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A numeric counter for the header's trailing slot, with a rolling transition
/// so a count that changes reads as a change rather than a flicker.
struct HeaderCount: View {
    let value: Int
    var suffix: String?

    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .contentTransition(.numericText())
            if let suffix {
                Text(suffix)
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .foregroundStyle(Theme.inkSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(suffix.map { "\(value) \($0)" } ?? "\(value)")
    }
}

/// The pinned header above a grid section.
struct SectionHeader: View {
    let title: String
    let caption: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Spacer()

            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
    }
}

/// The empty state, in one place: a glyph, a short headline, and one honest
/// sentence about why the screen is empty.
struct EmptyStateView: View {
    /// An optional call to action under the message.
    struct Action {
        let title: String
        let perform: () -> Void
    }

    let symbol: String
    let title: String
    let message: String
    var tint: Color = Theme.flare
    var action: Action?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.bottom, 2)

            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.bordered)
                    .tint(Theme.flare)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}

/// A compact pill toggle, used for the grouping axis and for search filters.
struct Chip: View {
    let title: String
    var symbol: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isOn ? Theme.flare : Theme.inkSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(isOn ? Theme.flare.opacity(0.14) : Color.clear)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isOn ? Theme.flare.opacity(0.4) : Theme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// Room reserved at the bottom of a scroll view so its last row clears the
/// floating bar.
///
/// The stage already ends above the bar, so this is a comfort margin, not a
/// clearance: the old `Color.clear.frame(height: 110)` was reserving space for
/// a bar that was never on top of the content, and left a dead gap under every
/// grid.
struct ScrollBottomInset: View {
    var height: CGFloat = 24

    var body: some View {
        Color.clear.frame(height: height)
    }
}
