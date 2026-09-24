import RevenueCat
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
/// ## De dónde salen los precios
///
/// De RevenueCat, que los pide a la App Store: el precio de verdad, en la
/// moneda de verdad, con la promoción que tenga puesta esa cuenta. Los de
/// ejemplo se quedan **solo** para cuando no hay tienda —sin clave, sin red o
/// sin oferta configurada—, porque un paywall en blanco es peor que uno con
/// precios orientativos.
struct PaywallStep: View {
    let onFinish: () -> Void

    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var plan: Plan = .sixMonth
    /// Cuál de los paquetes de verdad está elegido.
    @State private var picked: Package?

    private var store: Store { appEnvironment.store }
    private var packages: [Package] { store.plans }

    /// Los de ejemplo, **solo** para cuando no hay tienda. Los de verdad los
    /// pone la App Store a través de RevenueCat, y son los que mandan.
    /// **Seis meses en vez de un año.**
    ///
    /// Un anual a 44,99 € sale a 3,75 € al mes: un tercio de lo que cuesta el
    /// mensual, así que solo puede pagar un tercio de imágenes — y quedaba el
    /// plan más caro de comprar dando menos monedas al mes que el mensual, que
    /// es justo lo contrario de lo que promete. A seis meses, el mismo precio
    /// sale a 7,50 € al mes: sigue siendo un 37% más barato **y** ya da para
    /// tantas monedas como el mensual, todas de golpe.
    enum Plan: String, CaseIterable, Identifiable {
        case sixMonth, monthly, weekly
        var id: String { rawValue }

        var title: String {
            switch self {
            case .sixMonth: "Seis meses"
            case .monthly: "Mensual"
            case .weekly: "Semanal"
            }
        }

        var price: String {
            switch self {
            case .sixMonth: "44,99 €"
            case .monthly: "11,99 €/mes"
            case .weekly: "4,99 €/semana"
            }
        }

