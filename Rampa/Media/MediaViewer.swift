import AVKit
import SwiftUI

/// The full-screen viewer.
///
/// Tapping a photo in any grid used to stage it for deletion, which is a
/// startling thing for a tap on a picture to do and made the library useless
/// for actually *looking* at your photos. The tap now opens this: the asset,
/// whole and uncropped, with the actions it can take laid out underneath it.
///
/// The layout is deliberately bottom-heavy. The image gets the space, the
/// chrome sits where a thumb already is, and the sheet can be swiped down
/// because the whole screen is one scroll.
struct MediaViewer: View {
    let item: MediaItem

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var showInfo = false
    @State private var player: AVPlayer?
    @State private var metadata: MediaActions.Metadata?
    /// Mirrors the asset's favourite flag so the star can respond to the tap
    /// immediately; `item` is a snapshot and will not change under us.
    @State private var isFavorite = false

    var body: some View {
        ZStack {
            // A near-black stage: a photo viewer should never letterbox a
            // picture against the app's warm canvas.
            Color.black.opacity(0.94)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                imageStage

                if showInfo {
                    infoPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                actionBar
            }
        }
        .statusBarHidden()
        .task(id: item.id) {
            isFavorite = state.library.items.first { $0.id == item.id }?.isFavorite
                ?? item.isFavorite
            await loadMetadata()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .animation(.smooth(duration: 0.26), value: showInfo)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Fermer")

            VStack(alignment: .leading, spacing: 1) {
                Text(item.creationDate.formatted(date: .long, time: .shortened))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(item.isVideo ? "Vidéo" : "Photo")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer(minLength: 0)

            Button {
                showInfo.toggle()
            } label: {
                Image(systemName: showInfo ? "info.circle.fill" : "info.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(showInfo ? "Masquer les informations" : "Afficher les informations")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: Image

    @ViewBuilder
    private var imageStage: some View {
        if item.isVideo {
            videoStage
        } else {
            // `.fit`, not `.fill`: the deck used to crop every photo to a
            // square, so the top and bottom of a portrait shot were simply
            // not visible in the one screen meant for looking at it.
            ThumbnailView(assetID: item.id, target: .deck, fill: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)
        }
    }

    private var videoStage: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, 8)
            } else {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Chargement de la vidéo…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            player = await MediaActions.makePlayer(for: item.id)
        }
    }

    // MARK: Info

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let metadata {
                infoRow("Date", metadata.creationDate.formatted(date: .abbreviated, time: .shortened))
                infoRow("Type", metadata.kindText)
                infoRow("Dimensions", "\(metadata.pixelWidth) × \(metadata.pixelHeight)")
                infoRow("Poids", metadata.byteText ?? "Inconnu")
                if metadata.isVideo, let duration = metadata.durationText {
                    infoRow("Durée", duration)
                }
            } else {
                infoRow("Dimensions", item.resolutionText)
                infoRow("Poids", "Calcul…")
            }

            Text("Apple ne transmet ni le contenu ni le lieu d'une photo aux apps tierces. Ces informations sont celles que PhotoKit accepte de partager.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
    }

    // MARK: Actions

    /// The live copy of the asset.
    ///
    /// `item` is the snapshot that was tapped, so its `isFavorite` goes stale
    /// the moment the star is tapped. Everything the viewer acts on resolves
    /// through here, which keeps the flag, the star and PhotoKit in agreement.
    private var liveItem: MediaItem {
        state.library.items.first { $0.id == item.id } ?? item
    }

    /// The reason the viewer exists: looking is the default, acting is one tap
    /// away and never the accidental result of the gesture that opened it.
    private var actionBar: some View {
        HStack(spacing: 8) {
            viewerAction(
                title: "Favori",
                symbol: isFavorite ? "heart.fill" : "heart",
                tint: isFavorite ? Theme.danger : .white
            ) {
                withAnimation(.smooth(duration: 0.22)) {
                    isFavorite.toggle()
                }
                state.toggleFavorite([liveItem])
            }

            if state.tab == .bin {
                viewerAction(title: "Retirer", symbol: "arrow.uturn.backward", tint: .white) {
                    state.unstage([liveItem])
                    dismiss()
                }
            } else {
                viewerAction(title: "Panier", symbol: "tray.and.arrow.down", tint: .white) {
                    state.stage([liveItem])
                    dismiss()
                }
            }

            viewerAction(title: "Sélection", symbol: "checkmark.circle", tint: .white) {
                withAnimation(Theme.Motion.pill) {
                    state.beginSelection(state.tab)
                    state.toggleSelection(item.id, in: state.tab)
                }
                dismiss()
            }

            viewerAction(title: "Fermer", symbol: "chevron.down", tint: .white) {
                dismiss()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func viewerAction(
        title: String,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolEffect(.bounce, value: isFavorite)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(.white.opacity(0.10), in: .rect(cornerRadius: 14, style: .continuous))
            .contentShape(.rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(title)
    }

    // MARK: Loading

    private func loadMetadata() async {
        metadata = await MediaActions.metadata(for: item.id)
    }
}
