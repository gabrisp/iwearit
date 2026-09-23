import Foundation
import Observation
import RevenueCat
import WKCore

/// Lo que hay que tener configurado en RevenueCat para que esto funcione.
///
/// Los identificadores viven aquí y no repartidos por el código: son cadenas
/// que tienen que coincidir **exactamente** con el panel de RevenueCat, y
/// cuando no coinciden el fallo es silencioso —no hay paywall, no hay saldo—,
/// así que al menos que estén todas juntas y con su nombre.
nonisolated enum StoreIDs {

    /// El derecho que da acceso a todo. Es el que se mira para saber si alguien
    /// es Pro.
    static let entitlement = "pro"

    /// Las dos monedas.
    ///
    /// ## Por qué dos y no una
    ///
    /// Porque no cuestan lo mismo ni se gastan al mismo ritmo. Mejorar una
    /// prenda es una llamada a un modelo de imagen que tarda unos segundos y
    /// cuesta céntimos; probarse un outfit es varias veces eso. Con una sola
    /// moneda, el precio de una tendría que ser el de la otra —y entonces o
    /// las mejoras salen caras o las pruebas salen regaladas—.
    enum Currency {
        /// Para redibujar una prenda como foto de catálogo ("mejorar").
        static let improvements = "MEJ"
        /// Para probarse un outfit encima (fase 10).
        static let tryOns = "PRU"
    }
}

/// Si el usuario ha pagado, preguntándoselo a RevenueCat.
///
/// La app no conoce este tipo: habla con `FeatureGate`, que habla con el
/// protocolo. Cambiar de proveedor es cambiar este fichero.
nonisolated struct RevenueCatEntitlements: EntitlementsService {

    var isPro: Bool {
        get async {
            guard Purchases.isConfigured else { return false }
            let info = try? await Purchases.shared.customerInfo()
            return info?.entitlements[StoreIDs.entitlement]?.isActive == true
        }
    }

    func refresh() async {
        guard Purchases.isConfigured else { return }
        // La caché de RevenueCat es buena para arrancar rápido y mala justo
        // después de comprar o de restaurar, que es cuando esto se llama.
        _ = try? await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
    }
}

/// La tienda: lo que se puede comprar, comprarlo, y cuánto saldo queda.
///
/// ## Por qué es `@Observable` y vive en el entorno
///
/// Porque el paywall necesita precios **reales** —los de la App Store del
/// usuario, en su moneda y con su promoción— y porque comprar cambia cosas que
/// se ven en tres sitios a la vez: el paywall, los topes y el saldo de
/// mejoras. Un objeto observado en el entorno es lo que hace que las tres se
/// enteren sin avisarse entre ellas.
///
/// ## Lo que **no** hace
///
/// Gastar saldo. Restar una moneda es una operación de servidor —la hace
/// RevenueCat con su clave secreta, que no puede estar en la app— así que aquí
/// solo se lee el saldo y se refresca después de cada consumo. Ver
/// `Credits.spend` cuando esté la función de Appwrite.
@MainActor
@Observable
final class Store {

    /// Lo que se puede comprar ahora mismo, en el orden del panel.
    private(set) var packages: [Package] = []
    /// Lo que se está comprando o restaurando.
    private(set) var isWorking = false
    /// El último fallo, para poder decirlo en vez de no hacer nada.
    private(set) var problem: String?
    /// Saldo de cada moneda.
    private(set) var improvements = 0
    private(set) var tryOns = 0
    /// Si el SDK está configurado. Sin clave, la app funciona entera: el
    /// paywall enseña sus precios de ejemplo y no se puede comprar.
    private(set) var isReady = false

    /// Arranca el SDK. Llamarlo dos veces no configura dos veces.
    func start() {
        guard !Purchases.isConfigured else { isReady = true; return }
        let key = AppConfiguration.revenueCatAPIKey
        guard !key.isEmpty else {
            DiagnosticsLog.record("TIENDA", "sin clave de RevenueCat: la app va en modo gratuito")
            return
        }
        Purchases.logLevel = AppConfiguration.isDebugBuild ? .info : .warn
        Purchases.configure(withAPIKey: key)
        isReady = true
        DiagnosticsLog.record("TIENDA", "RevenueCat configurado")
    }

    /// Los productos de la oferta actual.
    func load() async {
        guard Purchases.isConfigured else { return }
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let current = offerings.current else {
                DiagnosticsLog.record(
                    "TIENDA", "no hay oferta actual configurada en RevenueCat", isProblem: true
                )
                return
            }
            packages = current.availablePackages
            DiagnosticsLog.record(
                "TIENDA",
                "oferta \(current.identifier): "
                    + packages.map(\.storeProduct.productIdentifier).joined(separator: ", ")
            )
        } catch {
            problem = error.localizedDescription
            DiagnosticsLog.record("TIENDA", "no se pudo leer la oferta: \(error)", isProblem: true)
        }
    }

    /// Compra, y dice si el usuario acabó siendo Pro.
    ///
    /// Cancelar **no es un error**: es la respuesta más común a un paywall y se
    /// devuelve como un "no" tranquilo, sin alerta ni mensaje rojo.
    func purchase(_ package: Package) async -> Bool {
        guard Purchases.isConfigured else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            guard !result.userCancelled else { return false }
            let active = result.customerInfo.entitlements[StoreIDs.entitlement]?.isActive == true
            DiagnosticsLog.record("TIENDA", "compra hecha · pro: \(active)")
            await refreshCredits()
            return active
        } catch {
            problem = error.localizedDescription
            DiagnosticsLog.record("TIENDA", "la compra falla: \(error)", isProblem: true)
            return false
        }
    }

    /// Restaurar: obligatorio en la App Store y lo primero que busca quien
    /// cambia de teléfono.
    func restore() async -> Bool {
        guard Purchases.isConfigured else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            let active = info.entitlements[StoreIDs.entitlement]?.isActive == true
            DiagnosticsLog.record("TIENDA", "restaurado · pro: \(active)")
            await refreshCredits()
            return active
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    /// Cuánto saldo queda de cada moneda.
    func refreshCredits() async {
        guard Purchases.isConfigured else { return }
        do {
            let currencies = try await Purchases.shared.virtualCurrencies()
            improvements = currencies[StoreIDs.Currency.improvements]?.balance ?? 0
            tryOns = currencies[StoreIDs.Currency.tryOns]?.balance ?? 0
            DiagnosticsLog.record("TIENDA", "saldo · mejoras \(improvements) · pruebas \(tryOns)")
        } catch {
            // Sin monedas configuradas en el panel esto falla, y no es un
            // problema: la app entera funciona sin saldo mientras no existan.
            DiagnosticsLog.record("TIENDA", "sin saldo que leer: \(error)")
        }
    }
}
