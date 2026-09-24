import SwiftUI

/// Paso de página como tarjetas: la pantalla que se va **se encoge** —con sus
/// esquinas redondeadas y su borde, como en el selector de apps—, se aparta
/// hacia un lado, y la siguiente llega por el otro y **crece** hasta ocupar la
/// pantalla. Hacia atrás, lo mismo al revés.
///
/// ## Por qué en tres tiempos y no todo a la vez
///
/// Encoger y deslizar a la vez se lee como un zoom torcido. Separado —primero
/// se vuelve tarjeta, luego se mueve, luego la nueva deja de serlo— se lee
/// como lo que es: dejar una hoja a un lado y coger la siguiente.
///
///   tiempo  0 ───── 0,3 ─────────── 0,75 ───── 1
///   sale    encoge  ·  se desliza      ·  fuera
///   entra   fuera   ·  se desliza      ·  crece
///
/// Los dos deslizamientos van en la misma ventana: por eso las dos tarjetas se
/// mueven juntas, pegadas, y nunca se montan una encima de la otra.
///
/// - Important: la animación tiene que ser **lineal** (`WKPageCardTransition.
///   animation`): cada tramo ya lleva su propia curva suave dentro, y una curva
///   encima deformaría las ventanas y las dos tarjetas dejarían de ir a la par.
public enum WKPageCardTransition {
    /// Lenta y lineal: ver la nota de arriba.
    public static let animation = Animation.linear(duration: 0.8)

    /// - Parameters:
    ///   - isGoingBack: hacia atrás, la que sale va a la derecha y la nueva
    ///     entra por la izquierda.
    ///   - insets: los márgenes seguros de la pantalla, para recortar la
    ///     tarjeta a la pantalla **entera** y no solo al marco de la vista —
    ///     sin ellos, al volverse tarjeta se cortaba de golpe el fondo bajo la
    ///     barra de estado—.
    ///
    /// Con `.modifier(active:identity:)` y no con un `Transition` propio: este
    /// último, con el efecto dentro, no llegaba a aplicarse y SwiftUI caía a un
    /// fundido. Así cada lado lleva su efecto fijo y solo se interpola el
    /// progreso.
    public static func transition(isGoingBack: Bool, insets: EdgeInsets) -> AnyTransition {
        let forward: CGFloat = isGoingBack ? -1 : 1
        func effect(_ progress: Double, leaving: Bool) -> PageCardEffect {
            PageCardEffect(
                progress: progress,
                isLeaving: leaving,
                side: leaving ? -forward : forward,
                insets: insets
            )
        }
        return .asymmetric(
            insertion: .modifier(active: effect(1, leaving: false), identity: effect(0, leaving: false)),
            removal: .modifier(active: effect(1, leaving: true), identity: effect(0, leaving: true))
        )
    }
}

/// El efecto, con un único progreso animable: 0 es la pantalla en reposo y 1
/// la tarjeta fuera de la pantalla.
nonisolated struct PageCardEffect: ViewModifier, Animatable {
    var progress: Double
    let isLeaving: Bool
    let side: CGFloat
    let insets: EdgeInsets

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// Cuánto encoge una tarjeta: lo justo para que se vean el borde y el
    /// fondo de detrás.
    private static let minimumScale = 0.86
    private static let cornerRadius: CGFloat = 44

    func body(content: Content) -> some View {
        // Los tramos, en tiempo de la animación. La que sale recorre el
        // progreso de 0 a 1 y la que entra de 1 a 0, así que sus ventanas se
        // escriben distintas para caer en el mismo momento.
        let shrink: Double
        let slide: Double
        if isLeaving {
            shrink = Self.ease(progress / 0.3)
            slide = Self.ease((progress - 0.3) / 0.45)
        } else {
            shrink = Self.ease(progress / 0.25)
            slide = Self.ease((progress - 0.25) / 0.45)
        }
        let scale = 1 - (1 - Self.minimumScale) * shrink
        let radius = Self.cornerRadius * shrink
        let card = ExpandedRoundedRectangle(cornerRadius: radius, insets: insets)

        return content
            .clipShape(card)
            .overlay {
                card.stroke(Color.primary.opacity(0.14 * shrink), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12 * shrink), radius: 24, y: 10)
            .scaleEffect(scale)
            .visualEffect { view, proxy in
                // Un poco más que el ancho, para que la sombra también salga.
                view.offset(x: side * slide * (proxy.size.width + 40))
            }
    }

    /// Curva suave dentro de un tramo, con el tramo acotado a 0...1.
    private static func ease(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}

/// Un rectángulo redondeado del tamaño de la pantalla entera: el marco de la
/// vista más sus márgenes seguros.
private struct ExpandedRoundedRectangle: Shape {
    var cornerRadius: CGFloat
    var insets: EdgeInsets

    func path(in rect: CGRect) -> Path {
        let full = CGRect(
            x: rect.minX - insets.leading,
            y: rect.minY - insets.top,
            width: rect.width + insets.leading + insets.trailing,
            height: rect.height + insets.top + insets.bottom
        )
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: full)
    }
}
