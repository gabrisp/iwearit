import SwiftUI

/// Las curvas de la app.
///
/// En un sitio y no elegidas pantalla por pantalla: dos gestos que hacen lo
/// mismo tienen que sentirse igual, y en cuanto cada vista escribe su propio
/// `.snappy(duration: 0.3)` empiezan a divergir sin que nadie lo decida.
public enum WKAnimation {
    /// Selección, chips, toggles. Rápida y sin rebote: un rebote en algo que se
    /// pulsa muchas veces seguidas se acumula y marea.
    public static let selection = Animation.snappy(duration: 0.22, extraBounce: 0)

    /// Contenido que entra o sale: un paso del onboarding, una fase, un hueco.
    public static let content = Animation.smooth(duration: 0.34)

    /// Algo que aparece por primera vez y queremos que se note.
    public static let arrival = Animation.spring(duration: 0.45, bounce: 0.28)

    /// Durante un gesto. Tiene que responder al dedo, no interpretar.
    public static let interactive = Animation.interactiveSpring(duration: 0.2)
}

public extension AnyTransition {
    /// Sustitución con desenfoque.
    ///
    /// Lo que hace que cambiar el contenido se lea como la misma superficie
    /// pensando, en vez de como una vista nueva llegando de golpe. Combinado
    /// con un escalado mínimo porque `blurReplace` a secas puede parecer que la
    /// pantalla se ha desenfocado sin más.
    static var wkContent: AnyTransition {
        AnyTransition(.blurReplace).combined(with: .opacity)
    }

    /// Para algo que ocupa un sitio concreto y llega a él.
    static var wkPlace: AnyTransition {
        .scale(scale: 0.82)
            .combined(with: AnyTransition(.blurReplace))
            .combined(with: .opacity)
    }

    /// Entrada lateral con desenfoque, para pasos de un flujo.
    static func wkSlide(fromLeading: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: fromLeading ? .leading : .trailing)
                .combined(with: AnyTransition(.blurReplace))
                .combined(with: .opacity),
            removal: .move(edge: fromLeading ? .trailing : .leading)
                .combined(with: AnyTransition(.blurReplace))
                .combined(with: .opacity)
        )
    }
}
