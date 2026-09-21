import SwiftUI
import UIKit

/// La barra de pestañas: **solo iconos**, sin texto.
///
/// Con dos o tres destinos el texto no aporta: el icono del armario y el del
/// calendario se distinguen a la primera, y la etiqueta debajo obliga a una
/// barra más alta que se come contenido en cada pantalla.
///
/// ## Por qué envuelve un `UISegmentedControl`
///
/// Es exactamente lo que hace Lockty, y la versión hecha a mano en SwiftUI
/// —que es lo que había aquí— no llega al mismo sitio. Un control segmentado
/// del sistema trae cosas que no se reproducen con una `Capsule` y un
/// `matchedGeometryEffect`: el indicador se arrastra con el dedo de un segmento
/// a otro, la píldora se deforma al llegar al tope, el háptico es el del
/// sistema, y en iOS 26 el cristal es el de verdad y no una imitación con
/// `ultraThinMaterial`. Imitarlo se nota, y se notaba.
///
/// Lo que se le quita es el fondo y los separadores propios del control, que
/// son los que lo hacen parecer un ajuste de dos opciones en vez de los
/// destinos de la app.
public enum WKTabBarMetrics {
    /// Alto total con su margen inferior.
    ///
    /// Lo consultan sitios que no saben —ni tienen por qué— de qué tipo son las
    /// pestañas, como el modificador que coloca los accesorios flotantes.
    public static let reservedHeight: CGFloat = 60
    /// Alto de la píldora.
    ///
    /// Público porque lo consulta quien tiene que ponerse **a su misma
    /// altura**: los botones redondos del editor están en la misma franja de
    /// la pantalla, y con medidas distintas pasar de una fila a la otra se
    /// nota como un salto.
    public static let barHeight: CGFloat = 44
    /// Ancho por destino.
    static let tabWidth: CGFloat = 58

    /// Cuánto hay que subir algo para que quede **por encima** de la barra.
    ///
    /// Para quien ignora el área segura. Una vista que la respeta no necesita
    /// esto: la barra ya le ha recortado el sitio y le basta un respiro. Pero
    /// el lienzo del plan llega a los cuatro bordes a propósito, así que ahí
    /// hay que contar a mano la barra **y** el indicador de inicio de debajo.
    ///
    /// El inset se lee de la ventana y no se mide con `onGeometryChange`:
    /// dentro del plan no queda ninguna vista que todavía lo conozca —la barra
    /// se lo ha comido y el contenido lo ignora—, así que medirlo ahí da cero
    /// y la píldora acababa media tapada.
    /// El mismo aire que deja el armario, que es donde está bien: allí la
    /// barra ya le ha recortado el sitio al scroll y basta `WK.Spacing.m`
    /// desde el canto de la barra. Aquí hay que llegar a ese mismo canto
    /// contando lo que mide la barra **de verdad** —no `reservedHeight`, que
    /// lleva un margen de más y dejaba la píldora flotando ocho puntos por
    /// encima de donde debía— y el indicador de inicio de debajo.
    @MainActor
    public static var clearance: CGFloat {
        barHeight + 2 * WK.Spacing.xs + WK.Spacing.m + windowBottomInset
    }

    @MainActor
    private static var windowBottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }
}

public struct WKIconTabBar<Tab: Hashable>: View {

    private let tabs: [Tab]
    private let symbol: (Tab) -> String
    @Binding private var selection: Tab

    public init(
        tabs: [Tab],
        selection: Binding<Tab>,
        symbol: @escaping (Tab) -> String
    ) {
        self.tabs = tabs
        _selection = selection
        self.symbol = symbol
    }

    /// Índice y no el valor: `UISegmentedControl` habla de posiciones, y la
    /// traducción en los dos sentidos vive aquí para que fuera se siga usando
    /// el tipo de pestaña de siempre.
    private var selectedIndex: Binding<Int> {
        Binding(
            get: { tabs.firstIndex(of: selection) ?? 0 },
            set: { index in
                guard tabs.indices.contains(index) else { return }
                selection = tabs[index]
            }
        )
    }

