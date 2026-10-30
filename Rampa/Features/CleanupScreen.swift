import SwiftUI

/// Automated cleanup proposals.
///
/// Every group is a *suggestion* with its reason stated. Nothing here deletes:
/// the worst a button can do is stage items into the trash, and even that is
/// undoable.
struct CleanupScreen: View {
    @Environment(AppState.self) private var state

    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Tri automatique",
                subtitle: "Des propositions, jamais des décisions. Rien ne part sans votre accord."
            )

            if state.cleanupGroups.isEmpty {
                EmptyStateView(
                    symbol: "sparkles",
                    title: "Rien à proposer",
                    message: "Aucun groupe ne ressort pour l'instant : pas de captures anciennes, pas de rafales, pas d'images minuscules."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(state.cleanupGroups) { group in
                            CleanupCard(
                                group: group,
                                tab: .cleanup,
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

                        ScrollBottomInset()
                    }
                    .padding(.horizontal, Theme.Metrics.gutter)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task {
            await state.library.start()
        }
        .task(id: recomputeKey) {
            recompute()
        }
    }

    /// The staged set is folded in by identity rather than by count: swapping
    /// one staged photo for another leaves the count identical but changes what
    /// the proposals should contain.
    private var recomputeKey: String {
        "\(state.library.revision)|\(state.trash.staged.map(\.id).sorted().joined(separator: ","))"
    }

    private func recompute() {
        let items = state.library.items
        guard !items.isEmpty else {
            if !state.cleanupGroups.isEmpty {
                withAnimation(Theme.Motion.pill) { state.cleanupGroups = [] }
            }
            return
        }

        let staged = Set(state.trash.staged.map(\.id))
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

/// One proposal. Collapsed it states the reason and the count; expanded it
/// shows the actual photos, each of which can be opened, so "les 42 captures
/// d'écran" is never a number you have to take on faith.
private struct CleanupCard: View {
    let group: CleanupGroup
    let tab: AppTab
    let isExpanded: Bool
    let onToggle: () -> Void
    let onStage: () -> Void

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
            .accessibilityHint(isExpanded ? "Replier le groupe" : "Déplier le groupe")

            if isExpanded {
                MediaGrid(items: Array(group.items.prefix(24)), tab: tab, columns: 5)

                if group.items.count > 24 {
                    Text("+ \(group.items.count - 24) autres")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                }

                Button(action: onStage) {
                    HStack(spacing: 7) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Mettre les \(group.items.count) à la corbeille")
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
