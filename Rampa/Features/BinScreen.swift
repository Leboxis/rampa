import LocalAuthentication
import SwiftUI

/// The bin. Nothing leaves the library until this screen says so, and this
/// screen requires a hold and a biometric check before it will.
///
/// Two things changed here. The old bin un-staged on a single tap, so a photo
/// was one stray finger away from leaving the bin; it now opens in the viewer
/// like everywhere else, with a clear "Retirer du panier" action. And "Vider"
/// was a one-way door — it is now undoable, like every other staging action.
struct BinScreen: View {
    @Environment(AppState.self) private var state

    @State private var showConfirm = false
    @State private var authError: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            if state.bin.staged.isEmpty {
                EmptyStateView(
                    symbol: "tray",
                    title: "Panier vide",
                    message: "Mettez des photos de côté depuis la bibliothèque, la revue ou le tri automatique.",
                    tint: Theme.inkSecondary
                )
                .frame(maxHeight: .infinity)
            } else {
                content
            }
        }
        .sheet(isPresented: $showConfirm) {
            ConfirmDeletionSheet(
                count: state.bin.staged.count,
                onCancel: { showConfirm = false },
                onConfirm: { Task { await commit() } }
            )
            .presentationDetents([.height(380)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
        }
        .alert(
            "Suppression impossible",
            isPresented: Binding(
                get: { authError != nil },
                set: { if !$0 { authError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { authError = nil }
        } message: {
            Text(authError ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        ScreenHeader(title: "Panier", subtitle: explainer) {
            if !state.bin.staged.isEmpty {
                Button("Vider") {
                    withAnimation(Theme.Motion.pill) {
                        state.unstageAll()
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private var explainer: String {
        let count = state.bin.staged.count
        guard count > 0 else {
            return "Les éléments que vous mettez de côté arrivent ici. Rien n'est supprimé tant que vous ne confirmez pas."
        }
        return "\(count) élément\(count > 1 ? "s" : "") en attente. La suppression passe par votre Face ID et Apple garde une copie 30 jours dans « Récents supprimés »."
    }

    // MARK: Content

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    MediaGrid(items: state.bin.staged, tab: .bin)

                    ScrollBottomInset()
                }
            }
            .scrollIndicators(.hidden)

            commitBar
        }
    }

    private var commitBar: some View {
        VStack(spacing: 8) {
            HoldToConfirmButton(
                title: "Maintenir pour supprimer",
                holdingTitle: "Continuez…",
                symbol: "trash",
                tint: Theme.danger
            ) {
                showConfirm = true
            }
            .disabled(state.bin.isWorking)

            Text("Vos éléments partent dans « Récents supprimés », pas dans le néant.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 20)
        // The stage already ends above the floating bar; the old extra 20 pt
        // here was padding the button away from nothing.
        .padding(.bottom, 4)
    }

    // MARK: Commit

    /// Third rail: biometrics. The app asks the system to confirm the human is
    /// present before it touches the library at all.
    private func commit() async {
        showConfirm = false

        let context = LAContext()
        context.localizedCancelTitle = "Annuler"
        context.localizedFallbackTitle = "Utiliser le code"

        var error: NSError?
        let policy = LAPolicy.deviceOwnerAuthentication

        guard context.canEvaluatePolicy(policy, error: &error) else {
            // No biometrics and no passcode set. Do not silently downgrade the
            // guard — refuse and say why.
            authError = "Aucun code ni Face ID n'est configuré sur cet appareil. Configurez-en un dans Réglages pour pouvoir supprimer."
            return
        }

        do {
            let ok = try await context.evaluatePolicy(
                policy,
                localizedReason: "Confirmer la suppression de \(state.bin.staged.count) élément(s) de votre photothèque."
            )
            guard ok else { return }
        } catch {
            // A cancel is not an error worth a dialog.
            return
        }

        let removed = await state.bin.commit()
        if let message = state.bin.errorMessage {
            authError = message
            state.bin.clearError()
        } else {
            withAnimation(Theme.Motion.pill) {
                state.applyRemoval(removed)
            }
        }
    }
}

// MARK: - Confirmation sheet

/// The plain-language summary shown before the biometric prompt. It states the
/// count, what will happen, and where the items go.
private struct ConfirmDeletionSheet: View {
    let count: Int
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Theme.danger)
                .padding(.top, 24)

            Text("Supprimer \(count) élément\(count > 1 ? "s" : "") ?")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)

            Text("Ils quitteront votre photothèque et iront dans « Récents supprimés », où Apple les conserve 30 jours. Vous pourrez les y récupérer pendant ce délai.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: onConfirm) {
                    Text("Continuer")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.danger, in: Capsule(style: .continuous))
                }
                .buttonStyle(PressScaleStyle())

                Button(action: onCancel) {
                    Text("Annuler")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.ink.opacity(0.06), in: Capsule(style: .continuous))
                }
                .buttonStyle(PressScaleStyle())
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
    }
}