    public var body: some View {
        WKSegmentedIcons(symbols: tabs.map(symbol), index: selectedIndex)
            .frame(
                width: CGFloat(tabs.count) * WKTabBarMetrics.tabWidth,
                height: WKTabBarMetrics.barHeight
            )
            .padding(WK.Spacing.xs)
            .adaptiveGlassInteractive(in: .capsule)
            .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Un control segmentado sin su fondo ni sus separadores.
///
/// ## Por qué en `layoutSubviews` y no una vez al crearlo
///
/// El fondo del control y sus divisores son `UIImageView` hijas directas; el
/// glifo de cada segmento vive más adentro. Apagar las primeras deja el control
/// que queremos: la píldora del sistema, los iconos, y nada más.
///
/// Lo que fallaba era **cuándo**. Se hacía una sola vez, en el siguiente ciclo
/// del run loop tras crear el control. Al cambiar de segmento UIKit rehace y
/// reordena esas subvistas, así que la que se había apagado volvía visible y a
/// veces se apagaba la que no era: de ahí que los iconos hicieran cosas raras
/// justo al cambiar de pestaña. Aquí se reaplica en cada pasada de layout, que
/// es exactamente cuando UIKit ha terminado de rehacerlas.
final class ChromelessSegmentedControl: UISegmentedControl {

    /// Las imágenes que hemos puesto nosotros.
    ///
    /// Sirven para reconocer los iconos **por identidad** y no por su forma:
    /// ver `layoutSubviews`. Se guardan las instancias exactas, que es lo que
    /// las hace reconocibles.
    var glyphs: [UIImage] = []

    override func layoutSubviews() {
        super.layoutSubviews()

        // **Por lo que es cada vista, no por dónde está en la lista.**
        //
        // Aquí estaba el parpadeo al cambiar de pestaña. Antes se apagaban
        // "todas menos la última", dando por hecho que la última era el glifo
        // activo — y UIKit **reordena** estas subvistas cada vez que cambia la
        // selección. Según cómo cayera el orden en esa pasada, se apagaba un
        // icono de verdad o volvía a aparecer el fondo del control. Y como el
        // alfa solo se ponía a cero y nunca se devolvía, un icono apagado por
        // error se quedaba apagado.
        //
        // El fondo y los divisores se reconocen por su forma: el fondo ocupa el
        // control entero y un divisor es una raya de un par de puntos de ancho.
        // Todo lo demás es contenido y se enciende **explícitamente**, que es
        // lo que impide que un error de una pasada se quede pegado.
        // Y además **por identidad**, que es lo único que no se equivoca nunca.
        //
        // La forma sola seguía fallando: mientras la píldora se desliza, UIKit
        // relayouta estas vistas y por una pasada el fondo puede medir menos de
        // lo que mide el control. Esa pasada lo encendía, y eso es el parpadeo.
        //
        // Los iconos los ponemos nosotros, así que se reconocen por ser
        // exactamente las imágenes que dimos. Lo que sea uno de ellos **nunca**
        // se apaga, pase lo que pase con las medidas en esa pasada; la forma
        // solo decide sobre lo que no reconocemos.
        for case let imageView as UIImageView in subviews {
            let size = imageView.bounds.size
            let isGlyph = imageView.image.map { candidate in
                glyphs.contains { $0 === candidate }
            } ?? false
            let isBackground = size.width >= bounds.width - 1 && size.height >= bounds.height - 1
            let isDivider = size.width <= 3 && size.height >= bounds.height * 0.4
            let wanted: CGFloat = !isGlyph && (isBackground || isDivider) ? 0 : 1

            // Sin animar y solo si cambia. `layoutSubviews` corre **dentro** del
            // bloque de animación con el que UIKit mueve la píldora: tocar el
            // alfa ahí sin más lo anima, y un icono que se funde mientras la
            // píldora viaja es justo lo que se veía.
            guard imageView.alpha != wanted else { continue }
            UIView.performWithoutAnimation { imageView.alpha = wanted }
        }
    }
}

/// El control segmentado del sistema, con su cromo apagado.
private struct WKSegmentedIcons: UIViewRepresentable {
    let symbols: [String]
    @Binding var index: Int

    func makeUIView(context: Context) -> ChromelessSegmentedControl {
        let control = ChromelessSegmentedControl(items: symbols)
        control.selectedSegmentIndex = index
        control.apportionsSegmentWidthsByContent = false
        // La píldora, dibujada por UIKit. **No se sustituye por una imagen de
        // fondo**: en cuanto se le da una, el control deja de animar el
        // indicador de un segmento a otro y lo pinta cuadrado y a saltos. Ese
        // arrastre es justo lo que se venía a buscar al usar el control del
        // sistema en vez de una cápsula hecha a mano.
        control.selectedSegmentTintColor = UIColor.label.withAlphaComponent(0.10)
        // El icono **no cambia de color** entre seleccionado y no: lo que marca
        // la selección es la píldora de debajo. Con el icono invertido, la
        // barra se lee como un control de dos opciones excluyentes de un ajuste
        // y no como los destinos de la app.
        control.tintColor = .label

        draw(symbols: symbols, in: control)
        context.coordinator.drawnScheme = context.environment.colorScheme
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.didSelect(_:)),
            for: .valueChanged
        )
        return control
    }

