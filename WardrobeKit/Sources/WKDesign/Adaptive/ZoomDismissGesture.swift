import os
import SwiftUI
import UIKit

/// Quita el cierre interactivo que instala la transición de zoom.
///
/// ## Qué son y dónde están
///
/// `navigationTransition(.zoom)` no se limita a animar la entrada: le cuelga a
/// la pantalla empujada **tres gestos** para poder cerrarla con el dedo. Se
/// llaman por su nombre y se pueden leer:
///
/// ```
/// com.apple.UIKit.ZoomInteractiveDismissLeadingEdgePan
/// com.apple.UIKit.ZoomInteractiveDismissPan
/// com.apple.UIKit.ZoomInteractiveDismissPinch
/// ```
///
/// Tres, no uno: el arrastre desde el borde, el arrastre normal y el pellizco.
/// Quitar solo el que se nota deja los otros dos puestos.
///
/// Viven en la vista del **controlador que se empuja**, no en la del
/// `UINavigationController`. Por eso apagar el `interactivePopGestureRecognizer`
/// no los tocaba, y por eso un barrido sobre la vista de la pila tampoco los
/// encontraba: se estaba mirando el sitio equivocado.
///
/// ## Por qué importan aquí
///
/// El editor del lienzo se maneja arrastrando y pellizcando. Con estos puestos,
/// arrastrar una prenda hacia abajo cerraba la pantalla, y pellizcar para
/// escalar competía con el pellizco de cierre. La animación de entrada sí se
/// quiere —la prenda crece desde su celda—; lo que sobra es la salida.
///
/// ## Por qué se quitan y no se apagan
///
/// Apagarlos obligaría a devolverlos como estaban, y no hace falta: pertenecen
/// a la vista de esta pantalla, que se destruye al volver. Quitarlos no deja
/// nada que restaurar.
public extension View {
    func zoomDismissDisabled(_ disabled: Bool = true) -> some View {
        background(ZoomDismissGate(isDisabled: disabled))
    }
}

private let logger = Logger(subsystem: "com.gabrisp.iWearIt", category: "zoom-dismiss")

private struct ZoomDismissGate: UIViewRepresentable {
    let isDisabled: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        // **Invisible y sorda**: está aquí para alcanzar la jerarquía de
        // UIKit, no para recibir toques. Dejándola interactiva se comería los
        // del contenido que la tiene de fondo.
        view.isUserInteractionEnabled = false
        if isDisabled { Self.removeZoomGestures(around: view) }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        // También aquí, y no solo al crearla: la pantalla puede reaparecer sin
        // que se construya otra vista —al volver de una hoja, por ejemplo— y
        // ahí la transición vuelve a instalar los suyos.
        guard isDisabled else { return }
        Self.removeZoomGestures(around: view)
    }

    /// Lo que identifica a los de la transición.
    ///
    /// Por `contains` y no por el prefijo completo
    /// (`com.apple.UIKit.ZoomInteractiveDismiss…`): el trozo estable del nombre
    /// es este, y si UIKit reorganiza el espacio de nombres o añade un cuarto
    /// gesto, sigue casando en vez de volver a colarse en silencio.
    private static let marker = "ZoomInteractive"

    private static func removeZoomGestures(around view: UIView) {
        // En el siguiente ciclo del run loop: la transición los instala
        // **después** de que la pantalla aparezca, así que mirar ahora mismo no
        // encuentra ninguno y parece que ya está hecho.
        DispatchQueue.main.async {
            guard let host = view.enclosingViewController?.view else {
                logger.warning("no se encontró el controlador: los gestos de zoom siguen puestos")
                return
            }

            var removed: [String] = []
            for recognizer in host.gestureRecognizers ?? []
            where (recognizer.name ?? "").contains(marker) {
                host.removeGestureRecognizer(recognizer)
                removed.append(recognizer.name ?? "?")
            }

            // Se anota **siempre**, también cuando no quita ninguno: "no había
            // ninguno" y "no llegué a mirar" se ven igual desde fuera, y es
            // justo la diferencia que hay que poder comprobar cuando el gesto
            // vuelve a colarse.
            logger.info("gestos de zoom quitados: \(removed.isEmpty ? "ninguno" : removed.joined(separator: ", "), privacy: .public)")
        }
    }
}

private extension UIView {
    /// El controlador que contiene esta vista, por la cadena de respondedores.
    ///
    /// SwiftUI mete la vista de un representable muy adentro, así que subir por
    /// `superview` no llega. La cadena de respondedores sí.
    var enclosingViewController: UIViewController? {
        sequence(first: self as UIResponder) { $0.next }
            .compactMap { $0 as? UIViewController }
            .first
    }
}
