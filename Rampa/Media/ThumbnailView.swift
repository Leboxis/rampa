import SwiftUI

/// Draws one library thumbnail, loading it off the main actor and downsampling
/// it to the exact size of this cell.
///
/// It reads the cache synchronously in `body` when it can, so scrolling back
/// over seen cells never shows a placeholder flash.
struct ThumbnailView: View {
    let assetID: String
    let target: ThumbnailLoader.Target

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Theme.placeholder)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: assetID) {
            if let hit = ThumbnailLoader.shared.cached(
                id: assetID,
                target: target,
                scale: displayScale
            ) {
                image = hit
                return
            }
            image = nil
            let loaded = await ThumbnailLoader.shared.image(
                for: assetID,
                target: target,
                scale: displayScale
            )
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                image = loaded
            }
        }
    }
}
