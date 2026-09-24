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
            case .sixMonth: String(localized: "paywall.paywallstep.sixMonths", defaultValue: "Six months")
            case .monthly: String(localized: "paywall.paywallstep.monthly", defaultValue: "Monthly")
            case .weekly: String(localized: "paywall.paywallstep.weekly", defaultValue: "Weekly")
            }
        }

        var price: String {
            switch self {
            case .sixMonth: "44,99 €"
            case .monthly: String(localized: "paywall.paywallstep.1199Month", defaultValue: "€11.99/month")
            case .weekly: String(localized: "paywall.paywallstep.499Week", defaultValue: "€4.99/week")
            }
        }

        var detail: String? {
            switch self {
            case .sixMonth: String(localized: "paywall.paywallstep.750MonthSave37", defaultValue: "€7.50/month · save 37%")
            case .monthly: nil
            case .weekly: String(localized: "paywall.paywallstep.toTryItForA", defaultValue: "To try it for a trip")
            }
        }
    }

    var body: some View {
        VStack(spacing: WK.Spacing.l) {
            ScrollView {
                VStack(spacing: WK.Spacing.l) {
                    VStack(spacing: WK.Spacing.s) {
                        Text(String(localized: "paywall.paywallstep.getEverythingNoutOfYour", defaultValue: "Get everything\nout of your closet"))
                            .font(.system(.largeTitle, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text(String(localized: "paywall.paywallstep.noLimitsOnClothesSuitcases", defaultValue: "No limits on clothes, suitcases or scanning."))
                            .font(.subheadline)
                            .foregroundStyle(WK.Palette.secondaryText)
                    }
                    .padding(.top, WK.Spacing.m)

                    VStack(alignment: .leading, spacing: WK.Spacing.m) {
                        PaywallBenefit(symbol: "infinity", tone: .granate, text: String(localized: "paywall.paywallstep.unlimitedClothesAndSuitcases", defaultValue: "Unlimited clothes and suitcases"))
                        PaywallBenefit(symbol: "photo.stack", tone: .denim, text: String(localized: "paywall.paywallstep.fullScanOfYourLibrary", defaultValue: "Full scan of your library"))
                        PaywallBenefit(symbol: "person.crop.rectangle", tone: .camel, text: String(localized: "paywall.paywallstep.tryOnYourOutfits", defaultValue: "Try on your outfits"))
                        PaywallBenefit(symbol: "square.and.arrow.up", tone: .oliva, text: String(localized: "paywall.paywallstep.shareAndExportYourLooks", defaultValue: "Share and export your looks"))
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

                    WKSecondaryButton(String(localized: "paywall.paywallstep.continueForFree", defaultValue: "Continue for free")) { onFinish() }

                    // **Restaurar tiene que estar a la vista.** Lo pide la App
                    // Store, y es lo primero que busca quien cambia de
                    // teléfono y se encuentra el paywall otra vez.
                    Button(String(localized: "paywall.paywallstep.restorePurchases", defaultValue: "Restore purchases")) {
                        Task {
                            let restored = await store.restore()
                            await appEnvironment.gate.refresh()
                            if restored { onFinish() }
                        }
                    }
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .disabled(store.isWorking)

                    Text(store.problem ?? String(localized: "paywall.paywallstep.cancelAnytime", defaultValue: "Cancel anytime."))
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
        if store.isWorking { return String(localized: "paywall.paywallstep.oneMoment", defaultValue: "One moment…") }
        // **Sin prueba gratis en ningún plan.** Antes, sin paquetes cargados,
        // el botón prometía siete días gratis que no existen.
        // guard let picked else { return "Empezar 7 días gratis" }
        // if let trial = picked.storeProduct.introductoryDiscount, trial.price == 0 {
        //     return "Empezar \(trial.subscriptionPeriod.localizedDescription) gratis"
        // }
        return String(localized: "paywall.paywallstep.subscribe", defaultValue: "Subscribe")
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
        case .annual: String(localized: "paywall.paywallstep.yearly", defaultValue: "Yearly")
        case .sixMonth: String(localized: "paywall.paywallstep.sixMonths", defaultValue: "Six months")
        case .threeMonth: String(localized: "paywall.paywallstep.threeMonths", defaultValue: "Three months")
        case .twoMonth: String(localized: "paywall.paywallstep.twoMonths", defaultValue: "Two months")
        case .monthly: String(localized: "paywall.paywallstep.monthly", defaultValue: "Monthly")
        case .weekly: String(localized: "paywall.paywallstep.weekly", defaultValue: "Weekly")
        case .lifetime: String(localized: "paywall.paywallstep.lifetime", defaultValue: "Lifetime")
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
                parts.append(String(localized: "paywall.paywallstep.month", defaultValue: "\(String(describing: text))/month"))
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
        case .day: return count == 1 ? String(localized: "paywall.paywallstep.1Day", defaultValue: "1 day") : String(localized: "paywall.paywallstep.days", defaultValue: "\(String(describing: count)) days")
        case .week: return count == 1 ? String(localized: "paywall.paywallstep.1Week", defaultValue: "1 week") : String(localized: "paywall.paywallstep.weeks", defaultValue: "\(String(describing: count)) weeks")
        case .month: return count == 1 ? String(localized: "paywall.paywallstep.1Month", defaultValue: "1 month") : String(localized: "paywall.paywallstep.months", defaultValue: "\(String(describing: count)) months")
        case .year: return count == 1 ? String(localized: "paywall.paywallstep.1Year", defaultValue: "1 year") : String(localized: "paywall.paywallstep.years", defaultValue: "\(String(describing: count)) years")
        @unknown default: return "\(count)"
        }
    }
}
