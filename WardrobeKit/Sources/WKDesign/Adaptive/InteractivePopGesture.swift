import SwiftUI
import UIKit

/// Desactiva el gesto de volver deslizando desde el borde.
///
/// `navigationBarBackButtonHidden(true)` esconde el botón pero **no toca el
/// gesto**: UIKit lo deja activo, y en una pantalla llena de arrastres —el
/// editor del lienzo— deslizar una prenda pegada al borde izquierdo cierra la
/// pantalla a mitad de colocarla.
///
/// SwiftUI no expone nada para esto, así que hace falta alcanzar el
/// `UINavigationController`. Es un representable diminuto y sin vista propia,
/// que es la única forma correcta de meter UIKit aquí: aislado, con una sola
/// responsabilidad y sin filtrar nada al resto del árbol.
public extension View {
    func interactivePopDisabled(_ disabled: Bool = true) -> some View {
        background(InteractivePopGate(isDisabled: disabled))
    }
}

private struct InteractivePopGate: UIViewControllerRepresentable {
    let isDisabled: Bool

    func makeUIViewController(context: Context) -> Gate {
        Gate()
    }

    func updateUIViewController(_ controller: Gate, context: Context) {
        controller.isDisabled = isDisabled
        controller.apply()
    }

    final class Gate: UIViewController {
        var isDisabled = false
        /// Lo que había antes, para dejarlo como estaba al salir. Apagar el
        /// gesto y no volver a encenderlo rompería la navegación del resto de
        /// la app, que es peor que el problema que resuelve.
        private var previous: Bool?


        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        func apply() {
            guard let recognizer = enclosingNavigationController?.interactivePopGestureRecognizer
            else {
                // Todavía no está en la pila. Se reintenta en el siguiente
                // ciclo: `didMove` llega antes de que SwiftUI haya terminado de
                // empujar la pantalla, y ahí `navigationController` aún es nil.
                DispatchQueue.main.async { [weak self] in self?.retryOnce() }
                return
            }
            if previous == nil { previous = recognizer.isEnabled }
            recognizer.isEnabled = isDisabled ? false : (previous ?? true)
        }

        private var hasRetried = false

        private func retryOnce() {
            guard !hasRetried else { return }
            hasRetried = true
            apply()
        }

        /// El `UINavigationController` que contiene esta pantalla.
        ///
        /// Por la **cadena de respondedores** y no por `navigationController`:
        /// SwiftUI mete el controlador de un representable como hijo del
        /// alojador, y ese hijo no siempre ve la pila por la cadena de padres
        /// —que es por lo que el gesto seguía activo aunque lo apagáramos—.
        /// La cadena de respondedores sí llega.
        private var enclosingNavigationController: UINavigationController? {
            if let direct = navigationController { return direct }
            var responder: UIResponder? = view
            while let current = responder {
                if let navigation = current as? UINavigationController { return navigation }
                responder = current.next
            }
            return nil
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let previous {
                enclosingNavigationController?
                    .interactivePopGestureRecognizer?.isEnabled = previous
            }
        }
    }
}

/// Devuelve el gesto de volver a una pantalla que esconde la barra.
///
/// Es el problema contrario al de arriba y **no se arregla igual**. Al poner
/// `toolbarVisibility(.hidden, for: .navigationBar)`, el gesto sigue activo
/// —`isEnabled` es `true`— pero su delegado, que es interno de UIKit, responde
/// que no debe empezar: para el sistema, una pila sin barra visible no es una
/// pila por la que se pueda volver deslizando. De ahí que encender `isEnabled`
/// no cambiara nada.
///
/// Lo que sí funciona es poner un delegado propio que diga que sí mientras haya
/// algo debajo en la pila. Y se restaura el que había al salir: dejar el nuestro
/// puesto cambiaría el comportamiento de todas las pantallas que vengan después.
/// - Parameter canPop: si en este momento deslizar debe **salir** de la
///   pantalla. Existe porque el borde izquierdo lo quieren dos cosas a la vez:
///   volver atrás y pasar página del cuaderno. Dentro de un viaje, la página
///   manda —deslizar es ir al día anterior— y solo en el primer día, cuando ya
///   no hay página detrás, el gesto sale de la maleta. Por defecto, siempre.
public extension View {
    func interactivePopEnabled(when canPop: @escaping () -> Bool = { true }) -> some View {
        background(InteractivePopForcer(canPop: canPop))
    }
}

private struct InteractivePopForcer: UIViewControllerRepresentable {
    let canPop: () -> Bool

    func makeUIViewController(context: Context) -> Forcer {
        let controller = Forcer()
        controller.canPop = canPop
        return controller
    }

    func updateUIViewController(_ controller: Forcer, context: Context) {
        // El cierre se renueva en cada pasada: capturado una sola vez en
        // `make`, seguiría leyendo el día en el que se abrió la pantalla.
        controller.canPop = canPop
        controller.apply()
    }

    final class Forcer: UIViewController, UIGestureRecognizerDelegate {
        var canPop: () -> Bool = { true }
        private weak var navigation: UINavigationController?
        private weak var previousDelegate: (any UIGestureRecognizerDelegate)?
        private var isInstalled = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        func apply() {
            guard
                let navigation = enclosingNavigationController,
                let recognizer = navigation.interactivePopGestureRecognizer
            else {
                DispatchQueue.main.async { [weak self] in self?.retryOnce() }
                return
            }
            self.navigation = navigation
            recognizer.isEnabled = true
            guard !isInstalled else { return }
            isInstalled = true
            // Solo se guarda si es de otro: al volver a entrar, el delegado que
            // hay puesto podría ser el nuestro de la visita anterior, y
            // guardarlo sería restaurarnos a nosotros mismos para siempre.
            if recognizer.delegate !== self { previousDelegate = recognizer.delegate }
            recognizer.delegate = self
        }

        private var hasRetried = false

        private func retryOnce() {
            guard !hasRetried else { return }
            hasRetried = true
            apply()
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            // Dos condiciones. Que haya una pantalla debajo —sin esto,
            // deslizar en la raíz deja la pila en un estado del que no vuelve,
            // el fallo clásico de poner el delegado a `nil`— y que quien aloja
            // esto no esté usando ese mismo borde para otra cosa.
            (navigation?.viewControllers.count ?? 0) > 1 && canPop()
        }

        func gestureRecognizer(
            _ gesture: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // Nunca a la vez que otro. Un lienzo con arrastres dentro y el
            // gesto de volver corriendo juntos mueve la prenda **y** cierra la
            // pantalla con el mismo dedo.
            false
        }

        /// Igual que arriba: por la cadena de respondedores, no por `parent`.
        private var enclosingNavigationController: UINavigationController? {
            if let direct = navigationController { return direct }
            var responder: UIResponder? = view
            while let current = responder {
                if let navigation = current as? UINavigationController { return navigation }
                responder = current.next
            }
            return nil
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard isInstalled, let previousDelegate else { return }
            navigation?.interactivePopGestureRecognizer?.delegate = previousDelegate
            isInstalled = false
        }
    }
}
