import SwiftUI

// Liquid Glass (iOS 26) con degradación digna a materiales en iOS 18.
//
// Todo el `#available` del proyecto vive en este directorio. Una vista de
// feature que escriba `if #available` es un bug de arquitectura.

public extension View {

    /// Superficie de cristal. En iOS 18 cae a `.ultraThinMaterial` con un filo
    /// sutil, que es lo que más se le parece sin inventarse un blur propio.
    ///
    /// - Important: como `glassEffect`, se aplica **después** de los
    ///   modificadores de layout (`padding`, `frame`), nunca antes.
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    /// Cristal teñido, para destacar sin recurrir a un `.prominent` que no
    /// existe.
    ///
    /// - Warning: este **no** decide la etiqueta, porque se usa también sobre
    ///   contenido que no es texto. Con un tinte oscuro hay que poner el color
    ///   del contenido a mano, o usar `adaptiveGlassProminent`, que ya lo hace.
    @ViewBuilder
    func adaptiveGlass<S: Shape>(tint: Color, in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.tint(tint), in: shape)
        } else {
            // 0.38 y no 0.18: sobre un material claro, un tinte al 18% se lee
            // como gris. Calibrado comparando las dos ramas lado a lado para
            // que el tinte pese lo mismo que en iOS 26.
            self
                .background(tint.opacity(0.38), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(tint.opacity(0.45), lineWidth: 0.5))
        }
    }

    /// Cristal que responde al tacto. **Solo en elementos realmente pulsables**:
    /// ponerlo en contenido estático es ruido visual que promete interacción.
    @ViewBuilder
    func adaptiveGlassInteractive<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    /// **Cristal que se puede apagar animando**: con `isEnabled` a `false`
    /// pasa a `.identity` —sin cristal— y el cambio se anima, en vez de
    /// quitar el modificador y rehacer la vista.
    @ViewBuilder
    func adaptiveGlassInteractive<S: Shape>(in shape: S, isEnabled: Bool) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(isEnabled ? .regular.interactive() : .identity, in: shape)
        } else {
            self
                .background(.ultraThinMaterial.opacity(isEnabled ? 1 : 0), in: shape)
                .overlay(shape.stroke(.white.opacity(isEnabled ? 0.12 : 0), lineWidth: 0.5))
        }
    }

    /// Una píldora de elegir: cristal de verdad, o nada.
    ///
    /// **El cristal no se apila.** Una cápsula rellena con el acento y luego
    /// un `glassEffect` encima son dos fondos, uno tapando al otro: el cristal
    /// no tiene nada que refractar y queda una pegatina turbia sobre un color
    /// plano. El tinte va **dentro** del cristal, que es para lo que está.
    ///
    /// Y donde no hay cristal de verdad, tampoco lo hay de mentira: un
    /// material imitándolo sobre un fondo claro se lee como suciedad. Un
    /// relleno plano dice lo mismo —esto se toca, esto está elegido— sin
    /// fingir una profundidad que no existe.
    @ViewBuilder
    func adaptiveGlassChip(isSelected: Bool, tint: Color) -> some View {
        if #available(iOS 26, *) {
            if isSelected {
                self.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
            } else {
                self.glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            self.background(isSelected ? tint : WK.Palette.ink(0.06), in: .capsule)
        }
    }

    /// Cristal teñido **y** pulsable: la acción principal sobre cristal.
    ///
    /// **Decide también el color de la etiqueta.** No es un extra: con el
    /// acento en negro y el texto heredando el color primario —negro también—
    /// el contenido desaparecía sobre su propio relleno. Es exactamente el
    /// mismo fallo que dejó los botones ilegibles, y la única forma de que no
    /// vuelva es que relleno y etiqueta se decidan en el mismo sitio.
    ///
    /// Si algún caso necesita otro color de etiqueta, se aplica **después** de
    /// este modificador y gana.
    ///
    /// En iOS 18 no hay cristal que teñir, así que cae a un relleno sólido. Es
    /// la degradación correcta: un material translúcido con un tinte fuerte
    /// encima se ve sucio, y para un botón principal importa más que se lea
    /// como pulsable que que imite el cristal.
    @ViewBuilder
    func adaptiveGlassProminent<S: Shape>(
        tint: Color,
        label: Color = WK.Palette.onAccent,
        in shape: S
    ) -> some View {
        if #available(iOS 26, *) {
            self.foregroundStyle(label)
                .glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self.foregroundStyle(label)
                .background(tint, in: shape)
        }
    }

    /// Cómo entra y sale el propio cristal.
    ///
    /// Distinto de una transición normal: `glassEffectTransition` controla la
    /// **materia**, no la vista. Con `.matchedGeometry`, dos superficies de
    /// cristal que comparten `glassEffectID` se funden una en otra en vez de
    /// desaparecer y aparecer — que es lo que hace que un control de cristal
    /// parezca líquido y no un panel que se cambia.
    ///
    /// En iOS 18 no hay cristal que transicionar, así que no hace nada.
    @ViewBuilder
    func adaptiveGlassTransition() -> some View {
        if #available(iOS 26, *) {
            self.glassEffectTransition(.matchedGeometry)
        } else {
            self
        }
    }

    /// El cristal **se forma** en su sitio al aparecer.
    ///
    /// Para lo que llega sin venir de ningún sitio —unos botones que aparecen
    /// al terminar algo—. La transición por defecto dentro de un contenedor
    /// busca de dónde venir, y sin pareja sale volando desde una esquina.
    @ViewBuilder
    func adaptiveGlassMaterialize() -> some View {
        if #available(iOS 26, *) {
            self.glassEffectTransition(.materialize)
        } else {
            self.transition(.opacity)
        }
    }

    /// El cristal **no** se mueve al aparecer ni al desaparecer.
    ///
    /// Hace falta decirlo explícitamente, y esa es la parte que no es obvia:
    /// dentro de un `GlassEffectContainer`, una superficie de cristal usa
    /// `.matchedGeometry` **por defecto**. Cuando tiene pareja —otro cristal
    /// con el mismo id— eso es exactamente lo que se quiere. Cuando no la
    /// tiene, el sistema la hace salir de un punto degenerado del contenedor:
    /// se ve como una píldora que llega volando desde una esquina.
    ///
    /// Con `.identity`, la materia se queda quieta y quien decide cómo llega
    /// la vista es su propia `transition`.
    @ViewBuilder
    func adaptiveGlassStill() -> some View {
        if #available(iOS 26, *) {
            self.glassEffectTransition(.identity)
        } else {
            self
        }
    }

    /// Identidad para que dos superficies de cristal se transformen una en otra.
    /// En iOS 18 el equivalente honesto es `matchedGeometryEffect`.
    @ViewBuilder
    func adaptiveGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self.matchedGeometryEffect(id: id, in: namespace)
        }
    }
}

/// Agrupa varias superficies de cristal para que compartan región de muestreo.
///
/// El cristal refracta muestreando un área mayor que él mismo, y **no puede
/// muestrear otro cristal**: dos elementos vecinos en contenedores distintos se
/// ven inconsistentes. En iOS 18 no hay nada que agrupar, así que es un paso a través.
public struct AdaptiveGlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    /// - Parameter spacing: debe coincidir con el spacing real del layout interior.
    public init(spacing: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
