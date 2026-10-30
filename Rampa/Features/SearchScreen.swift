import SwiftUI

/// Search over the facts a person can actually recall about a photo.
///
/// PhotoKit exposes no content, caption or place text to third-party apps, so
/// the app searches what it legitimately has: date, month, year, kind, size
/// bucket, screenshots and favourites. The screen says so instead of letting
/// people type "plage" and get nothing without explanation.
///
/// Results use the same `MediaGrid` as the library, so tapping one opens the
/// viewer with the same actions, and the same long-press menu.
struct SearchScreen: View {
    @Environment(AppState.self) private var state

    @State private var query = ""
    @State private var results: [MediaItem] = []
    @FocusState private var focused: Bool

    /// Filters that the query alone cannot express, so the user does not have
    /// to guess the magic word.
    @State private var filters: Set<SearchFilter> = []

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Recherche") {
                if !results.isEmpty {
                    HeaderCount(value: results.count, suffix: "résultats")
                }
            }

            searchField
            filterRow
            content
        }
        .task { await state.library.start() }
        .task(id: searchKey) { await search() }
    }

    private var searchKey: String {
        [
            query,
            String(state.library.revision),
            filters.map(\.rawValue).sorted().joined(separator: ",")
        ].joined(separator: "|")
    }

    // MARK: Field

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)

            TextField("Mois, année, vidéo, capture…", text: $query)
                .focused($focused)
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(focused ? Theme.flare.opacity(0.5) : Theme.hairline, lineWidth: 1)
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .animation(.smooth(duration: 0.2), value: query.isEmpty)
    }

    private var filterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(SearchFilter.allCases) { filter in
                    Chip(
                        title: filter.title,
                        symbol: filter.symbol,
                        isOn: filters.contains(filter)
                    ) {
                        withAnimation(.smooth(duration: 0.2)) {
                            if filters.contains(filter) {
                                filters.remove(filter)
                            } else {
                                filters.insert(filter)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 10)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if query.isEmpty && filters.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Essayez")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)

                    FlowLayout(spacing: 8) {
                        ForEach(Self.suggestions, id: \.self) { suggestion in
                            Button {
                                query = suggestion
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.flare)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Theme.flare.opacity(0.10), in: Capsule(style: .continuous))
                            }
                            .buttonStyle(PressScaleStyle())
                        }
                    }

                    Text("La recherche porte sur la date, le mois, l'année, le type, la taille, les captures d'écran et les favoris. Apple ne donne pas accès au contenu des images, donc « plage » ne trouvera rien — et l'app vous le dit plutôt que de faire semblant.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Metrics.gutter)
            }
            .scrollIndicators(.hidden)

        } else if results.isEmpty {
            EmptyStateView(
                symbol: "magnifyingglass",
                title: "Aucun résultat",
                message: "Essayez un mois, une année, « vidéo » ou « capture écran ».",
                tint: Theme.inkSecondary
            )
            .frame(maxHeight: .infinity)

        } else {
            ScrollView {
                MediaGrid(items: results, tab: .search)
                    .padding(.top, 2)

                ScrollBottomInset()
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private static let suggestions = [
        "vidéo", "capture écran", "favori", "2025", "cette année", "xxl"
    ]

    // MARK: Search

    private func search() async {
        let text = query
        let activeFilters = filters

        guard !text.trimmingCharacters(in: .whitespaces).isEmpty || !activeFilters.isEmpty else {
            results = []
            return
        }

        let items = state.browsableItems

        let found = await Task.detached(priority: .userInitiated) {
            // Filters first (cheap predicates), then the text search over what
            // survives — the other order would run the expensive string build
            // on assets a chip was about to exclude.
            let filtered = SearchFilter.apply(activeFilters, to: items)
            return MediaAnalyzer.search(filtered, query: text)
        }.value

        guard !Task.isCancelled else { return }
        results = found
    }
}

// MARK: - Filters

/// Toggles for the facets a person can actually name, so search does not depend
/// on remembering the vocabulary.
enum SearchFilter: String, CaseIterable, Identifiable, Sendable {
    case favorite
    case screenshot
    case video
    case photo
    case large
    case thisYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorite: "Favoris"
        case .screenshot: "Captures"
        case .video: "Vidéos"
        case .photo: "Photos"
        case .large: "Lourdes"
        case .thisYear: "Cette année"
        }
    }

    var symbol: String {
        switch self {
        case .favorite: "heart.fill"
        case .screenshot: "camera.viewfinder"
        case .video: "video.fill"
        case .photo: "photo.fill"
        case .large: "arrow.up.right"
        case .thisYear: "calendar"
        }
    }

    nonisolated static func apply(_ filters: Set<SearchFilter>, to items: [MediaItem]) -> [MediaItem] {
        guard !filters.isEmpty else { return items }
        let year = Calendar.current.component(.year, from: .now)

        return items.filter { item in
            filters.allSatisfy { filter in
                switch filter {
                case .favorite: item.isFavorite
                case .screenshot: item.isScreenCapture
                case .video: item.isVideo
                case .photo: !item.isVideo
                case .large: item.megapixels >= 12
                case .thisYear:
                    Calendar.current.component(.year, from: item.creationDate) == year
                }
            }
        }
    }
}

// MARK: - Layout

/// A wrapping stack for the suggestion chips. `LazyVGrid` cannot do variable
/// width chips, and this is a handful of views, so a simple `Layout` is enough.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
