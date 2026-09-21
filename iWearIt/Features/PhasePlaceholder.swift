import SwiftUI
import WKDesign

/// Marcador de contenido pendiente. Existe para que el andamiaje de F0 sea
/// verificable sin fingir funcionalidad que aún no está.
struct PhasePlaceholder: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(WK.Palette.accent)
            Text(title).font(WK.Font.shelfTitle)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(WK.Palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(WK.Spacing.xl)
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
