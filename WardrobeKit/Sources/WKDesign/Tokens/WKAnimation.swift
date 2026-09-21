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

    /// Cambio de modo sobre el mismo contenido: entra desde arriba y sale por
    /// abajo, siempre con opacidad.
    ///
    /// Asimétrica a propósito. Con la misma dirección en los dos sentidos las
    /// dos vistas se cruzan —una sube mientras la otra baja por el mismo
    /// sitio— y se lee como un parpadeo con ruido. Yendo las dos hacia abajo,
    /// lo que se ve es una capa que se aparta y otra que ocupa su lugar.
    ///
    /// Y con movimiento y no solo opacidad: dos contenidos distintos
    /// fundiéndose sin moverse no dicen de dónde viene el nuevo.
    static var wkVertical: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    /// Pasar de una vista general al detalle, **por el lado del detalle**.
    ///
    /// ## Por qué solo se anima un sentido
    ///
    /// Alejarse y acercarse no son el mismo gesto al revés. Al alejarse, lo que
    /// llega es un montón de cosas pequeñas colocándose cada una en su sitio: ya
    /// hay movimiento de sobra y añadirle más al contenedor lo emborrona. Al
    /// acercarse no llega nada que se coloque —llega **una** cosa, a pantalla
    /// completa— y sin movimiento eso es un fundido y se lee como un corte.
    ///
    /// Por eso este par es asimétrico en el sentido menos obvio: el detalle
    /// **entra** creciendo y **sale** sin más.
    ///
    /// Los dos lados crecen a la vez —el que se va se pasa de largo, el que
    /// llega se coloca— porque eso es lo que hace que se lea como acercarse y
    /// no como dos vistas cambiándose el turno.
    static var wkDetailReturn: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.94).combined(with: .opacity),
            removal: .opacity
        )
    }

    /// Y el mismo paso **por el lado de la vista general**: se queda quieta al
    /// llegar y se pasa de largo al irse.
    static var wkOverviewLeave: AnyTransition {
        .asymmetric(
            insertion: .opacity,
            removal: .scale(scale: 1.08).combined(with: .opacity)
        )
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
