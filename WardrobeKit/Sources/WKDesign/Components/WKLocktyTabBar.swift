import SwiftUI
import UIKit

/// La barra de pestañas de Lockty, **copiada tal cual**: solo cambian los iconos.
///
/// Es `MorphingTabBar` + `MorphingSegmentedControl` de Lockty con el panel
/// que se expande quitado (aquí no hay panel: con `progress` siempre a cero
/// `ExpandableGlassEffect` se queda en la etiqueta con su cristal, que es lo
/// que queda aquí). El control segmentado es el de Lockty línea por línea:
/// imágenes puestas **una vez** al crearlo, el fondo apagado **una vez** en el
/// siguiente ciclo, y en cada actualización solo la selección si cambió. La de
/// Lockty no parpadea; la nuestra, a fuerza de "arreglarla", sí.
///
/// ## Una barra por pantalla raíz
///
/// Cada pantalla raíz pone la suya dentro de su pila de navegación, y por eso
/// una pantalla empujada la **tapa** en vez de hacerla desaparecer. La barra
/// de cada pestaña sabe cuál es la suya (`home`) y vuelve a marcarla en cuanto
/// sale de la ventana: así la de la pestaña a la que llegas ya está en su
/// sitio antes de verse, y no enseña un instante la pestaña de antes.
public struct WKLocktyTabBar<Tab: Hashable>: View {
    private let tabs: [Tab]
    private let home: Tab
    private let symbol: (Tab) -> String
    @Binding private var selection: Tab

    public init(
        tabs: [Tab],
        home: Tab,
        selection: Binding<Tab>,
        symbol: @escaping (Tab) -> String
    ) {
        self.tabs = tabs
        self.home = home
        _selection = selection
        self.symbol = symbol
    }

    public var body: some View {
        let labelSize = CGSize(width: WKLocktyTabBarMetrics.width, height: WKLocktyTabBarMetrics.height)
        let homeIndex = tabs.firstIndex(of: home) ?? 0
        let index = Binding {
            tabs.firstIndex(of: selection) ?? homeIndex
        } set: { newValue in
            guard tabs.indices.contains(newValue) else { return }
            selection = tabs[newValue]
        }

        MorphingSegmentedControl(
            symbols: tabs.map(symbol),
            homeIndex: homeIndex,
            index: index
        ) { image in
            let font = UIFont.systemFont(ofSize: 19, weight: .regular)
            let configuration = UIImage.SymbolConfiguration(font: font)
            return UIImage(systemName: image, withConfiguration: configuration)
                ?? UIImage(named: image)?.withRenderingMode(.alwaysTemplate)
        }
        .frame(height: 48)
        .padding(.horizontal, 2)
        .offset(y: -0.7)
        .frame(width: labelSize.width, height: labelSize.height)
        .compositingGroup()
        .clipShape(.rect(cornerRadius: labelSize.height / 2))
        .modifier(LocktyBarGlass(cornerRadius: labelSize.height / 2))
    }
}

public enum WKLocktyTabBarMetrics {
    /// `collapsedWidth` de Lockty.
    public static let width: CGFloat = 132
    /// `LocktySpacing.tabBarHeight`.
    public static let height: CGFloat = 52
}

/// `ExpandableGlassEffect` con `progress == 0`: el contenedor y el cristal
/// interactivo sobre la etiqueta.
private struct LocktyBarGlass: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            GlassEffectContainer {
                content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content.adaptiveGlassInteractive(in: .rect(cornerRadius: cornerRadius))
        }
    }
}

/// El `UISegmentedControl` de Lockty, más una cosa: al salir de la ventana
/// vuelve a su pestaña. Ver `WKLocktyTabBar`.
final class HomeSegmentedControl: UISegmentedControl {
    var homeIndex = 0

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window == nil, selectedSegmentIndex != homeIndex else { return }
        UIView.performWithoutAnimation { selectedSegmentIndex = homeIndex }
    }
}

private struct MorphingSegmentedControl: UIViewRepresentable {
    var tint: Color = .gray.opacity(0.15)
    var symbols: [String]
    var homeIndex: Int
    @Binding var index: Int
    var image: (String) -> UIImage?

    func makeUIView(context: Context) -> HomeSegmentedControl {
        let control = HomeSegmentedControl(items: symbols)
        control.homeIndex = homeIndex
        // La suya, no la seleccionada: esta barra solo se ve en su pestaña.
        control.selectedSegmentIndex = homeIndex
        control.selectedSegmentTintColor = UIColor(tint)

        for (index, symbol) in symbols.enumerated() {
            control.setImage(image(symbol), forSegmentAt: index)
        }

        control.addTarget(context.coordinator, action: #selector(Coordinator.didSelect(_:)), for: .valueChanged)

        DispatchQueue.main.async {
            for view in control.subviews.dropLast() where view is UIImageView {
                view.alpha = 0
            }
        }

        return control
    }

    func updateUIView(_ uiView: HomeSegmentedControl, context: Context) {
        // Solo mientras está a la vista. Fuera de la ventana se queda en su
        // pestaña (ver `didMoveToWindow`), que es donde tiene que estar cuando
        // vuelva a verse.
        guard uiView.window != nil else { return }
        if uiView.selectedSegmentIndex != index {
            uiView.selectedSegmentIndex = index
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: MorphingSegmentedControl

        init(parent: MorphingSegmentedControl) {
            self.parent = parent
        }

        @objc
        func didSelect(_ control: UISegmentedControl) {
            parent.index = control.selectedSegmentIndex
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: HomeSegmentedControl, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

/// `PlainGlassButtonEffect` de Lockty: un botón que es un trozo de cristal y
/// nada más. Los dos círculos de al lado de la barra.
public struct WKPlainGlassButtonStyle<S: Shape>: ButtonStyle {
    var shape: S

    public init(shape: S) { self.shape = shape }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .adaptiveGlassInteractive(in: shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.2), value: configuration.isPressed)
    }
}
