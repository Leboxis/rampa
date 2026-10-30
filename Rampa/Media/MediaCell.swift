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

    var body: some View {
        SquareThumbnail(assetID: item.id, cornerRadius: cornerRadius)
            .overlay {
                if isStaged {
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
            .overlay(alignment: .topTrailing) {
                if selectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.flare : .white)
                        .shadow(radius: 2)
                        .padding(6)
                        .symbolEffect(.bounce, value: isSelected)
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
            .animation(.smooth(duration: 0.22), value: isStaged)
            .animation(.smooth(duration: 0.22), value: isSelected)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? [.isImage, .isSelected] : .isImage)
    }

    private var borderColor: Color {
        if isStaged { return Theme.danger }
        if isSelected { return Theme.flare }
        return .clear
    }

    private var borderWidth: CGFloat {
        isStaged || isSelected ? 2.5 : 0
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
