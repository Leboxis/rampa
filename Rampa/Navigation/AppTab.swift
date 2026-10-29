import SwiftUI

/// The five destinations of the app.
///
/// The order of the cases *is* the order of the bar, so `rawValue` doubles as
/// the horizontal index the selection pill travels to.
enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case home
    case flow
    case create
    case pulse
    case vault

    var id: Int { rawValue }

    /// Bar label. Kept to one word so it never wraps under the glyph.
    var title: String {
        switch self {
        case .home: "Accueil"
        case .flow: "Flux"
        case .create: "Créer"
        case .pulse: "Pulse"
        case .vault: "Coffre"
        }
    }

    /// SF Symbol drawn in the bar. All five are filled for a consistent weight.
    var symbol: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .flow: "waveform.path.ecg"
        case .create: "plus"
        case .pulse: "bolt.fill"
        case .vault: "lock.fill"
        }
    }

    /// One-line title for the screen's empty state.
    var headline: String {
        switch self {
        case .home: "Rien encore."
        case .flow: "Le flux est vide."
        case .create: "Commencez par un geste."
        case .pulse: "Aucun signal."
        case .vault: "Le coffre est fermé."
        }
    }

    /// The sentence that invites the next action.
    var invitation: String {
        switch self {
        case .home: "Ce que vous ajouterez apparaîtra ici."
        case .flow: "Les nouveautés arriveront au fil de l'eau."
        case .create: "Vos créations se rangeront à cet endroit."
        case .pulse: "L'activité s'affichera dès le premier événement."
        case .vault: "Vos éléments protégés vivront ici."
        }
    }
}
