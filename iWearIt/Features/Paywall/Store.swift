import Foundation
import Observation
import RevenueCat
import WKCore
import WKServices

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
    /// Las dos monedas.
    ///
    /// ## Por qué dos y no una
    ///
    /// Porque no cuestan lo mismo ni se gastan al mismo ritmo. Mejorar una
    /// prenda es una llamada a un modelo de imagen que tarda unos segundos;
    /// probarse un outfit es varias veces eso. Con una sola moneda, el precio
    /// de una tendría que ser el de la otra — y entonces o las mejoras salen
    /// caras o las pruebas salen regaladas.
    ///
    /// El nombre lo pone el panel de RevenueCat y viaja con el saldo, así que
    /// en Ajustes se lee lo que tú escribas allí; estos son el respaldo.
    enum Currency: String, Sendable, CaseIterable, Codable {
        /// Para redibujar una prenda como foto de catálogo ("mejorar").
        case improvements = "MEJ"
        /// Para probarse un outfit encima (fase 10).
        case tryOns = "PRU"

        var fallbackName: String {
            switch self {
            case .improvements: "Mejoras"
            case .tryOns: "Pruebas"
            }
        }

        var symbol: String {
            switch self {
            case .improvements: "wand.and.stars"
            case .tryOns: "person.crop.rectangle"
            }
        }
    }

    /// Lo que cuesta cada cosa, y con qué moneda se paga.
    ///
    /// En un sitio y como datos: cambiar el precio no puede obligar a recordar
    /// en qué tres pantallas se restaba.
    enum Cost: String, Sendable, CaseIterable, Codable {
        /// Redibujar una prenda como foto de catálogo.
        case improvement
        /// Probarse un outfit encima.
        case generation

        var currency: Currency {
            switch self {
            case .improvement: .improvements
            case .generation: .tryOns
            }
        }

        var amount: Int {
            switch self {
            case .improvement: 1
            case .generation: 1
            }
        }

        var label: String {
            switch self {
            case .improvement: "Mejorar una prenda"
            case .generation: "Probarte un outfit"
            }
        }
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

    /// Los planes: lo que se suscribe.
    var plans: [Package] {
        packages.filter { $0.storeProduct.productType != .consumable }
    }

    /// Los paquetes de monedas sueltas.
    ///
    /// Para quien ya paga y se ha quedado sin: obligarle a esperar a la
    /// renovación es decirle que no a alguien que quiere darte dinero.
    var coinPacks: [Package] {
        packages.filter { $0.storeProduct.productType == .consumable }
    }
    /// Lo que se está comprando o restaurando.
    private(set) var isWorking = false
    /// El último fallo, para poder decirlo en vez de no hacer nada.
    private(set) var problem: String?
    /// Cuánto queda de cada moneda y cómo se llama en el panel.
    private(set) var balances: [StoreIDs.Currency: Int] = [:]
    private(set) var names: [StoreIDs.Currency: String] = [:]
    /// En qué se han gastado, de lo más reciente a lo más viejo.
    private(set) var ledger: [CreditEntry] = CreditEntry.load()
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

    /// **Apunta un gasto.**
    ///
    /// Apunta, no resta: restar una moneda lo hace RevenueCat con su clave
    /// secreta, que no puede vivir en la app. Esto es el registro de lo que la
    /// app ha hecho —lo que se ve en el historial— y, en cuanto el servidor
    /// sepa cobrar, este es el sitio donde se le pide.
    func note(_ cost: StoreIDs.Cost, detail: String? = nil) {
        let entry = CreditEntry(cost: cost, detail: detail)
        ledger.insert(entry, at: 0)
        if ledger.count > CreditEntry.maximum { ledger.removeLast(ledger.count - CreditEntry.maximum) }
        CreditEntry.save(ledger)
        DiagnosticsLog.record("TIENDA", "gasto: \(cost.label) · \(cost.amount) \(cost.currency.rawValue)")
        Task { await refreshCredits() }
    }

    func balance(of currency: StoreIDs.Currency) -> Int { balances[currency] ?? 0 }
    func name(of currency: StoreIDs.Currency) -> String {
        names[currency] ?? currency.fallbackName
    }

    /// Si alcanza para algo.
    func canAfford(_ cost: StoreIDs.Cost) -> Bool {
        // Sin monedas configuradas todavía, no se bloquea nada: cobrar por algo
        // que nadie puede comprar sería cerrar la app a cambio de nada.
        guard isReady, balance(of: cost.currency) > 0 else { return true }
        return balance(of: cost.currency) >= cost.amount
    }

    /// Cuánto saldo queda.
    func refreshCredits() async {
        guard Purchases.isConfigured else { return }
        do {
            let currencies = try await Purchases.shared.virtualCurrencies()
            for currency in StoreIDs.Currency.allCases {
                let found = currencies[currency.rawValue]
                balances[currency] = found?.balance ?? 0
                // El nombre del panel manda: si allí se llama de otra forma,
                // eso es lo que ve el usuario.
                names[currency] = found?.name ?? currency.fallbackName
            }
            DiagnosticsLog.record(
                "TIENDA",
                "saldo · " + StoreIDs.Currency.allCases
                    .map { "\(name(of: $0)) \(balance(of: $0))" }
                    .joined(separator: " · ")
            )
        } catch {
            // Sin monedas configuradas en el panel esto falla, y no es un
            // problema: la app entera funciona sin saldo mientras no existan.
            DiagnosticsLog.record("TIENDA", "sin saldo que leer: \(error)")
        }
    }
}


/// Una línea del historial: qué se hizo, cuánto costó y cuándo.
///
/// Se guarda en el teléfono y no en el servidor porque es **lo que ha hecho la
/// app**: el saldo lo lleva RevenueCat, y esto explica en qué se fue. Sin ello,
/// el número de Ajustes baja sin que nadie sepa por qué.
struct CreditEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var cost: StoreIDs.Cost
    /// De qué prenda o de qué outfit, si se sabe.
    var detail: String?

    var amount: Int { cost.amount }
    var currency: StoreIDs.Currency { cost.currency }

    static let maximum = 120
    private static let key = "credits.ledger"

    static func load() -> [CreditEntry] {
        SyncedStore.value([CreditEntry].self, forKey: key) ?? []
    }

    static func save(_ entries: [CreditEntry]) {
        SyncedStore.setValue(entries, forKey: key)
    }
}

