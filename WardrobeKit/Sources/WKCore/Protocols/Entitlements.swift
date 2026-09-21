import Foundation

/// Lo que se puede gatear.
///
/// Un enum y no comprobaciones sueltas de `isPro` repartidas por las vistas:
/// así decidir qué es de pago y qué no es cambiar **una tabla**, y ninguna
/// pantalla tiene que enterarse.
public enum Feature: String, Sendable, CaseIterable {
    case garments
    case suitcases
    case customCategories
    case fullScan
    case extendedPlanning
    case tryOn
    case outfitExport
}

/// Qué puede hacer el usuario con una feature.
public enum Access: Sendable, Equatable {
    case allowed
    /// Puede, pero le queda un tope. `remaining` es lo que le queda.
    case limited(remaining: Int, of: Int)
    case locked

    public var isAllowed: Bool {
        switch self {
        case .allowed: true
        case let .limited(remaining, _): remaining > 0
        case .locked: false
        }
    }
}

/// Los topes del plan gratuito.
///
/// En un solo sitio y como datos, no como números sueltos en el código: lo que
/// se va a querer afinar muchas veces cuando haya usuarios reales.
public enum FreeTierLimits {
    public static let garments = 25
    public static let suitcases = 1
    public static let customCategories = 2
    /// Fotos que mira el escaneo inicial.
    public static let scanPhotos = 300
    /// Días vista en el planificador.
    public static let planningDays = 7

    public static func limit(for feature: Feature) -> Int? {
        switch feature {
        case .garments: garments
        case .suitcases: suitcases
        case .customCategories: customCategories
        case .fullScan: scanPhotos
        case .extendedPlanning: planningDays
        // Sin versión gratuita: no es un tope, es una puerta.
        case .tryOn, .outfitExport: nil
        }
    }
}

/// Si el usuario ha pagado.
///
/// Detrás de un protocolo para poder desarrollar sin RevenueCat, probar los dos
/// estados sin comprar nada, y cambiar de proveedor sin tocar ni una vista.
public protocol EntitlementsService: Sendable {
    var isPro: Bool { get async }
    func refresh() async
}

/// Estado fijo. Para tests y previews.
public struct StaticEntitlementsService: EntitlementsService {
    private let value: Bool
    public init(isPro: Bool) { self.value = isPro }
    public var isPro: Bool { get async { value } }
    public func refresh() async {}
}
