import SwiftUI

/// A tappable photo cell that knows three things: whether it is staged for
/// deletion, whether it is part of the current selection, and whether it is
/// currently being dragged.
struct MediaCell: View {
    let item: MediaItem
    let isStaged: Bool
    let isSelected: Bool
    let selectionMode: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ThumbnailView(assetID: item.id, target: .grid)
                .aspectRatio(1, contentMode: .fill)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isStaged ? Theme.danger : (isSelected ? Theme.flare : .clear),
                            lineWidth: isStaged || isSelected ? 2.5 : 0
                        )
                }
                .overlay(alignment: .bottomLeading) {
                    if let duration = item.durationText {
                        Text(duration)
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.55), in: .rect(cornerRadius: 4))
                            .padding(5)
                    }
                }
                .overlay {
                    // Dimming is the cheapest way to say "already in the bin"
                    // without adding a fourth overlay layer.
                    if isStaged {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.danger.opacity(0.22))
                    }
                }

            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.flare : .white)
                    .background(Circle().fill(.black.opacity(0.35)).padding(2))
                    .padding(6)
                    .symbolEffect(.bounce, value: isSelected)
            } else if isStaged {
                Image(systemName: "trash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Theme.danger, in: Circle())
                    .padding(5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
        .animation(.smooth(duration: 0.18, extraBounce: 0.2), value: pressed)
        .animation(.smooth(duration: 0.22), value: isStaged)
        .animation(.smooth(duration: 0.22), value: isSelected)
        .onLongPressGesture(minimumDuration: 0.01, pressing: { pressing in
            pressed = pressing
        }, perform: {})
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isImage, .isSelected] : .isImage)
    }

    private var accessibilityLabel: String {
        var parts = [item.isVideo ? "Vidéo" : "Photo"]
        parts.append(item.creationDate.formatted(date: .abbreviated, time: .shortened))
        if item.isScreenCapture { parts.append("capture d'écran") }
        if isStaged { parts.append("dans le panier") }
        if isSelected { parts.append("sélectionnée") }
        return parts.joined(separator: ", ")
    }
}
