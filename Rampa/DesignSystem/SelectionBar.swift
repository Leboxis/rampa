import SwiftUI

/// One action offered on a selection or on the item in the viewer.
struct MediaAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    let perform: () -> Void

    init(
        id: String,
        title: String,
        symbol: String,
        tint: Color = Theme.ink,
        perform: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.perform = perform
    }
}

/// The bar that appears under the thumb as soon as something is ticked.
///
/// It replaces the navigation bar rather than stacking on top of it, so the two
/// never fight for the same 60 pt and the selection count is never ambiguous.
/// Destructive actions are held apart on the right, in `danger`, so they are
/// never adjacent to the everyday ones.
struct SelectionBar: View {
    let count: Int
    let allSelected: Bool
    let actions: [MediaAction]
    let onSelectAll: () -> Void
    let onDone: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelectAll) {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(allSelected ? Theme.flare : Theme.inkSecondary)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(allSelected ? "Tout désélectionner" : "Tout sélectionner")

            Text(count == 1 ? "1 sélection" : "\(count) sélections")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(actions) { action in
                Button(action: action.perform) {
                    Image(systemName: action.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(action.tint)
                        .frame(width: 42, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(action.title)
            }

            Button("Terminé", action: onDone)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.flare)
                .padding(.leading, 4)
                .frame(height: 44)
                .buttonStyle(.plain)
                .accessibilityLabel("Quitter le mode sélection")
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.Metrics.barHeight)
        .glassSurface(
            in: Capsule(),
            tint: reduceTransparency ? nil : Theme.flare.opacity(0.06)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions sur la sélection")
    }
}

/// A transient confirmation with an undo, shown above the bar.
///
/// The old trash was a one-way door: "Vider" emptied it with no way back, and
/// removing the wrong photo from it meant going to find it again. Undo is what
/// makes a destructive-looking action safe to try.
struct UndoBanner: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.flare)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button("Annuler", action: onUndo)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.flare)
                .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}
