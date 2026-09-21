import SwiftUI
import WKDesign

/// El paywall del final del onboarding.
///
/// **Blando a propósito.** La app tiene plan gratuito con límites, así que
/// "Seguir gratis" es una opción legítima y se muestra como tal: un botón
/// visible y al lado del otro, no un enlace diminuto en gris al fondo.
///
/// El motivo no es solo ético. Un paywall duro al final de un onboarding largo
/// convierte a quien ya iba a pagar y pierde a todo el resto, incluida la gente
/// que habría pagado más adelante, una vez la app le hubiera demostrado algo.
///
/// - Note: precios de ejemplo. Los reales llegan de RevenueCat en F9.
struct PaywallStep: View {
    let onFinish: () -> Void

    @State private var plan: Plan = .yearly

    enum Plan: String, CaseIterable, Identifiable {
        case yearly, monthly
        var id: String { rawValue }

        var title: String {
            switch self {
            case .yearly: "Anual"
            case .monthly: "Mensual"
            }
        }

        var price: String {
            switch self {
            case .yearly: "29,99 €/año"
            case .monthly: "4,99 €/mes"
            }
        }

        var detail: String? {
            switch self {
            case .yearly: "7 días gratis · 2,50 €/mes"
            case .monthly: nil
            }
        }
    }

    var body: some View {
        VStack(spacing: WK.Spacing.l) {
            ScrollView {
                VStack(spacing: WK.Spacing.l) {
                    VStack(spacing: WK.Spacing.s) {
                        Text("Saca todo\nde tu armario")
                            .font(.system(.largeTitle, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text("Sin límites de prendas, maletas ni escaneo.")
                            .font(.subheadline)
                            .foregroundStyle(WK.Palette.secondaryText)
                    }
                    .padding(.top, WK.Spacing.m)

                    VStack(alignment: .leading, spacing: WK.Spacing.m) {
                        PaywallBenefit(symbol: "infinity", text: "Prendas y maletas sin límite")
                        PaywallBenefit(symbol: "photo.stack", text: "Escaneo completo de tu galería")
                        PaywallBenefit(symbol: "person.crop.rectangle", text: "Pruébate los outfits")
                        PaywallBenefit(symbol: "square.and.arrow.up", text: "Comparte y exporta tus looks")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TestimonialCard(OnboardingContent.testimonials[0])

                    VStack(spacing: WK.Spacing.s) {
                        ForEach(Plan.allCases) { option in
                            PlanRow(plan: option, isSelected: plan == option) { plan = option }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            AdaptiveGlassContainer(spacing: WK.Spacing.s) {
                VStack(spacing: WK.Spacing.s) {
                    WKPrimaryButton("Empezar 7 días gratis", surface: .glass) {
                        // F9: compra real con RevenueCat.
                        onFinish()
                    }
                    WKSecondaryButton("Seguir gratis") { onFinish() }

                    Text("Puedes cancelar cuando quieras.")
                        .font(WK.Font.caption)
                        .foregroundStyle(WK.Palette.tertiaryText)
                }
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.m)
    }
}

private struct PaywallBenefit: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: WK.Spacing.m) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(WK.Palette.accent)
                .frame(width: 26)
            Text(text).font(.subheadline)
            Spacer()
        }
    }
}

private struct PlanRow: View {
    let plan: PaywallStep.Plan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(plan.title).font(.body.weight(.medium))
                    if let detail = plan.detail {
                        Text(detail).font(.caption).foregroundStyle(WK.Palette.secondaryText)
                    }
                }
                Spacer()
                Text(plan.price).font(.subheadline.weight(.semibold))
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? WK.Palette.accent : WK.Palette.ink(0.22))
            }
            .padding(WK.Spacing.m)
            .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                    .stroke(isSelected ? WK.Palette.accent : .clear, lineWidth: 2)
            )
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}
