import SwiftUI

/// Swipe triage. One asset at a time, big, with a physical gesture per verdict.
///
/// The deck never deletes. "Mettre au panier" is just a different bucket from
/// "Garder", and both are one flick away from being undone.
struct ReviewScreen: View {
    @Environment(AppState.self) private var state

    @State private var drag: CGSize = .zero
    @State private var kept: Set<MediaItem.ID> = []
    @State private var deciding = false

    /// Distance past which a flick commits.
    private let threshold: CGFloat = 110

    private var queue: [MediaItem] {
        let staged = Set(state.bin.staged.map(\.id))
        return state.library.items.filter { !staged.contains($0.id) && !kept.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if queue.isEmpty {
                finishedState
            } else {
                deck
                controls
            }
        }
        .task { await state.library.start() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Revue")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            Spacer()

            Text("\(queue.count) restantes")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: Deck

    private var deck: some View {
        ZStack {
            // The next two cards, stacked behind, so the deck has depth and a
            // swipe feels like it is revealing something.
            ForEach(Array(queue.prefix(3).enumerated()).reversed(), id: \.element.id) { index, item in
                card(item, index: index)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func card(_ item: MediaItem, index: Int) -> some View {
        let isTop = index == 0
        let offset = isTop ? drag : .zero
        let rotation = isTop ? Double(drag.width / 22) : 0
        let verdict = verdict(for: offset.width)

        return ZStack(alignment: .bottom) {
            ThumbnailView(assetID: item.id, target: .deck)
                .clipShape(.rect(cornerRadius: 22, style: .continuous))

            // Verdict stamp, driven by the drag itself so the answer is visible
            // before release.
            if let verdict, isTop {
                Text(verdict.label)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(verdict.tint, in: Capsule())
                    .padding(.bottom, 18)
                    .transition(.scale.combined(with: .opacity))
            }

            if let duration = item.durationText {
                Text(duration)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    verdict?.tint.opacity(0.9) ?? Theme.hairline,
                    lineWidth: verdict == nil ? 1 : 3
                )
        }
        .scaleEffect(isTop ? 1 : 1 - CGFloat(index) * 0.045)
        .offset(y: isTop ? 0 : CGFloat(index) * 10)
        .offset(x: offset.width, y: offset.height)
        .rotationEffect(.degrees(rotation))
        .opacity(isTop ? 1 : 0.55)
        .animation(.smooth(duration: 0.28, extraBounce: 0.05), value: index)
        .gesture(isTop ? swipe : nil)
        .accessibilityElement()
        .accessibilityLabel(item.isVideo ? "Vidéo" : "Photo")
        .accessibilityValue(item.creationDate.formatted(date: .abbreviated, time: .shortened))
        .accessibilityHint("Glissez à gauche pour mettre au panier, à droite pour garder.")
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !deciding else { return }
                drag = value.translation
            }
            .onEnded { value in
                commit(value.predictedEndTranslation.width)
            }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 14) {
            actionButton(
                title: "Panier",
                symbol: "trash",
                tint: Theme.danger
            ) {
                commit(-threshold * 2)
            }

            actionButton(
                title: "Garder",
                symbol: "checkmark",
                tint: Theme.flare
            ) {
                commit(threshold * 2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func actionButton(
        title: String,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(tint.opacity(0.12), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.32), lineWidth: 1)
            }
        }
        .buttonStyle(PressScaleStyle())
    }

    // MARK: Verdicts

    private struct Verdict {
        let label: String
        let tint: Color
    }

    private func verdict(for translation: CGFloat) -> Verdict? {
        guard translation.magnitude > 40 else { return nil }
        return translation < 0
            ? Verdict(label: "PANIER", tint: Theme.danger)
            : Verdict(label: "GARDER", tint: Theme.flare)
    }

    private func commit(_ predicted: CGFloat) {
        guard let top = queue.first, !deciding else { return }

        if predicted.magnitude < threshold {
            // Not far enough: spring back, no state change.
            withAnimation(.smooth(duration: 0.3, extraBounce: 0.15)) {
                drag = .zero
            }
            return
        }

        deciding = true
        let toBin = predicted < 0

        if toBin {
            state.stage([top])
        } else {
            kept.insert(top.id)
        }

        withAnimation(.smooth(duration: 0.26, extraBounce: 0)) {
            drag = CGSize(width: toBin ? -600 : 600, height: 0)
        }

        Task {
            try? await Task.sleep(for: .milliseconds(200))
            drag = .zero
            deciding = false
        }
    }

    // MARK: Empty

    private var finishedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Theme.flare)
            Text("Revue terminée")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("Vous avez passé toute la bibliothèque en revue. Les éléments mis de côté vous attendent dans le panier.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)

            Button("Recommencer") {
                withAnimation(Theme.Motion.pill) {
                    kept.removeAll()
                }
            }
            .buttonStyle(.bordered)
            .tint(Theme.flare)
            .padding(.top, 6)
        }
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity)
    }
}
