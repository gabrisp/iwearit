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

    private let entitlements: EntitlementsService
    private let container: ModelContainer

    init(entitlements: EntitlementsService, container: ModelContainer) {
        self.entitlements = entitlements
        self.container = container
    }

    func refresh() async {
        await entitlements.refresh()
        isPro = await entitlements.isPro
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
        case .garments: "Has llegado a \(FreeTierLimits.garments) prendas"
        case .suitcases: "Una maleta por ahora"
        case .customCategories: "Has creado \(FreeTierLimits.customCategories) baldas propias"
        case .fullScan: "Escaneo completo"
        case .extendedPlanning: "Planifica más allá de esta semana"
        case .tryOn: "Pruébate los outfits"
        case .outfitExport: "Comparte tus looks"
        }
    }

    var lockedDetail: String {
        switch self {
        case .garments:
            "Con iWearIt Pro tu armario no tiene tope."
        case .suitcases:
            "Con Pro puedes preparar tantos viajes como quieras a la vez."
        case .customCategories:
            "Con Pro organizas el armario como te dé la gana."
        case .fullScan:
            "Gratis miramos \(FreeTierLimits.scanPhotos) fotos. Con Pro, toda tu galería."
        case .extendedPlanning:
            "Gratis puedes planificar \(FreeTierLimits.planningDays) días. Con Pro, sin límite."
        case .tryOn:
            "Mira cómo te queda un outfit antes de ponértelo."
        case .outfitExport:
            "Exporta y comparte los outfits que montes."
        }
    }
}
