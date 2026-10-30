import SwiftUI

/// The library: every asset, grouped by month, year, size or type.
///
/// A tap opens the viewer, a long press opens the cell's menu, and the header's
/// trailing menu switches the sort. Before this, a tap staged the photo for
/// deletion and the sort order was unreachable — `state.sort` existed but no
/// control ever wrote to it.
struct LibraryScreen: View {
    @Environment(AppState.self) private var state

    /// Derived sections. Computed in a `.task` keyed on the inputs, never in
    /// `body` — grouping 20 000 assets on every keystroke of the tab bar would
    /// drop frames.
    @State private var sections: [MediaSection] = []

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
            // Only the permission/fetch bootstrap here. Deriving the sections
            // is `.task(id:)`'s job, and doing it in both places ran the whole
            // grouping twice on launch.
            await state.library.start()
        }
        // One key for every input that changes the sections. Three separate
        // `.task(id:)` modifiers used to run `recompute()` concurrently on
        // launch and race to assign the result.
        .task(id: derivationKey) {
            await recompute()
        }
    }

    /// Everything `recompute()` depends on, in one comparable value.
    ///
    /// The staged set is folded in by identity, not by count: staging one photo
    /// while another leaves the bin keeps the count identical but changes which
    /// assets are browsable.
    private var derivationKey: String {
        [
            String(state.library.revision),
            state.grouping.rawValue,
            state.sort.rawValue,
            state.bin.staged.map(\.id).sorted().joined(separator: ",")
        ].joined(separator: "|")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(title: "Bibliothèque") {
                HStack(spacing: 10) {
                    sortMenu
                    HeaderCount(value: state.browsableCount)
                }
            }

            HStack(spacing: 8) {
                ForEach(Grouping.allCases) { option in
                    Chip(
                        title: option.title,
                        symbol: option.symbol,
                        isOn: state.grouping == option
                    ) {
                        withAnimation(Theme.Motion.pill) {
                            state.grouping = option
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Metrics.gutter)
        }
        .padding(.bottom, 10)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Trier par", selection: sortBinding) {
                ForEach(SortOrder.allCases) { order in
                    Label(order.title, systemImage: order.symbol)
                        .tag(order)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: state.sort.symbol)
                    .font(.system(size: 11, weight: .bold))
                Text(state.sort.shortTitle)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.ink.opacity(0.05), in: Capsule(style: .continuous))
        }
        .accessibilityLabel("Trier : \(state.sort.title)")
    }

    private var sortBinding: Binding<SortOrder> {
        Binding(
            get: { state.sort },
            set: { newValue in
                withAnimation(Theme.Motion.pill) { state.sort = newValue }
            }
        )
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                if state.library.isLimited {
                    LimitedBanner()
                        .padding(.horizontal, Theme.Metrics.gutter)
                }

                if sections.isEmpty {
                    EmptyStateView(
                        symbol: "photo.on.rectangle.angled",
                        title: "Aucune photo.",
                        message: "Votre photothèque apparaîtra ici dès qu'elle contiendra quelque chose."
                    )
                    .padding(.top, 40)
                    .padding(.bottom, 40)
                }

                ForEach(sections) { section in
                    Section {
                        MediaGrid(items: section.items, tab: .library)
                    } header: {
                        SectionHeader(title: section.title, caption: section.caption)
                    }
                }

                ScrollBottomInset()
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: Derivation

    private func recompute() async {
        let items = state.browsableItems
        let grouping = state.grouping
        let sort = state.sort

        let result = await Task.detached(priority: .userInitiated) {
            MediaAnalyzer.sections(items, by: grouping, sort: sort)
        }.value

        guard !Task.isCancelled else { return }
        sections = result
    }
}

// MARK: - Pieces

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

/// Shown when access was refused, with a way to fix it.
struct PermissionWall: View {
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        EmptyStateView(
            symbol: "lock.shield",
            title: "Accès refusé",
            message: "Rampa a besoin de lire votre photothèque pour la trier. Autorisez l'accès dans Réglages.",
            tint: Theme.inkSecondary,
            action: .init(title: "Ouvrir Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        )
        .frame(maxHeight: .infinity)
        .task(id: scenePhase) {
            // Returning from Settings used to leave this wall up even after
            // access had been granted.
            guard scenePhase == .active else { return }
            await state.library.refreshAccess()
        }
    }
}
