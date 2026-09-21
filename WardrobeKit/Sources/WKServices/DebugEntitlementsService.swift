import Foundation
import WKCore

/// Estado de suscripción controlado a mano, persistido en `UserDefaults`.
///
/// Es lo que corre mientras no haya RevenueCat: permite recorrer las dos ramas
/// —gratis y pro— sin comprar nada y sin sandbox, que es donde se va la mitad
/// del tiempo al montar un paywall.
///
/// - Important: solo en Debug. En Release el `AppEnvironment` inyecta el
///   servicio real, y este no se compila siquiera.
public actor DebugEntitlementsService: EntitlementsService {
    private static let key = "debug.isPro"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isPro: Bool {
        get async { defaults.bool(forKey: Self.key) }
    }

    public func setPro(_ value: Bool) {
        defaults.set(value, forKey: Self.key)
    }

    public func refresh() async {}
}

/// El servicio real, todavía sin conectar.
///
/// No se añade el SDK de RevenueCat hasta que haya productos configurados en
/// App Store Connect: una dependencia que no se puede ejercitar es una
/// dependencia que no se puede verificar, y acaba descubriéndose rota el día
/// del lanzamiento.
///
/// Cuando llegue el momento, lo único que cambia es el cuerpo de estos dos
/// métodos — nada de la app los conoce por su nombre.
public struct RevenueCatEntitlementsService: EntitlementsService {
    private let apiKey: String
    private let entitlementID: String

    public init(apiKey: String, entitlementID: String = "pro") {
        self.apiKey = apiKey
        self.entitlementID = entitlementID
    }

    public var isPro: Bool {
        get async {
            // TODO(F9b): Purchases.shared.customerInfo().entitlements[entitlementID]?.isActive
            false
        }
    }

    public func refresh() async {
        // TODO(F9b): Purchases.shared.invalidateCustomerInfoCache()
    }
}
