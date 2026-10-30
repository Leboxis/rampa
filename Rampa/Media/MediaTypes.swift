import Foundation

/// How the library is grouped into sections.
enum Grouping: String, CaseIterable, Identifiable, Sendable {
    case month
    case year
    case size
    case type

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: "Mois"
        case .year: "Année"
        case .size: "Taille"
        case .type: "Type"
        }
    }

    var symbol: String {
        switch self {
        case .month: "calendar"
        case .year: "calendar.badge.clock"
        case .size: "arrow.up.arrow.down.square"
        case .type: "square.on.square"
        }
    }
}

/// A titled group of assets, ready for a `Section`.
struct MediaSection: Identifiable, Sendable {
    let id: String
    let title: String
    /// Short right-aligned caption: a count, or a size range.
    let caption: String
    let items: [MediaItem]
}

/// Sort order inside a section.
enum SortOrder: String, CaseIterable, Identifiable, Sendable {
    case newest
    case oldest
    case largest
    case smallest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Plus récentes"
        case .oldest: "Plus anciennes"
        case .largest: "Plus lourdes"
        case .smallest: "Plus légères"
        }
    }

    /// What the sort control shows once picked.
    var shortTitle: String {
        switch self {
        case .newest: "Récent"
        case .oldest: "Ancien"
        case .largest: "Lourd"
        case .smallest: "Léger"
        }
    }

    var symbol: String {
        switch self {
        case .newest: "arrow.down"
        case .oldest: "arrow.up"
        case .largest: "arrow.up.right"
        case .smallest: "arrow.down.left"
        }
    }
}
