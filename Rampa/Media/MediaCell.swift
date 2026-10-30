import SwiftUI

/// A tappable photo cell that knows three things: whether it is staged for
/// deletion, whether it is part of the current selection, and what kind of
/// media it is.
///
/// The cell is square by construction. Every overlay is sized against that
/// square, so nothing inside can change the cell's footprint — that was the bug
/// that made grid rows overlap.
struct MediaCell: View {
    let item: MediaItem
    let isStaged: Bool
    let isSelected: Bool
    let selectionMode: Bool
    var cornerRadius: CGFloat = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SquareThumbnail(assetID: item.id, cornerRadius: cornerRadius)
            .overlay {
                // A selection has to be readable at a glance across a whole
                // grid, so it dims the image as well as ringing it: a 2 pt
                // border alone disappears on a bright photo.
                if isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.flare.opacity(0.22))
                } else if isStaged {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.danger.opacity(0.22))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
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
            .overlay(alignment: .bottomTrailing) {
                if item.isFavorite && !selectionMode {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 1.5)
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selectionMode {
                    SelectionBadge(isSelected: isSelected)
                        .padding(5)
                } else if isStaged {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Theme.danger, in: Circle())
                        .padding(5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(isSelected && !reduceMotion ? 0.94 : 1)
            .animation(.smooth(duration: 0.22), value: isStaged)
            .animation(.smooth(duration: 0.22), value: isSelected)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? [.isImage, .isSelected] : .isImage)
            .accessibilityHint(
                selectionMode
                    ? "Touchez pour sélectionner ou désélectionner."
                    : "Touchez pour afficher en grand, touchez deux fois pour les actions."
            )
    }

    private var borderColor: Color {
        if isSelected { return Theme.flare }
        if isStaged { return Theme.danger }
        return .clear
    }

    private var borderWidth: CGFloat {
        isSelected ? 3 : (isStaged ? 2.5 : 0)
    }

    private var accessibilityLabel: String {
        var parts = [item.isVideo ? "Vidéo" : "Photo"]
        parts.append(item.creationDate.formatted(date: .abbreviated, time: .shortened))
        if item.isScreenCapture { parts.append("capture d'écran") }
        if item.isFavorite { parts.append("favori") }
        if isStaged { parts.append("dans le panier") }
        if isSelected { parts.append("sélectionnée") }
        return parts.joined(separator: ", ")
    }
}

/// The tick shown in multi-select mode. Extracted so the bounce lives in one
/// place and does not re-trigger when an unrelated cell changes.
private struct SelectionBadge: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isSelected ? .white : .white.opacity(0.9))
            .background {
                Circle()
                    .fill(isSelected ? Theme.flare : .black.opacity(0.28))
                    .padding(-1.5)
            }
            .shadow(radius: 2)
            .symbolEffect(.bounce, value: isSelected)
    }
}
