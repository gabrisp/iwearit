import Foundation
import Observation
import SwiftUI

/// Los avisos que enseñan a usar la app.
///
/// ## Por qué no TipKit
///
/// TipKit resuelve el registro y las reglas, y a cambio impone su tarjeta, su
/// tipografía y sus animaciones — que no son las de esta app. Y lo que hay que
/// enseñar aquí no es "toca este botón": es **un gesto**, el tirón que crea un
/// outfit o el mantener pulsado que suelta una prenda en otra balda. Un gesto
/// se enseña dibujándolo, y eso hay que pintarlo igualmente.
///
/// Así que el registro y las reglas se quedan —son media página— y la tarjeta
/// es la de la app, con el dedo animado haciendo el gesto de verdad.
public enum WKTip: String, CaseIterable, Sendable {
    /// Tirar hacia abajo para crear un outfit.
    case overscrollNewOutfit
    /// Mantener pulsada una prenda para moverla de balda.
    case dragGarment
    /// Varias fotos de una vez al importar.
    case bulkImport
    /// Tocar una tarjeta para editar la prenda antes de guardarla.
    case reviewCard
    /// Arrastrar un conjunto de inspiración a un lado o al otro.
    case swipeLook

    public var title: String {
        switch self {
        case .overscrollNewOutfit: String(localized: "wkdesign.wktips.pullToCreate", defaultValue: "Pull to create", bundle: .module)
        case .dragGarment: String(localized: "wkdesign.wktips.moveYourClothes", defaultValue: "Move your clothes", bundle: .module)
        case .bulkImport: String(localized: "wkdesign.wktips.severalAtOnce", defaultValue: "Several at once", bundle: .module)
        case .reviewCard: String(localized: "wkdesign.wktips.tapToAdjust", defaultValue: "Tap to adjust", bundle: .module)
        case .swipeLook: String(localized: "wkdesign.wktips.sayItWithASwipe", defaultValue: "Say it with a swipe", bundle: .module)
        }
    }

    public var message: String {
        switch self {
        case .overscrollNewOutfit:
            String(localized: "wkdesign.wktips.pullAllTheWayDown", defaultValue: "Pull all the way down and let go to put together a new outfit.", bundle: .module)
        case .dragGarment:
            String(localized: "wkdesign.wktips.pressAndHoldAPiece", defaultValue: "Press and hold a piece to take it to another shelf or move it around.", bundle: .module)
        case .bulkImport:
            String(localized: "wkdesign.wktips.youCanPickSeveralPhotos", defaultValue: "You can pick several photos at once: they're analysed one after another.", bundle: .module)
        case .reviewCard:
            String(localized: "wkdesign.wktips.tapAPieceToChange", defaultValue: "Tap a piece to change its type, its color or crop it again.", bundle: .module)
        case .swipeLook:
            String(localized: "wkdesign.wktips.swipeRightOnWhatYou", defaultValue: "Swipe right on what you like and left on what you don't: what you discard counts less in what comes next.", bundle: .module)
        }
    }

    /// Qué gesto se dibuja. Ver `WKTipDemo`.
    public var demo: WKTipDemo {
        switch self {
        case .overscrollNewOutfit: .pull
        case .dragGarment: .drag
        case .bulkImport: .stack
        case .reviewCard: .tap
        case .swipeLook: .drag
        }
    }
}

/// El gesto que se dibuja en la tarjeta.
public enum WKTipDemo: Sendable {
    /// Un dedo tirando hacia abajo y soltando.
    case pull
    /// Un dedo llevándose una pieza de un sitio a otro.
    case drag
    /// Varias piezas entrando en fila.
    case stack
    /// Un toque.
    case tap
}

/// Quién decide qué aviso se enseña y cuándo.
///
/// ## Una sola llave
///
/// Todo lo visto vive en **una** entrada de `UserDefaults` con la lista de
/// avisos ya enseñados. Una llave por aviso —cuatro hoy, veinte dentro de dos
/// meses— convierte los ajustes en un cajón de booleanos y hace que "empezar
/// de cero" sea acordarse de borrarlos todos.
@MainActor
@Observable
public final class WKTipCenter {

    /// La llave. Una, con la lista dentro.
    public static let storageKey = "tips.seen"

    /// Lo que ya se ha enseñado.
    private var seen: Set<String> {
        didSet { defaults.set(Array(seen), forKey: Self.storageKey) }
    }

    /// El que se está enseñando ahora, si hay alguno.
    public private(set) var current: WKTip?

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.seen = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    /// Pide enseñar un aviso.
    ///
    /// No se enseña si ya se vio o si hay otro puesto: dos tarjetas a la vez
    /// no se leen, se cierran. El que llega tarde se pedirá otra vez la
    /// próxima vez que se entre en su pantalla, que es justo cuando vuelve a
    /// tener sentido.
    public func offer(_ tip: WKTip) {
        guard current == nil, !seen.contains(tip.rawValue) else { return }
        current = tip
    }

    /// Lo cierra y no vuelve.
    public func dismiss() {
        guard let current else { return }
        seen.insert(current.rawValue)
        self.current = nil
    }

    /// **El gesto hecho vale por el aviso leído.**
    ///
    /// Si el usuario ya ha arrastrado una prenda, explicarle cómo se arrastra
    /// sobra — esté la tarjeta puesta o no. Se marca como vista y, si era la
    /// que estaba en pantalla, se va.
    public func complete(_ tip: WKTip) {
        seen.insert(tip.rawValue)
        if current == tip { current = nil }
    }

    /// Lo quita de la pantalla **sin darlo por visto**: ya no tiene sentido
    /// ahora, pero lo tendrá más adelante.
    public func withdraw(_ tip: WKTip) {
        if current == tip { current = nil }
    }

    /// Si un aviso ya se vio. Para pintar el estado en ajustes.
    public func hasSeen(_ tip: WKTip) -> Bool { seen.contains(tip.rawValue) }

    public var seenCount: Int { seen.count }

    /// **Empezar de cero.** Borra la lista entera, y los avisos vuelven a
    /// salir según se vayan visitando las pantallas.
    public func resetAll() {
        seen = []
        current = nil
    }
}
