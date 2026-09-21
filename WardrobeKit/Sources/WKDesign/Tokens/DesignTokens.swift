import SwiftUI
import UIKit

/// Resuelve por esquema sin pasar por el catálogo de assets, para que el
/// paquete sea autocontenido y las `#Preview` funcionen aisladas.
private func adaptive(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
    })
}

/// Paleta, métrica y tipografía.
///
/// El color lo pone **la ropa**. Todo lo que la rodea es neutro, y se construye
/// sobre una única relación: la página es un escalón más apagada que las
/// superficies que descansan sobre ella. En claro la página es gris y las
/// superficies blancas; en oscuro la página es gris muy oscuro y las
/// superficies un poco más claras. La misma relación, del revés.
public enum WK {

    // MARK: - Color

    public enum Palette {
        /// Fondo de pantalla.
        ///
        /// **Ni blanco puro ni negro puro.** Una prenda negra recortada sobre
        /// negro puro desaparece, y una blanca sobre blanco también. Un gris a
        /// cada lado deja que ambas se vean, y además da algo contra lo que la
        /// sombra de la balda pueda leerse.
        public static let canvas = adaptive(
            light: .secondarySystemBackground,
            dark: .secondarySystemBackground
        )

        /// Superficie que descansa sobre la página: una tarjeta, una celda.
        ///
        /// Más clara que la página en los dos esquemas. En oscuro no se usa
        /// negro: sobre una página gris oscuro, una caja más oscura lee como
        /// una mancha y no como algo elevado.
        public static let shelf = adaptive(
            light: .systemBackground,
            dark: .tertiarySystemBackground
        )

        /// Un poco del color de primer plano, sea cual sea.
        ///
        /// Escribir los filetes y las sombras como "negro al 10%" solo funciona
        /// en claro; en oscuro desaparecen. Esto dice la intención en vez de
        /// deletrearla como un color.
        ///
        /// En claro se aplica menos: el negro sobre fondo claro pesa bastante
        /// más que el blanco sobre oscuro con el mismo alfa, y calcar el número
        /// deja los filetes como trazados a boli.
        public static func ink(_ opacity: Double) -> Color {
            adaptive(
                light: UIColor.black.withAlphaComponent(opacity * 0.62),
                dark: UIColor.white.withAlphaComponent(opacity)
            )
        }

        /// Canto de la balda.
        public static let shelfEdge = ink(0.14)

        /// Acento monocromo: negro en claro, blanco en oscuro.
        ///
        /// Negro y blanco **explícitos**, no `.label`. Un color dinámico
        /// metido dentro de otro bloque dinámico no resuelve de forma fiable:
        /// `UIColor.label` dentro de `UIColor { traits in ... }` puede
        /// resolverse contra el esquema equivocado, y el resultado era negro
        /// sobre negro en claro y blanco sobre blanco en oscuro.
        public static let accent = adaptive(light: .black, dark: .white)

        /// Lo que se dibuja **encima** de una superficie rellena con `accent`.
        ///
        /// Imprescindible: con el acento en blanco, dejar que el sistema elija
        /// el color de la etiqueta produce texto blanco sobre blanco. El relleno
        /// y la etiqueta se deciden siempre juntos.
        public static let onAccent = adaptive(light: .white, dark: .black)

        public static let primaryText = adaptive(light: .black, dark: .white)
        public static let secondaryText = adaptive(
            light: UIColor.black.withAlphaComponent(0.58),
            dark: UIColor.white.withAlphaComponent(0.64)
        )
        public static let tertiaryText = Color(uiColor: .tertiaryLabel)

        /// Retícula de puntos del canvas.
        public static let grid = ink(0.22)
    }

    // MARK: - Métrica

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 40

