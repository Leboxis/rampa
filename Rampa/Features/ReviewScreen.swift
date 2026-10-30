import SwiftUI

/// Swipe triage. One asset at a time, big, with a physical gesture per verdict.
///
/// The deck never deletes. "Mettre au panier" is just a different bucket from
/// "Garder", and both are one flick away from being undone.
///
/// The deck now shows the whole photo. It used to use `.scaledToFill()` inside
/// an explicit frame, which cropped every portrait shot to a square in the one
/// screen whose entire job is looking at a photo carefully.
struct ReviewScreen: View {
    @Environment(AppState.self) private var state

    @State private var drag: CGSize = .zero
    @State private var kept: Set<MediaItem.ID> = []
    @State private var deciding = false
    @State private var queue: [MediaItem] = []

    /// Distance past which a flick commits.
    private let threshold: CGFloat = 110

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
        .task(id: queueKey) { rebuildQueue() }
    }

    /// The deck used to rebuild its queue inside a computed property, which
    /// meant filtering the whole library on every frame of a drag. It is built
    /// once per input change instead.
    ///
    /// `kept` is folded in by identity, not by count: "Garder" on one card and
    /// a change elsewhere can leave the count identical while the queue
    /// genuinely differs.
    private var queueKey: String {
        [
            String(state.library.revision),
            state.bin.staged.map(\.id).sorted().joined(separator: ","),
            kept.sorted().joined(separator: ",")
        ].joined(separator: "|")
    }

    // MARK: Header

    private var header: some View {
        ScreenHeader(title: "Revue") {
            HeaderCount(value: queue.count, suffix: "restantes")
        }
    }

    // MARK: Deck

    private var deck: some View {
        GeometryReader { proxy in
            ZStack {
                // The next two cards, stacked behind, so the deck has depth and
                // a swipe feels like it is revealing something. The order is
                // reversed so index 0 is drawn last, on top.
                ForEach(Array(queue.prefix(3).enumerated()).reversed(), id: \.element.id) { index, item in
                    card(item, index: index, size: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func card(_ item: MediaItem, index: Int, size: CGSize) -> some View {
        let isTop = index == 0
        let offset = isTop ? drag : .zero
        let rotation = isTop ? Double(drag.width / 22) : 0
        let verdict = verdict(for: offset.width)

        return ZStack {
            // A dark card behind the photo, so a letterboxed portrait still
            // reads as a deliberate frame rather than a hole.
            Color.black.opacity(0.82)

            ThumbnailView(assetID: item.id, target: .deck, fill: .fit)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottom) {
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
        }
        .overlay(alignment: .topLeading) {
            if let duration = item.durationText {
                Text(duration)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(12)
            }
        }
        .overlay(alignment: .topTrailing) {
            if item.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.danger)
                    .padding(8)
                    .background(.black.opacity(0.4), in: Circle())
                    .padding(10)
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
        .highPriorityGesture(isTop ? swipe : nil)
        .onTapGesture {
            // Looking closer is a legitimate thing to want mid-review, and it
            // does not change the verdict.
            if isTop { state.openViewer(item) }
        }
        .accessibilityElement()
        .accessibilityLabel(item.isVideo ? "Vidéo" : "Photo")
        .accessibilityValue(item.creationDate.formatted(date: .abbreviated, time: .shortened))
        .accessibilityHint("Glissez à gauche pour mettre au panier, à droite pour garder.")
        .accessibilityAction(named: "Afficher en grand") {
            state.openViewer(item)
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !deciding else { return }
                drag = value.translation
            }
            .onEnded { value in
                commit(value.translation.width)
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

    /// Applies one verdict.
    ///
    /// The verdict is deliberately *not* applied when the finger lifts. Staging
    /// the asset immediately removes it from `queue`, so the next card becomes
    /// index 0 while `drag` is still at the fly-out offset — it would inherit
    /// that offset and appear to be dismissed too, which is what made a single
    /// swipe skip several media. So: fly the card out first, then clear the
    /// drag and change state together, without animation.
    private func commit(_ translation: CGFloat) {
        guard let top = queue.first, !deciding else { return }

        guard translation.magnitude >= threshold else {
            // Not far enough: spring back, no state change.
            withAnimation(.smooth(duration: 0.3, extraBounce: 0.15)) {
                drag = .zero
            }
            return
        }

        deciding = true
        let toBin = translation < 0

        withAnimation(.smooth(duration: 0.22, extraBounce: 0)) {
            drag = CGSize(width: toBin ? -600 : 600, height: 0)
        }

        Task {
            try? await Task.sleep(for: .milliseconds(230))
            guard !Task.isCancelled else { return }

            // One transaction: reset the offset and apply the verdict together,
            // so the incoming card starts at rest.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                drag = .zero
                if toBin {
                    state.stage([top])
                } else {
                    kept.insert(top.id)
                }
                queue.removeFirst()
            }
            deciding = false
        }
    }

    // MARK: Queue

    private func rebuildQueue() {
        let staged = Set(state.bin.staged.map(\.id))
        queue = state.library.items.filter {
            !staged.contains($0.id) && !kept.contains($0.id)
        }
    }

    // MARK: Empty

    private var finishedState: some View {
        EmptyStateView(
            symbol: "checkmark.seal.fill",
            title: "Revue terminée",
            message: "Vous avez passé toute la bibliothèque en revue. Les éléments mis de côté vous attendent dans le panier.",
            action: .init(title: "Recommencer") {
                withAnimation(Theme.Motion.pill) {
                    kept.removeAll()
                }
            }
        )
        .frame(maxHeight: .infinity)
    }
}
