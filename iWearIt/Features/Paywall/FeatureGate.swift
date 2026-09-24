import Foundation
import Observation
import SwiftData
import SwiftUI
import WKCore
import WKPersistence
import WKServices

/// Decide qué puede hacer el usuario y abre el paywall cuando no puede.
///
/// **Ninguna vista sabe de RevenueCat, ni de `isPro`, ni de los topes.** Las
/// vistas preguntan `gate.access(.suitcases)` o llaman
/// `gate.require(.tryOn) { ... }`, y eso es todo lo que necesitan saber. Cambiar
/// qué es de pago no toca ni una pantalla.
@MainActor
@Observable
public final class FeatureGate {

    private(set) var isPro = false
    /// Qué feature ha provocado que se abra el paywall, para poder enseñar el
    /// motivo en vez de un muro genérico.
    var pendingFeature: Feature?
    var isPresentingPaywall = false
    /// **Acabas de hacerte Pro**: lo enseña la raíz de la app. Ver
    /// `ProCelebration`.
    var celebratesUpgrade = false
    /// El primer refresco solo toma nota: al arrancar siendo ya Pro no hay
    /// nada que celebrar.
    private var hasLoaded = false

    private let entitlements: EntitlementsService
    private let container: ModelContainer

    init(entitlements: EntitlementsService, container: ModelContainer) {
        self.entitlements = entitlements
        self.container = container
    }

    func refresh() async {
        await entitlements.refresh()
        let wasPro = isPro
        isPro = await entitlements.isPro
        // De no a sí, y no en el arranque: comprar o restaurar. Da igual desde
        // qué pantalla: la celebración sale en la raíz.
        if hasLoaded, !wasPro, isPro { celebratesUpgrade = true }
        hasLoaded = true
    }

    /// Qué puede hacer con una feature, contando lo que ya tiene.
    func access(_ feature: Feature) -> Access {
        guard !isPro else { return .allowed }
        guard let limit = FreeTierLimits.limit(for: feature) else { return .locked }

        let used = usage(of: feature)
        return .limited(remaining: max(0, limit - used), of: limit)
    }

    /// Ejecuta la acción si puede; si no, abre el paywall.
    ///
    /// El patrón que usan las vistas. Que el paywall se abra **aquí** y no en
    /// cada sitio es lo que garantiza que siempre se abra igual.
    func require(_ feature: Feature, then action: () -> Void) {
        if access(feature).isAllowed {
            action()
        } else {
            pendingFeature = feature
            isPresentingPaywall = true
        }
    }

    /// Cuántas fotos mira el escaneo con el plan actual.
    var scanPhotoLimit: Int? {
        isPro ? nil : FreeTierLimits.scanPhotos
    }

    /// Hasta cuántos días vista deja planificar.
    var planningDayLimit: Int? {
        isPro ? nil : FreeTierLimits.planningDays
    }

    // MARK: - Lo que ya tiene

    /// Se cuenta contra la base de datos en el momento, no se lleva un contador
    /// aparte: un contador y la realidad acaban discrepando en cuanto algo se
    /// borra fuera del camino previsto.
    private func usage(of feature: Feature) -> Int {
        let context = ModelContext(container)
        switch feature {
        case .garments:
            return (try? context.fetchCount(FetchDescriptor<Garment>())) ?? 0
        case .suitcases:
            return (try? context.fetchCount(FetchDescriptor<Suitcase>())) ?? 0
        case .customCategories:
            let descriptor = FetchDescriptor<GarmentCategory>(
                predicate: #Predicate { $0.isBuiltIn == false }
            )
            return (try? context.fetchCount(descriptor)) ?? 0
        case .fullScan, .extendedPlanning, .tryOn, .outfitExport:
            return 0
        }
    }

    #if DEBUG
    /// Cambia el estado de suscripción sin pasar por la tienda.
    func setDebugPro(_ value: Bool) async {
        guard let debug = entitlements as? DebugEntitlementsService else { return }
        await debug.setPro(value)
        await refresh()
    }

    var isDebugControllable: Bool { entitlements is DebugEntitlementsService }
    #endif
}

/// Texto de por qué se ha abierto el paywall.
extension Feature {
    var lockedTitle: String {
        switch self {
        case .garments: String(localized: "paywall.featuregate.youVeReachedPieces", defaultValue: "You've reached \(String(describing: FreeTierLimits.garments)) pieces")
        case .suitcases: String(localized: "paywall.featuregate.oneSuitcaseForNow", defaultValue: "One suitcase for now")
        case .customCategories: String(localized: "paywall.featuregate.youVeCreatedCustomShelves", defaultValue: "You've created \(String(describing: FreeTierLimits.customCategories)) custom shelves")
        case .fullScan: String(localized: "paywall.featuregate.fullScan", defaultValue: "Full scan")
        case .extendedPlanning: String(localized: "paywall.featuregate.planBeyondThisWeek", defaultValue: "Plan beyond this week")
        case .tryOn: String(localized: "paywall.featuregate.tryOnYourOutfits", defaultValue: "Try on your outfits")
        case .outfitExport: String(localized: "paywall.featuregate.shareYourLooks", defaultValue: "Share your looks")
        }
    }

    var lockedDetail: String {
        switch self {
        case .garments:
            String(localized: "paywall.featuregate.withSnazzyProYourCloset", defaultValue: "With Snazzy Pro your closet has no limit.")
        case .suitcases:
            String(localized: "paywall.featuregate.withProYouCanPrepare", defaultValue: "With Pro you can prepare as many trips as you like at once.")
        case .customCategories:
            String(localized: "paywall.featuregate.withProYouOrganiseYour", defaultValue: "With Pro you organise your closet however you want.")
        case .fullScan:
            String(localized: "paywall.featuregate.freeWeLookAtPhotos", defaultValue: "Free, we look at \(String(describing: FreeTierLimits.scanPhotos)) photos. With Pro, your whole library.")
        case .extendedPlanning:
            String(localized: "paywall.featuregate.freeYouCanPlanDays", defaultValue: "Free, you can plan \(String(describing: FreeTierLimits.planningDays)) days. With Pro, no limit.")
        case .tryOn:
            String(localized: "paywall.featuregate.seeHowAnOutfitLooks", defaultValue: "See how an outfit looks on you before you wear it.")
        case .outfitExport:
            String(localized: "paywall.featuregate.exportAndShareTheOutfits", defaultValue: "Export and share the outfits you put together.")
        }
    }
}
