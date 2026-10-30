import SwiftUI

/// The library: every asset, grouped by month, year, size or type.
struct LibraryScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.displayScale) private var displayScale

    /// Derived sections. Computed in a `.task` keyed on the inputs, never in
    /// `body` — grouping 20k assets on every keystroke of the tab bar would
    /// drop frames.
    @State private var sections: [MediaSection] = []

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 2),
        count: 4
    )

    var body: some View {
        VStack(spacing: 0) {
            header

            switch state.library.access {
            case .unknown:
                ProgressView().frame(maxHeight: .infinity)
            case .denied:
                PermissionWall()
            default:
                content
            }
        }
        .task {
            await state.library.start()
            await recompute()
        }
        .task(id: state.library.items.count) {
            await recompute()
        }
        .task(id: state.grouping) {
            await recompute()
        }
        .task(id: state.sort) {
            await recompute()
        }
        .task(id: state.bin.staged.count) {
            await recompute()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bibliothèque")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)

                Spacer()

                Text("\(state.browsableItems.count)")
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.inkSecondary)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 8) {
                ForEach(Grouping.allCases) { option in
                    GroupChip(
                        title: option.title,
                        symbol: option.symbol,
                        isOn: state.grouping == option
                    ) {
                        withAnimation(Theme.Motion.pill) {
                            state.grouping = option
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                if state.library.isLimited {
                    LimitedBanner()
                        .padding(.horizontal, 16)
                }

                if sections.isEmpty {
                    EmptyLibrary()
                        .padding(.top, 60)
                }

                ForEach(sections) { section in
                    Section {
                        grid(for: section.items)
                    } header: {
                        SectionHeader(section: section)
                    }
                }

                // Room for the floating bar so the last row is reachable.
                Color.clear.frame(height: 110)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func grid(for items: [MediaItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(items) { item in
                Button {
                    if state.isSelecting {
                        withAnimation(.smooth(duration: 0.2)) {
                            state.toggleSelection(item.id)
                        }
                    } else {
                        state.stage([item])
                    }
                } label: {
                    MediaCell(
                        item: item,
                        isStaged: false,
                        isSelected: state.selected.contains(item.id),
                        selectionMode: state.isSelecting
                    )
                }
                .buttonStyle(.plain)
                .onAppear {
                    prefetchNeighbours(of: item, in: items)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    /// Warms the next two dozen thumbnails so a fast scroll does not outrun
    /// the decoder.
    private func prefetchNeighbours(of item: MediaItem, in items: [MediaItem]) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let upper = min(index + 24, items.count)
        guard upper > index + 1 else { return }
        let ids = items[(index + 1)..<upper].map(\.id)
        ThumbnailLoader.shared.prefetch(ids: ids, target: .grid, scale: displayScale)
    }

    // MARK: Derivation

    private func recompute() async {
        let items = state.browsableItems
        let grouping = state.grouping
        let sort = state.sort

        let result = await Task.detached(priority: .userInitiated) {
            MediaAnalyzer.sections(items, by: grouping, sort: sort)
        }.value

        withAnimation(Theme.Motion.pill) {
            sections = result
        }
    }
}

// MARK: - Pieces

/// A pill toggle for the grouping axis.
private struct GroupChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isOn ? Theme.flare : Theme.inkSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(isOn ? Theme.flare.opacity(0.14) : Color.clear)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isOn ? Theme.flare.opacity(0.4) : Theme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// A pinned month/size header.
private struct SectionHeader: View {
    let section: MediaSection

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(section.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Spacer()

            Text(section.caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

/// Shown when the user granted limited library access.
private struct LimitedBanner: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "photo.badge.checkmark")
                    .foregroundStyle(Theme.flare)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accès limité")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Vous ne voyez qu'une partie de votre photothèque.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(12)
            .background(Theme.flare.opacity(0.10), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// Shown when the library genuinely has nothing in it.
private struct EmptyLibrary: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.flare)
            Text("Aucune photo.")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("Votre photothèque apparaîtra ici dès qu'elle contiendra quelque chose.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}

/// Shown when access was refused, with a way to fix it.
struct PermissionWall: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)

            Text("Accès refusé")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)

            Text("Rampa a besoin de lire votre photothèque pour la trier. Autorisez l'accès dans Réglages.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)

            Button("Ouvrir Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.flare)
            .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity)
    }
}