        var detail: String? {
            switch self {
            case .sixMonth: "7,50 €/mes · ahorras un 37%"
            case .monthly: nil
            case .weekly: "Para probarlo un viaje"
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
                        PaywallBenefit(symbol: "infinity", tone: .granate, text: "Prendas y maletas sin límite")
                        PaywallBenefit(symbol: "photo.stack", tone: .denim, text: "Escaneo completo de tu galería")
                        PaywallBenefit(symbol: "person.crop.rectangle", tone: .camel, text: "Pruébate los outfits")
                        PaywallBenefit(symbol: "square.and.arrow.up", tone: .oliva, text: "Comparte y exporta tus looks")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TestimonialCard(OnboardingContent.testimonials[0])

                    VStack(spacing: WK.Spacing.s) {
                        if packages.isEmpty {
                            // Sin tienda: los de ejemplo, que al menos dicen de
                            // qué orden de precio hablamos.
                            ForEach(Plan.allCases) { option in
                                PlanRow(
                                    title: option.title,
                                    price: option.price,
                                    detail: option.detail,
                                    isSelected: plan == option
                                ) { plan = option }
                            }
                        } else {
                            ForEach(packages, id: \.identifier) { package in
                                PlanRow(
                                    title: package.planTitle,
                                    price: package.storeProduct.localizedPriceString,
                                    detail: package.planDetail,
                                    isSelected: picked?.identifier == package.identifier
                                ) { picked = package }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            AdaptiveGlassContainer(spacing: WK.Spacing.s) {
                VStack(spacing: WK.Spacing.s) {
                    WKPrimaryButton(buyTitle, surface: .glass) { buy() }
                        .disabled(store.isWorking)

                    WKSecondaryButton("Seguir gratis") { onFinish() }

                    // **Restaurar tiene que estar a la vista.** Lo pide la App
                    // Store, y es lo primero que busca quien cambia de
                    // teléfono y se encuentra el paywall otra vez.
                    Button("Restaurar compras") {
                        Task {
                            let restored = await store.restore()
                            await appEnvironment.gate.refresh()
                            if restored { onFinish() }
                        }
                    }
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .disabled(store.isWorking)

                    Text(store.problem ?? "Puedes cancelar cuando quieras.")
                        .font(WK.Font.caption)
                        .foregroundStyle(
                            store.problem == nil ? WK.Palette.tertiaryText : WK.Palette.accent
                        )
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.m)
        .task {
            // Por si se abre antes de que el arranque haya traído la oferta.
            if packages.isEmpty { await store.load() }
            // El de seis meses primero, que es el que sale a cuenta.
            picked = picked
                ?? packages.first { $0.packageType == .sixMonth }
                ?? packages.first { $0.packageType == .annual }
                ?? packages.first
        }
    }

    /// Lo que pone el botón.
    private var buyTitle: String {
        if store.isWorking { return "Un momento…" }
        // **Sin prueba gratis en ningún plan.** Antes, sin paquetes cargados,
        // el botón prometía siete días gratis que no existen.
        // guard let picked else { return "Empezar 7 días gratis" }
        // if let trial = picked.storeProduct.introductoryDiscount, trial.price == 0 {
        //     return "Empezar \(trial.subscriptionPeriod.localizedDescription) gratis"
        // }
        return "Suscribirme"
    }

    private func buy() {
        guard let picked else {
            // Sin tienda no hay nada que comprar: se sale como quien dice que
            // no, en vez de dejar un botón que no hace nada.
            onFinish()
            return
        }
        Task {
            let bought = await store.purchase(picked)
            await appEnvironment.gate.refresh()
            if bought { onFinish() }
        }
    }
}

private struct PaywallBenefit: View {
    let symbol: String
    let tone: OnboardingTone
    let text: String

    var body: some View {
        HStack(spacing: WK.Spacing.m) {
            // Image(systemName: symbol)
            //     .font(.body)
            //     .foregroundStyle(WK.Palette.accent)
            //     .frame(width: 26)
            ToneIcon(symbol, tone: tone, size: 36)
            Text(text).font(.subheadline.weight(.medium))
            Spacer()
        }
    }
}

private struct PlanRow: View {
    let title: String
    let price: String
    let detail: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.medium))
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(WK.Palette.secondaryText)
                    }
                }
                Spacer()
                Text(price).font(.subheadline.weight(.semibold))
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? WK.Palette.accent : WK.Palette.ink(0.22))
            }
            .padding(WK.Spacing.m)
            // .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))
            // .overlay(
            //     RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
            //         .stroke(isSelected ? WK.Palette.accent : .clear, lineWidth: 2)
            // )
            .contentShape(.rect(cornerRadius: WK.Radius.medium, style: .continuous))
        }
        // Cristal interactivo, como las opciones del resto del onboarding.
        .buttonStyle(.plain)
        .adaptiveGlassInteractive(in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))
        // Por fuera del cristal: ver `OptionRow`.
        .overlay {
            RoundedRectangle(cornerRadius: WK.Radius.medium + 4, style: .continuous)
                .stroke(isSelected ? WK.Palette.accent : .clear, lineWidth: 2)
                .padding(-4)
        }
    }
}


/// Cómo se llama y qué se dice de un paquete de RevenueCat.
///
/// El nombre sale del **tipo** de paquete y no del título del producto: el de
/// App Store Connect suele ser "iWearIt Pro (anual)", que repite el nombre de
/// la app dentro de la app.
private extension Package {

    var planTitle: String {
        switch packageType {
        case .annual: "Anual"
        case .sixMonth: "Seis meses"
        case .threeMonth: "Tres meses"
        case .twoMonth: "Dos meses"
        case .monthly: "Mensual"
        case .weekly: "Semanal"
        case .lifetime: "Para siempre"
        default: storeProduct.localizedTitle
        }
    }

    /// Lo que se puede decir con verdad debajo del nombre: la prueba gratis si
    /// la hay, y lo que sale al mes si es un plan largo.
    var planDetail: String? {
        var parts: [String] = []
        // Sin prueba gratis: no se anuncia aunque la tienda trajera una.
        // if let intro = storeProduct.introductoryDiscount, intro.price == 0 {
        //     parts.append("\(intro.subscriptionPeriod.localizedDescription) gratis")
        // }
        if packageType == .annual || packageType == .sixMonth,
           let monthly = storeProduct.pricePerMonth {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = storeProduct.currencyCode
            if let text = formatter.string(from: monthly) {
                parts.append("\(text)/mes")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private extension SubscriptionPeriod {
    /// "7 días", "1 mes": lo justo para el botón.
    var localizedDescription: String {
        let count = value
        switch unit {
        case .day: return count == 1 ? "1 día" : "\(count) días"
        case .week: return count == 1 ? "1 semana" : "\(count) semanas"
        case .month: return count == 1 ? "1 mes" : "\(count) meses"
        case .year: return count == 1 ? "1 año" : "\(count) años"
        @unknown default: return "\(count)"
        }
    }
}
