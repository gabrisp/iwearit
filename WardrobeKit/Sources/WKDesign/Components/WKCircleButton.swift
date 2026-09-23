import SwiftUI

/// El botón redondo de la app: **un símbolo, alto igual que ancho, siempre**.
///
/// ## Por qué existe
///
/// Porque había cinco tamaños distintos del mismo botón —30 en el chat, 34 en
/// una tarjeta de inspiración, 44 en el campo de escribir, 52 en la maleta— y
/// cada pantalla los ponía a mano con su `frame` y su `contentShape`. Se
/// notaba al pasar de una a otra: la misma acción cambiaba de tamaño, y al
/// ponerlos en fila uno quedaba más gordo que el de al lado.
///
/// Dos medidas y ninguna más: la de una barra y la de dentro de una tarjeta.
/// Las dos son cuadradas —alto igual que ancho— y las dos se recortan en
/// círculo, que es lo que hace que un icono suelto se lea como algo que se
/// toca.
///
/// - Note: en la barra de navegación **no se usa**: ahí el tamaño lo pone el
///   sistema y forzarlo descoloca la barra entera.
public struct WKCircleButton<Symbol: View>: View {

    public enum Size {
        /// El de una barra o el de un botón suelto sobre el contenido. Es el
        /// mínimo táctil de Apple, y por debajo de eso se falla el toque.
        case regular
        /// El de dentro de una tarjeta, donde tres botones tienen que caber
        /// sin tapar lo que hay debajo.
        case compact

        public var side: CGFloat {
            switch self {
            case .regular: 44
            case .compact: 34
            }
        }

        @MainActor
        var font: Font {
            switch self {
            case .regular: WK.Font.headline
            case .compact: .footnote.weight(.semibold)
            }
        }
    }

    private let size: Size
    private let action: () -> Void
    private let symbol: Symbol

    public init(
        size: Size = .regular,
        action: @escaping () -> Void,
        @ViewBuilder symbol: () -> Symbol
    ) {
        self.size = size
        self.action = action
        self.symbol = symbol()
    }

    public var body: some View {
        Button(action: action) {
            symbol
                .font(size.font)
                .frame(width: size.side, height: size.side)
                .contentShape(.circle)
        }
        .buttonStyle(WKPressStyle())
        .adaptiveGlassInteractive(in: .circle)
    }
}

public extension WKCircleButton where Symbol == Image {
    /// El caso de siempre: un símbolo del sistema.
    init(_ systemName: String, size: Size = .regular, action: @escaping () -> Void) {
        self.init(size: size, action: action) { Image(systemName: systemName) }
    }
}

#Preview {
    HStack(spacing: WK.Spacing.m) {
        WKCircleButton("heart") {}
        WKCircleButton("calendar", size: .compact) {}
        WKCircleButton("pencil", size: .compact) {}
    }
    .tint(WK.Palette.primaryText)
    .padding()
    .background(WK.Palette.canvas)
}