    func updateUIView(_ control: ChromelessSegmentedControl, context: Context) {
        // **Los iconos no se vuelven a dibujar al cambiar de pestaña.** No
        // cambian: ni el dibujo ni el color. Redibujarlos en cada cambio
        // obligaba a UIKit a rehacer sus vistas justo mientras la píldora se
        // desliza, y ahí es donde se colaba el parpadeo. Lo único que los
        // cambia es el tema del sistema, así que se rehacen cuando cambia ese
        // y en ningún otro momento.
        if context.coordinator.drawnScheme != context.environment.colorScheme {
            context.coordinator.drawnScheme = context.environment.colorScheme
            draw(symbols: symbols, in: control)
        }

        // Y la selección, solo si de verdad cambió. SwiftUI llama a esto en
        // cada repintado en el que participa la vista.
        guard control.selectedSegmentIndex != index else { return }
        control.selectedSegmentIndex = index
    }

    /// Pone los iconos, ya teñidos y sin plantilla.
    ///
    /// `.alwaysOriginal` y no `.alwaysTemplate`: una imagen de plantilla la
    /// vuelve a teñir UIKit por cada estado del segmento —normal, seleccionado,
    /// resaltado— y ese repintado es trabajo por nada, porque aquí el icono se
    /// ve igual en los tres. Ya teñida, es un mapa de bits fijo que UIKit
    /// coloca y no toca.
    private func draw(symbols: [String], in control: ChromelessSegmentedControl) {
        let images = symbols.map { Self.image(for: $0, traits: control.traitCollection) }
        control.glyphs = images.compactMap { $0 }
        for (position, image) in images.enumerated() {
            control.setImage(image, forSegmentAt: position)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: ChromelessSegmentedControl,
        context: Context
    ) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: WKSegmentedIcons
        /// Con qué tema se dibujaron las imágenes del control. Es lo único que
        /// obliga a volver a dibujarlas.
        var drawnScheme: ColorScheme?

        init(parent: WKSegmentedIcons) { self.parent = parent }

        @objc
        func didSelect(_ control: UISegmentedControl) {
            parent.index = control.selectedSegmentIndex
        }
    }

    /// Un símbolo del sistema y, si no lo es, un recurso del catálogo.
    ///
    /// Un nombre que no es un SF Symbol devuelve `nil` sin quejarse, y el
    /// segmento se queda vacío sin que nada lo diga.
    private static func image(for symbol: String, traits: UITraitCollection) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(
            font: .systemFont(ofSize: 19, weight: .regular)
        )
        let base = UIImage(systemName: symbol, withConfiguration: configuration)
            ?? UIImage(named: symbol)
        // Teñida aquí, con el color ya resuelto para el tema de ahora. Ver
        // `draw(symbols:in:)`: lo que se busca es que UIKit no tenga nada que
        // recalcular cuando cambia la selección.
        return base?.withTintColor(
            UIColor.label.resolvedColor(with: traits),
            renderingMode: .alwaysOriginal
        )
    }
}

// La versión hecha a mano en SwiftUI. Se queda comentada y no se borra: es la
// que hay que volver a poner si algún día el control del sistema estorba —por
// ejemplo con más de tres destinos, donde el segmentado empieza a apretar.
//
// private struct WKIconTab: View {
//     let symbol: String
//     let isSelected: Bool
//     let indicator: Namespace.ID
//     let action: () -> Void
//
//     var body: some View {
//         Button(action: action) {
//             Image(systemName: symbol)
//                 .font(.system(size: 19, weight: .regular))
//                 .foregroundStyle(WK.Palette.primaryText)
//                 .frame(width: 58, height: 44)
//                 .background {
//                     if isSelected {
//                         Capsule()
//                             .fill(WK.Palette.ink(0.10))
//                             .matchedGeometryEffect(id: "tab-indicator", in: indicator)
//                     }
//                 }
//                 .contentShape(.capsule)
//         }
//         .buttonStyle(WKPressStyle())
//         .sensoryFeedback(.selection, trigger: isSelected)
//     }
// }
