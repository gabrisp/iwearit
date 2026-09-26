import RevenueCat
import SwiftData
import SwiftUI
import WKCore
import WKPersistence
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
    /// En el onboarding, el botón de comprar es el global —ver
    /// `onboardingButton`—; en la hoja de dentro de la app, uno propio.
    var usesOnboardingButton = false
    /// Si pinta sus propias prendas alrededor. La hoja las pinta ella, detrás
    /// de todo —también del texto del tope—, para que den la vuelta al borde
    /// entero. Ver `PaywallSheetScreen`.
    var showsGarments = true

    @Query(filter: #Predicate<Garment> { $0.deletedAt == nil }) private var garments: [Garment]
    /// Tus prendas, dando la vuelta por el borde: el mismo lienzo del final
    /// del escaneo. Ver `ScanCloud`.
    @State private var pieces: [ScanCloud.Item] = []
    @State private var spreadSince = Date()

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

    /// **Tus prendas alrededor, y en medio lo que te llevas**: qué pasa hoy,
    /// esta semana y después —como hace Opal con su prueba, por pasos—, y
    /// los planes para elegir.
    var body: some View {
        ZStack {
            // En el onboarding las pinta él, debajo, para que no se muevan al
            // llegar desde "Tu armario". Ver `OnboardingClosetCloud`.
            if !usesOnboardingButton, showsGarments {
                ScanCloud(pieces: pieces, spreadSince: spreadSince, arrivesInPlace: true)
                    .ignoresSafeArea()
            }

            VStack(spacing: WK.Spacing.l) {
                Spacer(minLength: 0)
                AuraText(String(localized: "paywall.paywallstep.getEverythingNoutOfYour", defaultValue: "Get everything\nout of your closet"), font: WK.Font.largeTitle)
                    .multilineTextAlignment(.center)
                    .onboardingEntrance(0)

                // **Un carrusel y no una sola tarjeta**: los pasos, lo que dicen
                // quienes ya lo usan y lo que se consigue, pasando solos.
                // PaywallTimeline(steps: timeline)
                PaywallCarousel(timeline: timeline)
                    .onboardingEntrance(1)

                PlanPicker(options: planOptions, selected: selectedID) { select($0) }
                    .onboardingEntrance(2)

                Spacer(minLength: 0)

                if !usesOnboardingButton {
                    AdaptiveGlassContainer(spacing: WK.Spacing.s) {
                        WKPrimaryButton(buyTitle, surface: .glass) { buy() }
                            .disabled(store.isWorking)
                    }
                }
                secondaryActions
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.s)
        }
        .modifier(PaywallButton(
            isActive: usesOnboardingButton,
            title: buyTitle,
            isEnabled: !store.isWorking,
            footnote: store.problem ?? String(localized: "paywall.paywallstep.cancelAnytime", defaultValue: "Cancel anytime."),
            action: { buy() }
        ))
        .task {
            // Por si se abre antes de que el arranque haya traído la oferta.
            if packages.isEmpty { await store.load() }
            // El de seis meses primero, que es el que sale a cuenta.
            // picked = picked
            //     ?? packages.first { $0.packageType == .sixMonth }
            //     ?? packages.first { $0.packageType == .annual }
            //     ?? packages.first
            // **El que más ahorra**, que es el que lleva la etiqueta. Por tipo
            // de paquete fallaba: si el panel los tiene como personalizados,
            // salía elegido el semanal.
            picked = picked
                ?? packages.max { saving(of: $0) < saving(of: $1) }.flatMap { saving(of: $0) > 0 ? $0 : nil }
                ?? packages.first { $0.packageType == .sixMonth }
                ?? packages.first { $0.packageType == .annual }
                ?? packages.first
        }
        .task { if !usesOnboardingButton, showsGarments { await loadPieces() } }
    }

    /// "Seguir gratis" y "Restaurar", a la vista y juntos.
    private var secondaryActions: some View {
        HStack(spacing: WK.Spacing.l) {
            // "Seguir gratis", solo en el onboarding: entra en la app. En la
            // hoja de dentro de la app lo hace la X de arriba, que aparece a
            // los cinco segundos. Ver `PaywallSheetScreen`.
            if usesOnboardingButton {
                Button(String(localized: "paywall.paywallstep.continueForFree", defaultValue: "Continue for free")) { onFinish() }
            }
            // **Restaurar tiene que estar a la vista.** Lo pide la App Store,
            // y es lo primero que busca quien cambia de teléfono y se
            // encuentra el paywall otra vez.
            Button(String(localized: "paywall.paywallstep.restorePurchases", defaultValue: "Restore purchases")) {
                Task {
                    let restored = await store.restore()
                    await appEnvironment.gate.refresh()
                    if restored { onFinish() }
                }
            }
            .disabled(store.isWorking)
        }
        .font(WK.Font.captionMedium)
        .foregroundStyle(WK.Palette.secondaryText)
        .buttonStyle(.plain)
    }

    private func loadPieces() async {
        guard pieces.isEmpty else { return }
        // Todas a la vez y ya en su sitio: son las mismas, en el mismo sitio,
        // que en "Tu armario". Ver `ScanCloud.orbitEpoch`.
        var loaded: [ScanCloud.Item] = []
        for garment in garments.prefix(28) {
            guard let image = try? await appEnvironment.imageStore.image(for: garment.normalizedImageKey, variant: .thumb) else { continue }
            var item = ScanCloud.Item(image: image)
            item.kind = garment.kind
            loaded.append(item)
        }
        withAnimation(.easeOut(duration: 0.5)) { pieces = loaded }
    }

    // MARK: Los pasos

    /// Los días de prueba gratis del plan elegido, si la tienda da alguno.
    private var trialDays: Int? {
        guard let intro = picked?.storeProduct.introductoryDiscount, intro.price == 0 else { return nil }
        let period = intro.subscriptionPeriod
        let days = switch period.unit {
        case .day: period.value
        case .week: period.value * 7
        case .month: period.value * 30
        case .year: period.value * 365
        @unknown default: period.value
        }
        return days * max(1, intro.numberOfPeriods)
    }

    /// **Por pasos, como Opal**: con prueba, cuándo se avisa y cuándo se
    /// cobra; sin ella, lo que se nota hoy, esta semana y en un mes. Nada que
    /// la tienda no dé.
    private var timeline: [PaywallTimeline.Step] {
        if let days = trialDays {
            return [
                .init(symbol: "lock.open", when: String(localized: "paywall.timeline.today", defaultValue: "Today"),
                      what: String(localized: "paywall.timeline.trial.today", defaultValue: "Everything unlocked: unlimited closet, try-on and suitcases.")),
                .init(symbol: "bell", when: String(localized: "paywall.timeline.day", defaultValue: "Day \(String(describing: max(1, days - 2)))"),
                      what: String(localized: "paywall.timeline.trial.reminder", defaultValue: "We remind you before your trial ends.")),
                .init(symbol: "sparkles", when: String(localized: "paywall.timeline.day", defaultValue: "Day \(String(describing: days))"),
                      what: String(localized: "paywall.timeline.trial.billing", defaultValue: "Your plan starts. Cancel anytime before.")),
            ]
        }
        return [
            .init(symbol: "hanger", when: String(localized: "paywall.timeline.today", defaultValue: "Today"),
                  what: String(localized: "paywall.timeline.value.today", defaultValue: "Your whole closet inside, with no limit on pieces.")),
            .init(symbol: "calendar", when: String(localized: "paywall.timeline.thisWeek", defaultValue: "This week"),
                  what: String(localized: "paywall.timeline.value.week", defaultValue: "Outfits planned, and tried on before you go out.")),
            .init(symbol: "leaf", when: String(localized: "paywall.timeline.inAMonth", defaultValue: "In a month"),
                  what: String(localized: "paywall.timeline.value.month", defaultValue: "You stop buying what you already have.")),
        ]
    }

    // MARK: Los planes

    /// Los planes a elegir: los de la tienda, o los de ejemplo sin ella.
    private var planOptions: [PlanPicker.Option] {
        guard !packages.isEmpty else {
            return Plan.allCases.map {
                .init(id: $0.rawValue, title: $0.title, price: $0.price, detail: $0.detail,
                      badge: $0 == .sixMonth ? String(localized: "paywall.plan.save", defaultValue: "Save \(String(describing: 37))%") : nil)
            }
        }
        return packages.map { package in
            var badge: String?
            let saving = saving(of: package)
            if saving >= 5 {
                badge = String(localized: "paywall.plan.save", defaultValue: "Save \(String(describing: saving))%")
            }
            return .init(
                id: package.identifier,
                title: package.planTitle,
                price: package.storeProduct.localizedPriceString,
                detail: package.planDetail,
                badge: badge
            )
        }
    }

    /// Cuánto ahorra al mes frente al mensual, en %. 0 si nada o no se sabe.
    private func saving(of package: Package) -> Int {
        guard let monthly = packages.first(where: { $0.packageType == .monthly })?.storeProduct.price, monthly > 0,
              package.packageType != .monthly, package.packageType != .weekly,
              let perMonth = package.storeProduct.pricePerMonth?.decimalValue else { return 0 }
        return max(0, Int((1 - NSDecimalNumber(decimal: perMonth / monthly).doubleValue) * 100))
    }

    private var selectedID: String {
        packages.isEmpty ? plan.rawValue : (picked?.identifier ?? "")
    }

    private func select(_ id: String) {
        withAnimation(WKAnimation.selection) {
            if packages.isEmpty {
                plan = Plan(rawValue: id) ?? plan
            } else {
                picked = packages.first { $0.identifier == id }
            }
        }
    }

    // El paywall de antes: beneficios en lista, un testimonio y los planes en
    // filas, en un scroll.
    // var body: some View {
    //     VStack(spacing: WK.Spacing.l) {
    //         ScrollView {
    //             VStack(spacing: WK.Spacing.l) {
    //                 VStack(spacing: WK.Spacing.s) {
    //                     Text(String(localized: "paywall.paywallstep.getEverythingNoutOfYour", defaultValue: "Get everything\nout of your closet"))
    //                         .font(.system(.largeTitle, weight: .bold))
    //                         .multilineTextAlignment(.center)
    //                     Text(String(localized: "paywall.paywallstep.noLimitsOnClothesSuitcases", defaultValue: "No limits on clothes, suitcases or scanning."))
    //                         .font(.subheadline)
    //                         .foregroundStyle(WK.Palette.secondaryText)
    //                 }
    //                 .padding(.top, WK.Spacing.m)
    //
    //                 VStack(alignment: .leading, spacing: WK.Spacing.m) {
    //                     PaywallBenefit(symbol: "infinity", tone: .granate, text: String(localized: "paywall.paywallstep.unlimitedClothesAndSuitcases", defaultValue: "Unlimited clothes and suitcases"))
    //                     PaywallBenefit(symbol: "photo.stack", tone: .denim, text: String(localized: "paywall.paywallstep.fullScanOfYourLibrary", defaultValue: "Full scan of your library"))
    //                     PaywallBenefit(symbol: "person.crop.rectangle", tone: .camel, text: String(localized: "paywall.paywallstep.tryOnYourOutfits", defaultValue: "Try on your outfits"))
    //                     PaywallBenefit(symbol: "square.and.arrow.up", tone: .oliva, text: String(localized: "paywall.paywallstep.shareAndExportYourLooks", defaultValue: "Share and export your looks"))
    //                 }
    //                 .frame(maxWidth: .infinity, alignment: .leading)
    //
    //                 TestimonialCard(OnboardingContent.testimonials[0])
    //
    //                 VStack(spacing: WK.Spacing.s) {
    //                     if packages.isEmpty {
    //                         // Sin tienda: los de ejemplo, que al menos dicen de
    //                         // qué orden de precio hablamos.
    //                         ForEach(Plan.allCases) { option in
    //                             PlanRow(
    //                                 title: option.title,
    //                                 price: option.price,
    //                                 detail: option.detail,
    //                                 isSelected: plan == option
    //                             ) { plan = option }
    //                         }
    //                     } else {
    //                         ForEach(packages, id: \.identifier) { package in
    //                             PlanRow(
    //                                 title: package.planTitle,
    //                                 price: package.storeProduct.localizedPriceString,
    //                                 detail: package.planDetail,
    //                                 isSelected: picked?.identifier == package.identifier
    //                             ) { picked = package }
    //                         }
    //                     }
    //                 }
    //             }
    //         }
    //         .scrollIndicators(.hidden)
    //
    //         AdaptiveGlassContainer(spacing: WK.Spacing.s) {
    //             VStack(spacing: WK.Spacing.s) {
    //                 WKPrimaryButton(buyTitle, surface: .glass) { buy() }
    //                     .disabled(store.isWorking)
    //
    //                 WKSecondaryButton(String(localized: "paywall.paywallstep.continueForFree", defaultValue: "Continue for free")) { onFinish() }
    //
    //                 // **Restaurar tiene que estar a la vista.** Lo pide la App
    //                 // Store, y es lo primero que busca quien cambia de
    //                 // teléfono y se encuentra el paywall otra vez.
    //                 Button(String(localized: "paywall.paywallstep.restorePurchases", defaultValue: "Restore purchases")) {
    //                     Task {
    //                         let restored = await store.restore()
    //                         await appEnvironment.gate.refresh()
    //                         if restored { onFinish() }
    //                     }
    //                 }
    //                 .font(WK.Font.caption)
    //                 .foregroundStyle(WK.Palette.secondaryText)
    //                 .disabled(store.isWorking)
    //
    //                 Text(store.problem ?? String(localized: "paywall.paywallstep.cancelAnytime", defaultValue: "Cancel anytime."))
    //                     .font(WK.Font.caption)
    //                     .foregroundStyle(
    //                         store.problem == nil ? WK.Palette.tertiaryText : WK.Palette.accent
    //                     )
    //                     .multilineTextAlignment(.center)
    //             }
    //         }
    //     }
    //     .padding(.horizontal, WK.Spacing.screenInset)
    //     .padding(.bottom, WK.Spacing.m)
    //     .task {
    //         // Por si se abre antes de que el arranque haya traído la oferta.
    //         if packages.isEmpty { await store.load() }
    //         // El de seis meses primero, que es el que sale a cuenta.
    //         picked = picked
    //             ?? packages.first { $0.packageType == .sixMonth }
    //             ?? packages.first { $0.packageType == .annual }
    //             ?? packages.first
    //     }
    // }

    /// Lo que pone el botón.
    private var buyTitle: String {
        if store.isWorking { return String(localized: "paywall.paywallstep.oneMoment", defaultValue: "One moment…") }
        // La prueba, **solo si la tienda la da** para este plan.
        if let days = trialDays {
            return String(localized: "paywall.paywallstep.startTrial", defaultValue: "Start \(String(describing: days)) days free")
        }
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

/// El botón global del onboarding, o nada.
private struct PaywallButton: ViewModifier {
    let isActive: Bool
    let title: String
    let isEnabled: Bool
    let footnote: String
    let action: () -> Void

    func body(content: Content) -> some View {
        if isActive {
            content.onboardingButton(title, isEnabled: isEnabled, footnote: footnote, action: action)
        } else {
            content
        }
    }
}

/// **Lo que pasa, por pasos**: un punto por paso unidos por una línea, como
/// la prueba de Opal.
struct PaywallTimeline: View {
    struct Step: Identifiable {
        let symbol: String
        let when: String
        let what: String
        var id: String { when + what }
    }

    let steps: [Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: WK.Spacing.m) {
                    VStack(spacing: 0) {
                        Image(systemName: step.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(index == 0 ? WK.Palette.primaryText : WK.Palette.secondaryText)
                            .frame(width: 34, height: 34)
                            // .adaptiveGlass(in: .circle)
                            .background(WK.Palette.ink(0.06), in: .circle)
                        if index < steps.count - 1 {
                            Capsule()
                                .fill(WK.Palette.ink(0.14))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                                .padding(.vertical, 4)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.when)
                            .font(WK.Font.headline)
                            .foregroundStyle(WK.Palette.primaryText)
                        Text(step.what)
                            .font(WK.Font.callout)
                            .foregroundStyle(WK.Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 6)
                    .padding(.bottom, index < steps.count - 1 ? WK.Spacing.m : 0)
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(WK.Spacing.m)
        // Plana, sin sombra: va en el carrusel.
        // .adaptiveGlass(in: .rect(cornerRadius: WK.Radius.large, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.9), in: .rect(cornerRadius: WK.Radius.large, style: .continuous))
    }
}

/// **Los planes, uno al lado del otro**: el precio grande, lo que sale al
/// mes debajo, y "Ahorra X%" encima del que sale a cuenta. Sin contornos de
/// color: el elegido lleva el check, que se transforma, y se adelanta un
/// poco.
struct PlanPicker: View {
    struct Option: Identifiable {
        let id: String
        let title: String
        let price: String
        let detail: String?
        let badge: String?
    }

    let options: [Option]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        AdaptiveGlassContainer(spacing: WK.Spacing.s) {
            HStack(alignment: .bottom, spacing: WK.Spacing.s) {
                ForEach(options) { option in
                    card(option)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func card(_ option: Option) -> some View {
        let isSelected = option.id == selected
        return Button { onSelect(option.id) } label: {
            VStack(spacing: WK.Spacing.xs) {
                // "Ahorra X%", **dentro** de la tarjeta: por fuera, el cristal
                // de la de al lado lo tapaba. Las que no lo llevan guardan el
                // hueco, para que las tres midan lo mismo.
                Text(option.badge ?? " ")
                    .font(WK.Font.captionMedium)
                    .foregroundStyle(WK.Palette.canvas)
                    .padding(.horizontal, WK.Spacing.s)
                    .padding(.vertical, 3)
                    .background(WK.Palette.primaryText, in: .capsule)
                    .opacity(option.badge == nil ? 0 : 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? WK.Palette.primaryText : WK.Palette.tertiaryText)
                    .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating))
                Text(option.title)
                    .font(WK.Font.captionMedium)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .lineLimit(1)
                Text(option.price)
                    .font(WK.Font.headline)
                    .foregroundStyle(WK.Palette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(option.detail ?? " ")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WK.Spacing.m)
            .padding(.horizontal, WK.Spacing.xs)
            .contentShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .adaptiveGlassInteractive(in: .rect(cornerRadius: WK.Radius.large, style: .continuous))
        .opacity(isSelected ? 1 : 0.72)
        .scaleEffect(isSelected ? 1.04 : 1)
        .animation(WKAnimation.selection, value: isSelected)
    }
}

/// **El paywall como hoja**: no se cierra arrastrando, y la X de arriba
/// aparece a los cinco segundos. Es lo mismo al final del onboarding y
/// dentro de la app.
struct PaywallSheetScreen: View {
    /// Lo que lo ha abierto, si viene de un tope. Ver `PaywallSheet`.
    var feature: Feature?
    /// La X: seguir sin pagar.
    let onClose: () -> Void
    /// Comprado o restaurado.
    let onPurchased: () -> Void

    @State private var canClose = false

    var body: some View {
        NavigationStack {
            ZStack {
            // Las prendas, detrás de todo y de borde a borde de la hoja.
            OnboardingClosetCloud()
                .ignoresSafeArea()
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
                }
                PaywallStep(onFinish: onPurchased, showsGarments: false)
            }
            }
            .background(WK.Palette.canvas)
            // **Un título vacío, en línea**: la barra existe desde el
            // principio y la X, al aparecer, no hace saltar nada.
            .navigationTitle("   ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if canClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(String(localized: "common.close", defaultValue: "Close"))
                        .transition(.opacity.combined(with: .scale))
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.smooth(duration: 0.5)) { canClose = true }
        }
    }
}

/// **El carrusel del paywall**: tarjetas que pasan solas —los pasos, lo que
/// dicen quienes ya lo usan, lo que se consigue—, con sus puntos debajo. Se
/// puede deslizar a mano; al soltar, sigue solo.
struct PaywallCarousel: View {
    let timeline: [PaywallTimeline.Step]

    private enum Page: Hashable {
        case timeline
        case testimonial(Int)
        case outfits
    }

    private var pages: [Page] {
        [.timeline] + OnboardingContent.testimonials.indices.map { .testimonial($0) } + [.outfits]
    }

    @State private var page: Page = .timeline
    /// Lo que enseña el scroll; `page` lo sigue.
    @State private var scrolled: Page? = .timeline

    var body: some View {
        VStack(spacing: WK.Spacing.s) {
            // **Un scroll que pagina y no un `TabView`**: el de páginas
            // recortaba por arriba y por abajo. Este no recorta nada.
            // TabView(selection: $page) {
            //     ForEach(pages, id: \.self) { page in
            //         card(page)
            //             // El margen, dentro de cada tarjeta: el carrusel va de
            //             // borde a borde y las tarjetas no se cortan al pasar.
            //             // .padding(.horizontal, 2)
            //             .padding(.horizontal, WK.Spacing.screenInset)
            //             .padding(.vertical, WK.Spacing.s)
            //             .tag(page)
            //     }
            // }
            // .tabViewStyle(.page(indexDisplayMode: .never))
            // .frame(height: 252)
            // .padding(.horizontal, -WK.Spacing.screenInset)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pages, id: \.self) { page in
                        card(page)
                            .padding(.horizontal, WK.Spacing.screenInset)
                            .containerRelativeFrame(.horizontal)
                            .id(page)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .scrollPosition(id: $scrolled)
            .frame(height: 236)
            .padding(.horizontal, -WK.Spacing.screenInset)
            .onChange(of: scrolled) { _, new in if let new { page = new } }

            HStack(spacing: 6) {
                ForEach(pages, id: \.self) { item in
                    Capsule()
                        .fill(item == page ? WK.Palette.primaryText : WK.Palette.ink(0.18))
                        .frame(width: item == page ? 18 : 6, height: 6)
                }
            }
            .animation(.smooth(duration: 0.3), value: page)
        }
        // Pasa sola; cada cambio —a mano o no— vuelve a contar.
        .task(id: page) {
            try? await Task.sleep(for: .seconds(4.5))
            guard let index = pages.firstIndex(of: page) else { return }
            let next = pages[(index + 1) % pages.count]
            withAnimation(.smooth(duration: 0.6)) {
                page = next
                scrolled = next
            }
        }
    }

    @ViewBuilder
    private func card(_ page: Page) -> some View {
        switch page {
        case .timeline:
            PaywallTimeline(steps: timeline)
        case let .testimonial(index):
            let testimonial = OnboardingContent.testimonials[index]
            VStack(alignment: .leading, spacing: WK.Spacing.m) {
                HStack(spacing: WK.Spacing.m) {
                    Text(testimonial.initials)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(testimonial.tone.color, in: .circle)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 3) {
                            ForEach(0..<testimonial.stars, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(OnboardingTone.camel.color)
                            }
                        }
                        Text(testimonial.name + " · " + testimonial.tag)
                            .font(WK.Font.captionMedium)
                            .foregroundStyle(WK.Palette.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                Text("“" + testimonial.text + "”")
                    .font(Font.custom("PlusJakartaSans-SemiBold", size: 19, relativeTo: .headline))
                    .foregroundStyle(WK.Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(WK.Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Plano, sin sombra.
            // .adaptiveGlass(in: .rect(cornerRadius: WK.Radius.large, style: .continuous))
            .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.9), in: .rect(cornerRadius: WK.Radius.large, style: .continuous))
        case .outfits:
            VStack(spacing: WK.Spacing.m) {
                HStack(spacing: WK.Spacing.s) {
                    ForEach([4, 8, 6, 10], id: \.self) { garment in
                        Image(CatalogGarment.name(garment))
                            .resizable()
                            .scaledToFit()
                            .frame(height: 96)
                            .frame(maxWidth: .infinity)
                    }
                }
                Text(String(localized: "chat.proof.title", defaultValue: "Our users get more than 1,000 combinations out of what they already have"))
                    .font(Font.custom("PlusJakartaSans-SemiBold", size: 17, relativeTo: .headline))
                    .foregroundStyle(WK.Palette.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(WK.Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // .adaptiveGlass(in: .rect(cornerRadius: WK.Radius.large, style: .continuous))
            .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.9), in: .rect(cornerRadius: WK.Radius.large, style: .continuous))
        }
    }
}
