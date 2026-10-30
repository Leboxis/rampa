import SwiftUI

/// The five destinations of the app.
///
/// The order of the cases *is* the order of the bar, so `rawValue` doubles as
/// the horizontal index the selection lens travels to.
enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case library
    case review
    case cleanup
    case search
    case bin

    var id: Int { rawValue }

    /// Bar label. One word each so it never wraps under the glyph.
    var title: String {
        switch self {
        case .library: "Photos"
        case .review: "Revue"
        case .cleanup: "Trier"
        case .search: "Chercher"
        case .bin: "Panier"
        }
    }

    /// SF Symbol drawn in the bar.
    var symbol: String {
        switch self {
        case .library: "square.grid.2x2.fill"
        case .review: "rectangle.stack.fill"
        case .cleanup: "wand.and.sparkles"
        case .search: "magnifyingglass"
        case .bin: "trash.fill"
        }
    }

    /// Screen heading.
    var headline: String {
        switch self {
        case .library: "Bibliothèque"
        case .review: "Revue"
        case .cleanup: "Tri automatique"
        case .search: "Recherche"
        case .bin: "Panier"
        }
    }
}
