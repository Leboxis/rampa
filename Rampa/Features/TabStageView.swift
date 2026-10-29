import SwiftUI

/// The screen behind each tab. Intentionally empty: Rampa ships as the shell,
/// with navigation and motion complete and no content yet.
struct TabStageView: View {
    let tab: AppTab

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: tab.symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.flare)

            Text(tab.headline)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)

            Text(tab.invitation)
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
