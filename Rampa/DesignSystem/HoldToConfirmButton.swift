import SwiftUI

/// The last rail before anything leaves the library.
///
/// A tap is not enough: the user presses and holds while a ring closes over the
/// button. Releasing early cancels, with no state change and no penalty. This is
/// deliberately slower than a normal button — it is the point.
struct HoldToConfirmButton: View {
    let title: String
    let holdingTitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    /// How long the ring takes to close. Long enough to be a decision.
    private let duration: Double = 1.4

    @State private var progress: CGFloat = 0
    @State private var isHolding = false
    @State private var didFire = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Track
            Capsule(style: .continuous)
                .fill(tint.opacity(0.16))

            // Fill that grows with the hold
            GeometryReader { proxy in
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.30))
                    .frame(width: proxy.size.width * progress)
            }
            .clipShape(Capsule(style: .continuous))

            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(isHolding ? holdingTitle : title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(tint)
            .contentTransition(.opacity)
        }
        .frame(height: 54)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        }
        .contentShape(Capsule(style: .continuous))
        .gesture(holdGesture)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityHint("Appuyez et maintenez pour confirmer.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isHolding else { return }
                beginHold()
            }
            .onEnded { _ in
                cancelHold()
            }
    }

    private func beginHold() {
        isHolding = true
        didFire = false

        withAnimation(.linear(duration: duration)) {
            progress = 1
        }

        // The ring closing is the confirmation; `progress` reaching 1 is what
        // fires, so a cancelled animation can never delete anything.
        Task {
            try? await Task.sleep(for: .seconds(duration))
            guard isHolding, !Task.isCancelled else { return }
            didFire = true
            action()
            cancelHold()
        }
    }

    private func cancelHold() {
        guard !didFire else {
            isHolding = false
            return
        }
        isHolding = false
        withAnimation(.easeOut(duration: 0.18)) {
            progress = 0
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HoldToConfirmButton(
            title: "Glisser vers le panier",
            holdingTitle: "Continuez…",
            symbol: "trash",
            tint: Theme.flare
        ) {}
        HoldToConfirmButton(
            title: "Supprimer définitivement",
            holdingTitle: "Relâchez pour annuler",
            symbol: "exclamationmark.triangle",
            tint: Theme.danger
        ) {}
    }
    .padding()
}
