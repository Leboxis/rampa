import SwiftUI

/// Automated cleanup proposals.
///
/// Every group is a *suggestion* with its reason stated. Nothing here deletes:
/// the worst a button can do is stage items into the bin.
struct CleanupScreen: View {
    @Environment(AppState.self) private var state

    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header

            if state.cleanupGroups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(state.cleanupGroups) { group in
                            CleanupCard(
                                group: group,
                                isExpanded: expanded.contains(group.id),
                                onToggle: {
                                    withAnimation(Theme.Motion.pill) {
                                        if expanded.contains(group.id) {
                                            expanded.remove(group.id)
                                        } else {
                                            expanded.insert(group.id)
                                        }
                                    }
                                },
                                onStage: {
                                    withAnimation(Theme.Motion.pill) {
                                        state.stage(group.items)
                                    }
                                }
                            )
                        }

                        Color.clear.frame(height: 110)
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task {
            await state.library.start()
            recompute()
        }
        .task(id: state.library.items.count) {
            recompute()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tri automatique")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            Text("Des propositions, jamais des décisions. Rien ne part sans votre accord.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.flare)
            Text("Rien à proposer")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("Aucun groupe ne ressort pour l'instant : pas de captures anciennes, pas de rafales, pas d'images minuscules.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity)
    }

    private func recompute() {
        let items = state.library.items
        guard !items.isEmpty else {
            state.cleanupGroups = []
            return
        }
        let staged = Set(state.bin.staged.map(\.id))
        let groups = MediaAnalyzer.cleanupSuggestions(items)
            .map { group in
                CleanupGroup(
                    id: group.id,
                    title: group.title,
                    reason: group.reason,
                    symbol: group.symbol,
                    items: group.items.filter { !staged.contains($0.id) }
                )
            }
            .filter { !$0.items.isEmpty }

        withAnimation(Theme.Motion.pill) {
            state.cleanupGroups = groups
        }
    }
}

// MARK: - Card

private struct CleanupCard: View {
    let group: CleanupGroup
    let isExpanded: Bool
    let onToggle: () -> Void
    let onStage: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: group.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.flare)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(group.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(group.items.count)")
                                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Theme.flare)
                        }

                        Text(group.reason)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.inkSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(.top, 3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(group.items.prefix(25)) { item in
                        SquareThumbnail(assetID: item.id, cornerRadius: 6)
                    }
                }

                if group.items.count > 25 {
                    Text("+ \(group.items.count - 25) autres")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                }

                Button(action: onStage) {
                    HStack(spacing: 7) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Mettre les \(group.items.count) au panier")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Theme.flare)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.flare.opacity(0.12), in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Theme.flare.opacity(0.3), lineWidth: 1)
                    }
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }
}
