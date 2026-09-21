import SwiftUI
import UIKit

/// Paso de página con efecto libro, restringido al borde de la pantalla.
///
/// ## El conflicto que resuelve
///
/// El canvas libre quiere el pan a pantalla completa para arrastrar prendas sin
/// long-press previo. `UIPageViewController` con `pageCurl` quiere ese mismo
/// pan para pasar página. No pueden coexistir tal cual.
///
/// La solución no es desactivar el gesto interno —eso mataría el curl
/// interactivo que sigue al dedo— sino **filtrarlo por delegado**: el pan solo
/// arranca si el toque empieza a menos de `edgeWidth` del borde. El resto de la
/// superficie queda libre para manipular prendas.
///
/// - Important: `pageCurl` exige páginas **opacas**. Una página transparente
///   produce artefactos al enrollarse, así que el contenido lleva fondo propio.
public struct EdgeCurlPager<Page: View>: UIViewControllerRepresentable {

    /// Ancho de la zona sensible, en puntos, a cada lado.
    public static var edgeWidth: CGFloat { 28 }

    @Binding private var index: Int
    private let content: (Int) -> Page
    /// Hasta dónde llega el cuaderno, si tiene final.
    ///
    /// El planificador no lo pasa: los días no se acaban. Una maleta **sí** lo
    /// pasa, porque un viaje dura lo que dura — y sin esto se podía seguir
    /// pasando página después del último día, donde se repetía el mismo día
    /// una y otra vez como si el viaje continuara.
    private let bounds: ClosedRange<Int>?

    public init(
        index: Binding<Int>,
        bounds: ClosedRange<Int>? = nil,
        @ViewBuilder content: @escaping (Int) -> Page
    ) {
        _index = index
        self.bounds = bounds
        self.content = content
    }

    public func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .systemBackground
        controller.isDoubleSided = false

        // Aquí está el truco: interceptamos los gestos internos en vez de
        // sustituirlos, para conservar el curl que sigue al dedo.
        for recognizer in controller.gestureRecognizers {
            recognizer.delegate = context.coordinator
        }

        controller.setViewControllers(
            [context.coordinator.host(for: index, content: content)],
            direction: .forward,
            animated: false
        )
        return controller
    }

    public func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.content = content
        context.coordinator.bounds = bounds
        guard context.coordinator.currentIndex != index else { return }

        let direction: UIPageViewController.NavigationDirection =
            index > context.coordinator.currentIndex ? .forward : .reverse
        context.coordinator.currentIndex = index
        controller.setViewControllers(
            [context.coordinator.host(for: index, content: content)],
            direction: direction,
            animated: true
        )
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(index: $index, bounds: bounds, content: content)
    }

    @MainActor
    public final class Coordinator: NSObject, UIPageViewControllerDataSource,
                                    UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var currentIndex: Int
        var content: (Int) -> Page
        var bounds: ClosedRange<Int>?
        private let binding: Binding<Int>

        init(
            index: Binding<Int>,
            bounds: ClosedRange<Int>?,
            content: @escaping (Int) -> Page
        ) {
            self.binding = index
            self.currentIndex = index.wrappedValue
            self.bounds = bounds
            self.content = content
        }

        /// Devolver `nil` aquí es lo que hace que el pager **no deje** pasar de
        /// página: el curl ni siquiera empieza, así que el final del viaje se
        /// nota en el dedo y no en una página repetida.
        private func page(at index: Int) -> PageHost<Page>? {
            if let bounds, !bounds.contains(index) { return nil }
            return host(for: index, content: content)
        }

        func host(for index: Int, content: (Int) -> Page) -> PageHost<Page> {
            let controller = PageHost(rootView: content(index))
            controller.index = index
            // Opaco: `pageCurl` no sabe enrollar una página transparente.
            controller.view.backgroundColor = .systemBackground
            controller.view.isOpaque = true
            return controller
        }

        // MARK: Páginas

        public func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let page = viewController as? PageHost<Page> else { return nil }
            return self.page(at: page.index - 1)
        }

        public func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let page = viewController as? PageHost<Page> else { return nil }
            return self.page(at: page.index + 1)
        }

        public func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard
                completed,
                let page = pageViewController.viewControllers?.first as? PageHost<Page>
            else { return }
            currentIndex = page.index
            binding.wrappedValue = page.index
        }

        // MARK: El filtro de borde

        public nonisolated func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            MainActor.assumeIsolated {
                guard let view = gestureRecognizer.view else { return true }
                let x = gestureRecognizer.location(in: view).x
                let edge = EdgeCurlPager.edgeWidth
                let isPan = gestureRecognizer is UIPanGestureRecognizer

                // Los taps de `pageCurl` —tocar el margen para pasar página— no
                // compiten con el arrastre de prendas, así que no se filtran
                // por borde; el arrastre sí.
                if isPan, x > edge, x < view.bounds.width - edge { return false }

                // **Y el tope del cuaderno se comprueba aquí, no al pedir la
                // página.** `pageCurl` da por hecho que si el gesto empieza hay
                // página a la que ir: si el origen de datos devuelve `nil` con
                // el curl ya en marcha, UIKit **revienta** —"the number of view
                // controllers provided (0) doesn't match the number required
                // (1)"—. Así que el final del viaje se nota antes, impidiendo
                // que el gesto arranque.
                guard let bounds else { return true }
                let goingBack = x < view.bounds.width / 2
                return bounds.contains(goingBack ? currentIndex - 1 : currentIndex + 1)
            }
        }
    }
}

/// `UIHostingController` que recuerda qué página es.
public final class PageHost<Content: View>: UIHostingController<Content> {
    var index = 0

    override init(rootView: Content) {
        super.init(rootView: rootView)
        // **Sin área segura.** `UIHostingController` la aplica a su contenido
        // por defecto, así que la página empezaba por debajo de la hora y el
        // papel de puntos dejaba una franja muerta arriba. El lienzo es la hoja
        // entera, de borde a borde; lo que tenga que respetar márgenes los pone
        // por su cuenta.
        safeAreaRegions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
}
