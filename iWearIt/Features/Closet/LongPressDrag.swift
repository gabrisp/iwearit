import SwiftUI
import UIKit

/// Mantener pulsado y arrastrar, con el reconocedor de **UIKit**.
///
/// ## Por qué no el de SwiftUI
///
/// Con `LongPressGesture` encadenado a un `DragGesture` sobre cada prenda, el
/// scroll que las contiene esperaba a ese gesto antes de moverse: si el dedo
/// empezaba encima de una prenda, ni la balda se desplazaba de lado ni el
/// armario hacia abajo. Solo funcionaba empezando en un hueco.
///
/// El de UIKit se lleva bien con el scroll de toda la vida: si el dedo se
/// mueve antes de tiempo, la pulsación larga falla y el scroll sigue; si se
/// queda quieto el tiempo justo, la pulsación gana, el scroll ya no arranca y
/// el botón de debajo no recibe el toque. Y avisa también de la cancelación,
/// así que el arrastre nunca se queda a medias.
struct LongPressDrag: UIGestureRecognizerRepresentable {
    var minimumDuration: TimeInterval = 0.35
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    /// **Convivir con el botón, no con el scroll.** La prenda es un botón, y
    /// su propio reconocimiento del toque se quedaba el dedo: la pulsación
    /// larga no llegaba a empezar. Se deja reconocer a la vez con todo
    /// **menos** con el arrastre del scroll, que es justo con quien tiene que
    /// competir: o se coge la prenda o se desplaza la balda, las dos cosas no.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            !(other is UIPanGestureRecognizer)
        }
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.minimumPressDuration = minimumDuration
        // Lo que se puede mover el dedo antes de que cuente como desplazar
        // la balda en vez de coger la prenda.
        recognizer.allowableMovement = 10
        return recognizer
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context
    ) {
        let point = context.converter.location(in: .named(ShelfDragModel.space))
        switch recognizer.state {
        case .began: onBegan(point)
        case .changed: onChanged(point)
        case .ended, .cancelled, .failed: onEnded()
        default: break
        }
    }
}
