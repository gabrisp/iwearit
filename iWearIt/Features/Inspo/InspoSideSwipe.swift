import SwiftUI
import UIKit

/// Arrastrar una tarjeta a los lados **sin quitarle el scroll a la lista**.
///
/// ## Por qué no es un `DragGesture`
///
/// Porque un `DragGesture` de SwiftUI puesto sobre el contenido de un
/// `ScrollView` se queda con el dedo. Aunque el gesto decida a la primera que
/// el movimiento es vertical y no haga nada, ya ha ganado la partida: el
/// scroll deja de moverse mientras el dedo esté encima de una tarjeta, y solo
/// funciona arrastrando por los márgenes. Eso es exactamente lo que pasaba
/// aquí —"el scroll solo va si lo hago por fuera"— y no se arregla mirando la
/// dirección dentro del `onChanged`, porque para entonces ya es tarde.
///
/// Lo que sí lo arregla es contestar a la pregunta **antes** de empezar, y esa
/// pregunta la hace UIKit: `gestureRecognizerShouldBegin`. Si el dedo va hacia
/// abajo, este gesto dice que no y el scroll se queda con el movimiento, como
/// si no hubiera nada puesto encima. `UIGestureRecognizerRepresentable`
/// (iOS 18) es lo que permite usar esa pregunta desde SwiftUI.
struct SideSwipeGesture: UIGestureRecognizerRepresentable {
    /// Cuánto se lleva arrastrado de lado, en puntos.
    let onChange: (CGFloat) -> Void
    /// Al soltar: lo arrastrado y a qué velocidad iba.
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view)
        switch recognizer.state {
        case .began, .changed:
            onChange(translation.x)
        case .ended:
            onEnd(translation.x, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            // Cancelado a medias —una llamada, el gesto del sistema— es que no
            // ha pasado nada: vuelve a su sitio.
            onEnd(0, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// **La pregunta que lo decide todo.**
        ///
        /// Se contesta con la velocidad del primer movimiento, que es la
        /// intención del dedo antes de que la tarjeta se haya movido un píxel.
        /// Más horizontal que vertical: es un descarte o un me gusta. Si no,
        /// esto no se entera y el gesto es de la lista.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        /// Y conviviendo con lo demás: el scroll sigue siguiendo el dedo, y el
        /// doble toque y la pulsación larga de la tarjeta siguen ahí. Sin
        /// esto, el primero en reconocer deja mudos a los otros.
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// Pone —o no— el arrastre a los lados sobre una tarjeta.
///
/// En un modificador y no en un `if` dentro del cuerpo porque cambiar de rama
/// destruiría la tarjeta y volvería a construirla al girar el iPad: lo que se
/// quita es el gesto, no la vista.
struct SideSwipeArbitration: ViewModifier {
    enum Phase {
        case change(CGFloat)
        case end(CGFloat, CGFloat)
    }

    let isOn: Bool
    let onPhase: (Phase) -> Void

    func body(content: Content) -> some View {
        if isOn {
            content.gesture(
                SideSwipeGesture(
                    onChange: { onPhase(.change($0)) },
                    onEnd: { distance, velocity in onPhase(.end(distance, velocity)) }
                )
            )
        } else {
            content
        }
    }
}
