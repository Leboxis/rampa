import SwiftUI

/// How an image should fill the space it is given.
enum ThumbnailFill: Hashable {
    /// Fill the box and crop the overflow. The right choice for square grid
    /// cells, where a consistent mosaic beats a faithful aspect ratio.
    case fill
    /// Fit the whole image inside the box and letterbox it. The right choice
    /// for the viewer and the review deck, where cropping a photo is a bug.
    case fit
}

/// Draws one library image, loading it off the main actor and downsampling it
/// to the size of this cell.
///
/// Layout contract: this view is **flexible and has no intrinsic size**. It
/// takes whatever it is offered and clips its content to that. That matters
/// more than it looks: an `Image` with `.scaledToFill()` reports the image's
/// native pixel size as its ideal size, so putting one straight into a `ZStack`
/// makes the cell claim e.g. 1600×1600 pt. In a `LazyVGrid` that produces
/// overlapping cells, and in a full-screen container it blows the whole window
/// out — which is exactly what pushed the nav bar off screen before.
///
/// `Color.clear` accepts any proposal and has no ideal size, so the overlay
/// pattern below keeps the image from ever influencing layout. A
/// `GeometryReader` would *not* do here: it takes the whole proposal, and in a
/// lazily sized grid row that is not a size anyone defined.
struct ThumbnailView: View {
    let assetID: String
    var target: ThumbnailLoader.Target = .grid
    var fill: ThumbnailFill = .fill

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: fill == .fill ? .fill : .fit)
                        .transition(.opacity)
                } else {
                    Theme.placeholder
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: taskKey) {
                await load()
            }
    }

    /// Re-runs the load when the asset or the fill mode changes, and never for
    /// anything else.
    private var taskKey: String {
        "\(assetID)|\(target == .deck ? "deck" : "grid")|\(fill == .fit ? "fit" : "fill")|\(Int(displayScale))"
    }

    private func load() async {
        if fill == .fill,
           let hit = ThumbnailLoader.shared.cached(id: assetID, target: target, scale: displayScale) {
            image = hit
            return
        }

        image = nil
        let loaded = await ThumbnailLoader.shared.image(
            for: assetID,
            target: target,
            scale: displayScale,
            fill: fill
        )
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            image = loaded
        }
    }
}

/// A square thumbnail. The one place a grid cell's size is decided, so the grid
/// and the decoded pixel size can never disagree.
struct SquareThumbnail: View {
    let assetID: String
    var target: ThumbnailLoader.Target = .grid
    var cornerRadius: CGFloat = 10

    var body: some View {
        ThumbnailView(assetID: assetID, target: target)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}
