import SwiftUI
import WKCore
import WKDesign

/// El paywall cuando se abre desde dentro de la app.
///
/// Reutiliza el del onboarding, pero encabezado por **el motivo concreto** que
/// lo ha abierto. Un muro genérico obliga al usuario a adivinar qué acaba de
/// pasar; decirle "has llegado a 25 prendas" convierte el bloqueo en
/// información.
struct PaywallSheet: View {
    let feature: Feature?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if let feature {
                VStack(spacing: WK.Spacing.xs) {
                    Text(feature.lockedTitle)
                        .font(.system(.title3, weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text(feature.lockedDetail)
                        .font(.subheadline)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.top, WK.Spacing.xl)
            }

            PaywallStep { dismiss() }
        }
        .background(WK.Palette.canvas)
    }
}

/// Engancha el paywall a una pantalla.
///
/// Un solo sitio donde se presenta: si cada pantalla lo abriera a su manera,
/// acabarían difiriendo en detents, en animación y en si se puede descartar.
extension View {
    func featureGatePaywall(_ gate: FeatureGate) -> some View {
        sheet(isPresented: Binding(
            get: { gate.isPresentingPaywall },
            set: { gate.isPresentingPaywall = $0 }
        )) {
            PaywallSheet(feature: gate.pendingFeature)
        }
    }
}
