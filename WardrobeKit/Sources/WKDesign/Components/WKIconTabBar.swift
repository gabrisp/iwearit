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
    static let barHeight: CGFloat = 44
    /// Ancho por destino.
    static let tabWidth: CGFloat = 58
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
    override func layoutSubviews() {
        super.layoutSubviews()
        // Todas menos la última: la última es el glifo del segmento activo, y
        // apagarla deja la barra vacía.
        for view in subviews.dropLast() where view is UIImageView {
            view.alpha = 0
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

        for (position, symbol) in symbols.enumerated() {
            control.setImage(Self.image(for: symbol), forSegmentAt: position)
        }
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.didSelect(_:)),
            for: .valueChanged
        )
        return control
    }

    func updateUIView(_ control: ChromelessSegmentedControl, context: Context) {
        // Solo si de verdad cambió. SwiftUI llama a esto en cada repintado en
        // el que participa la vista.
        guard control.selectedSegmentIndex != index else { return }
        control.selectedSegmentIndex = index
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
        /// Con qué tema se dibujaron las imágenes del control.
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
    private static func image(for symbol: String) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(
            font: .systemFont(ofSize: 19, weight: .regular)
        )
        return UIImage(systemName: symbol, withConfiguration: configuration)
            ?? UIImage(named: symbol)?.withRenderingMode(.alwaysTemplate)
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