        /// Margen lateral del contenido de una pantalla dentro de una pestaña.
        ///
        /// Más ancho que el de una hoja: una pantalla en un `NavigationStack`
        /// lleva toolbar encima, y el sistema coloca sus items a su propio
        /// margen. A 16 las tarjetas quedan visiblemente por dentro del botón
        /// que tienen arriba, y eso se lee como desalineado, no como decisión.
        public static let screenInset: CGFloat = 20
        /// Margen lateral dentro de una tarjeta que contiene filas.
        public static let cardInset: CGFloat = 14
    }

    public enum Radius {
        public static let small: CGFloat = 10
        public static let medium: CGFloat = 16
        public static let large: CGFloat = 24
        public static let card: CGFloat = 20
    }

    public enum Shelf {
        /// Alto de la zona donde cuelgan las prendas, etiqueta incluida.
        public static let height: CGFloat = 172
        /// Alto reservado a la imagen. El resto es la etiqueta.
        public static let imageHeight: CGFloat = 132
        /// Grosor visible del tablero.
        public static let plankThickness: CGFloat = 1
        /// Separación entre el nombre de la prenda y el canto de la balda.
        public static let labelBottomInset: CGFloat = 12
        public static let garmentWidth: CGFloat = 104
        /// Inclinación máxima de una prenda "colgada", en grados.
        /// Determinista a partir del id: sin estado ni aleatoriedad por frame.
        public static let maxSwayDegrees: Double = 2.5
    }

    // MARK: - Tipografía

    /// Fuente del sistema con **pesos ligeros**.
    ///
    /// No es una fuente de marca: es la del sistema, que trae Dynamic Type y
    /// todas las métricas de accesibilidad gratis. Lo que cambia es el peso —
    /// `.light` en el texto corrido y en los números grandes— y eso basta para
    /// que no parezca una app de plantilla. Un peso pesado en texto largo
    /// además cansa la vista.
    /// Inter, con Dynamic Type.
    ///
    /// `relativeTo:` y no un tamaño fijo: sin eso, una fuente propia rompe los
    /// ajustes de tamaño de texto del sistema, que para mucha gente no es una
    /// preferencia estética sino la diferencia entre poder usar la app o no.
    ///
    /// Los pesos ligeros en texto corrido son deliberados: un peso pesado en
    /// párrafos largos cansa la vista, y Inter aguanta bien el `.light`.
    public enum Font {

        /// Nombre PostScript por peso.
        ///
        /// Se nombra el fichero exacto y no se deja que SwiftUI aplique
        /// `.weight()` sobre una familia: con una fuente propia, ese modificador
        /// **sintetiza** el peso deformando los trazos en vez de usar el corte
        /// real, y el resultado se ve sucio a tamaños grandes.
        private static func face(_ weight: SwiftUI.Font.Weight) -> String {
            switch weight {
            case .light, .thin, .ultraLight: "PlusJakartaSans-Light"
            case .medium: "PlusJakartaSans-Medium"
            case .semibold: "PlusJakartaSans-SemiBold"
            case .bold, .heavy, .black: "PlusJakartaSans-Bold"
            default: "PlusJakartaSans-Regular"
            }
        }

        /// Plus Jakarta Sans si está registrada; la del sistema si no.
        ///
        /// El respaldo importa: si el registro fallara, una `Font.custom` con un
        /// nombre inexistente cae a Helvetica, que se ve visiblemente peor que
        /// SF Pro y es difícil de diagnosticar.
        @MainActor static func scaled(
            _ size: CGFloat,
            relativeTo style: SwiftUI.Font.TextStyle,
            weight: SwiftUI.Font.Weight = .regular
        ) -> SwiftUI.Font {
            guard WKFonts.isRegistered else {
                return .system(style, design: .default, weight: weight)
            }
            return .custom(face(weight), size: size, relativeTo: style)
        }

        @MainActor public static let largeTitle = scaled(34, relativeTo: .largeTitle, weight: .bold)
        @MainActor public static let title = scaled(22, relativeTo: .title2, weight: .semibold)
        @MainActor public static let headline = scaled(17, relativeTo: .headline, weight: .medium)
        @MainActor public static let body = scaled(17, relativeTo: .body, weight: .light)
        @MainActor public static let callout = scaled(16, relativeTo: .callout, weight: .light)
        @MainActor public static let caption = scaled(12, relativeTo: .caption, weight: .light)
        @MainActor public static let captionMedium = scaled(12, relativeTo: .caption, weight: .medium)

        @MainActor public static let shelfTitle = scaled(20, relativeTo: .title3, weight: .semibold)
        @MainActor public static let garmentName = scaled(12, relativeTo: .caption, weight: .light)
        @MainActor public static let rowTitle = scaled(17, relativeTo: .body, weight: .light)

        /// Cifras grandes. En ligero y no en negrita: a este tamaño el peso
        /// pesado grita, y la cifra ya tiene todo el peso visual por su tamaño.
        @MainActor public static func display(_ size: CGFloat) -> SwiftUI.Font {
            scaled(size, relativeTo: .largeTitle, weight: .light)
        }
        @MainActor public static let statNumber = display(44)
    }
}

// MARK: - Superficies

public extension View {
    /// Tarjeta: relleno suave y **filete de un punto**.
    ///
    /// El filete es lo que separa una tarjeta del fondo sin recurrir a una
    /// sombra. Sombras a media opacidad sobre fondo oscuro se convierten en
    /// manchas; un filete se comporta igual en los dos esquemas porque se
    /// escribe como "un poco del color de primer plano" y no como negro.
    func wkCard(cornerRadius: CGFloat = WK.Radius.card) -> some View {
        background(WK.Palette.shelf, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(WK.Palette.ink(0.09), lineWidth: 1)
            )
    }
}
