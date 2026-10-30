import SwiftUI

/// Search over the facts a person can actually recall about a photo.
///
/// PhotoKit exposes no content, caption or place text to third-party apps, so
/// the app searches what it legitimately has: date, month, year, kind, size
/// bucket, screenshots and favourites. The screen says so instead of letting
/// people type "plage" and get nothing without explanation.
struct SearchScreen: View {
    @Environment(AppState.self) private var state

    @State private var query = ""
    @State private var results: [MediaItem] = []
    @FocusState private var focused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    /// Chips that fill the field with something that will actually match.
    private let suggestions = [
        "vidéo", "capture écran", "favori", "2025", "cette année", "xxl"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            body_
        }
        .task { await state.library.start() }
        .task(id: query) { await search() }
    }

    private var header: some View {
        Text("Recherche")
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
    }

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
        .padding(.horizontal, 16)
        .animation(.smooth(duration: 0.2), value: query.isEmpty)
    }

    @ViewBuilder
    private var body_: some View {
        if query.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Essayez")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)

                    FlowLayout(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
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
                .padding(16)
            }
            .scrollIndicators(.hidden)
        } else if results.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Text("Aucun résultat")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("Essayez un mois, une année, « vidéo » ou « capture écran ».")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("\(results.count) résultat\(results.count > 1 ? "s" : "")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .contentTransition(.numericText())
                        .padding(.horizontal, 16)

                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(results) { item in
                            Button {
                                state.stage([item])
                            } label: {
                                MediaCell(
                                    item: item,
                                    isStaged: false,
                                    isSelected: false,
                                    selectionMode: false
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)

                    Color.clear.frame(height: 110)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func search() async {
        let text = query
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        let items = state.browsableItems

        let found = await Task.detached(priority: .userInitiated) {
            MediaAnalyzer.search(items, query: text)
        }.value

        guard !Task.isCancelled else { return }
        withAnimation(Theme.Motion.pill) {
            results = found
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
