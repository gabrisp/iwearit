import SwiftUI

public extension View {
    /// Seguir tirando al final del scroll dispara una acción.
    ///
    /// Va sobre un `ScrollView` —es lo único que tiene "final"—, pero se
    /// declara sobre `View` porque para cuando se encadena detrás de
    /// `scrollTargetBehavior` y compañía ya no es un `ScrollView` sino un
    /// `some View`, y acotarlo al tipo obligaba a ponerlo el primero de la
    /// cadena.
    ///
    /// ## Por qué esto y no un botón
    ///
    /// Porque el gesto ya lo estás haciendo. Llegas al último lienzo del día,
    /// sigues arrastrando hacia arriba porque quieres ver si hay más, y la
    /// respuesta es "no, pero puedes añadir otro". Un botón obliga a parar,
    /// buscar dónde está y apuntar; esto contesta en el mismo movimiento con
    /// el que has preguntado.
    ///
    /// Es el gesto que Threads usa para cerrar un hilo. La idea —y el cálculo
    /// del desbordamiento— vienen de la muestra de Balaji Venkatesh que me
    /// pasaste; aquí dispara una acción en vez de cerrar, y el indicador usa
    /// los tokens de la app.
    ///
    /// ## Lo que hace que no se dispare sin querer
    ///
    /// Tres cosas, y las tres importan:
    ///
    /// 1. **Solo si el gesto empezó cerca del final.** Un impulso fuerte desde
    ///    arriba llega al fondo con inercia y desbordaría sin que nadie haya
    ///    tirado de nada. Al empezar a arrastrar se decide si ese arrastre
    ///    puede disparar, y si no, no dispara por mucho que rebote.
    /// 2. **Al soltar, no al llegar.** Mientras el dedo está puesto se puede
    ///    volver atrás; el compromiso es soltar pasado el umbral.
    /// 3. **Una vez por gesto.** Hasta que el scroll no vuelve al final, no se
    ///    vuelve a armar.
    ///
    /// - Parameters:
    ///   - threshold: cuánto hay que desbordar, en puntos.
    ///   - symbol: el símbolo del indicador.
    ///   - label: qué va a pasar, escrito. Un icono solo obliga a adivinarlo
    ///     justo cuando todavía puedes echarte atrás.
    ///   - bottomInset: cuánto separarlo del borde. Lo que haya ahí abajo
    ///     —barra de pestañas, accesorio flotante— lo taparía.
    ///   - action: se ejecuta al soltar pasado el umbral.
    @ViewBuilder
    func overscrollAction(
        threshold: CGFloat = 120,
        symbol: String = "plus",
        label: String,
        bottomInset: CGFloat = 0,
        action: @MainActor @escaping () -> Void
    ) -> some View {
        modifier(
            OverscrollAction(
                threshold: threshold,
                symbol: symbol,
                label: label,
                bottomInset: bottomInset,
                action: action
            )
        )
    }
}

private struct OverscrollAction: ViewModifier {
    let threshold: CGFloat
    let symbol: String
    let label: String
    let bottomInset: CGFloat
    let action: @MainActor () -> Void
    /// Para dar por aprendido el aviso del tirón en cuanto se usa. Opcional:
    /// fuera de la app —previsualizaciones— no hay avisos.
    @Environment(WKTipCenter.self) private var tips: WKTipCenter?

    /// Cuánto se ha pasado del final. Negativo = desbordando.
    @State private var offset: CGFloat = 0
    /// Si el dedo está puesto en el scroll **ahora mismo**.
    @State private var isTouching = false
    /// Si **este** arrastre puede disparar. Ver el punto 1 de la nota.
    @State private var isEligible = false
    /// Ya disparado: no se repite hasta volver al final.
    @State private var hasFired = false

    /// El relleno. Negro translúcido y no el color del texto: sobre cristal,
    /// un relleno opaco tapa lo que hay detrás y la píldora deja de parecer
    /// cristal para parecer una pastilla pegada encima. Al 60% la superficie
    /// sigue dejando ver el lienzo y aun así hay contraste de sobra para la
    /// letra invertida.
    static let fill = Color.black.opacity(0.6)

    /// Y la tinta que va encima de ese relleno. Blanca en los dos temas,
    /// porque el relleno es negro en los dos: atarla al color de fondo la
    /// hacía desaparecer en oscuro.
    static let fillInk = Color.white

    /// El aura: un **círculo difuso** que nace en el centro y crece.
    ///
    /// Elíptica y no lineal. La lineal tapaba de golpe toda la altura de la
    /// píldora, así que por suave que fuera el borde seguía siendo una franja
    /// cruzando de lado a lado. Un círculo que se abre desde el centro no
    /// tiene ni dirección ni frontera.
    ///
    /// La difuminación se hace con **paradas**, no con `blur`: un desenfoque
    /// dentro de la vista que lleva el `glassEffect` obliga a SwiftUI a
    /// rasterizar el grupo, y un cristal rasterizado se queda fuera de la
    /// transición de su contenedor. Cuatro paradas con caída larga dan la
    /// misma nube sin rasterizar nada.
    ///
    /// A progreso cero devuelve transparente **explícitamente**: un degradado
    /// elíptico de radio cero es degenerado y a veces se pinta entero del
    /// primer color, que es lo que hacía aparecer la píldora rellena un
    /// instante.
    @ViewBuilder
    /// El aura de antes. **Ya no se usa** —ver `indicator`— y se queda por si
    /// algún día hace falta teñir algo sin marcar una frontera.
    static func aura(to progress: CGFloat, of color: Color) -> some View {
        if progress <= 0 {
            Color.clear
        } else {
            EllipticalGradient(
                stops: [
                    .init(color: color, location: 0),
                    .init(color: color.opacity(0.62), location: 0.34),
                    .init(color: color.opacity(0.24), location: 0.62),
                    .init(color: color.opacity(0), location: 1),
                ],
                center: .center,
                startRadiusFraction: 0,
                // Más allá de la mitad: una píldora es mucho más ancha que
                // alta, y un círculo que solo llegue a su borde corto deja las
                // puntas sin teñir.
                endRadiusFraction: progress * 1.9
            )
        }
    }

    /// Cuánto hay que desbordar para que el indicador acabe de aparecer.
    /// Separa "estás desbordando" de "estás pidiendo algo".
    private static let revealDistance: CGFloat = 32

    func body(content: Content) -> some View {
        content
            // **Sin reconocedor propio.** La muestra original añade un
            // `DragGesture(minimumDistance: 0)` para saber si el dedo sigue
            // puesto, y aquí eso no sale gratis: este scroll vive dentro del
            // pasador de hoja y encima de un lienzo con doble toque y pulsación
            // larga, y un reconocedor más compitiendo por el mismo toque
            // rompía el paso de página.
            //
            // `onScrollPhaseChange` dice lo mismo y no compite con nada: es el
            // propio scroll contando en qué está.
            .onScrollPhaseChange { _, phase in
                let touching = phase == .tracking || phase == .interacting
                if touching, !isTouching { isEligible = offset < threshold * 1.2 }
                isTouching = touching
                fireIfDue()
            }
            .overlay(alignment: .bottom) { pill }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let scrolled = geometry.contentOffset.y + geometry.contentInsets.top
                let scrollable = max(geometry.contentSize.height - geometry.containerSize.height, 0)
                // Distancia al final: 0 justo en el fondo, negativa al
                // desbordar.
                return scrollable - scrolled
            } action: { _, new in
                offset = new
                fireIfDue()
            }
    }

    /// Si hay que enseñarla. Binario a propósito: ver `pill`.
    private var isVisible: Bool { isEligible && offset < -2 }

    /// La píldora, **puesta y quitada** en vez de atenuada.
    ///
    /// Con `opacity` la vista existe siempre, y el cristal no tiene nada que
    /// animar: aparece una superficie ya formada a la que solo le sube el
    /// alfa. Metiéndola y sacándola de un contenedor de cristal, iOS 26 la
    /// forma y la deshace de verdad —se despega del fondo al entrar y se
    /// funde con él al salir—, que es para lo que existe
    /// `glassEffectTransition`.
    private var pill: some View {
        AdaptiveGlassContainer(spacing: WK.Spacing.s) {
            if isVisible { indicator }
        }
        .padding(.bottom, bottomInset)
        // Por encima de todo lo que haya en el scroll.
        .zIndex(100)
        // **Despacio.** Formar cristal no es encender una luz: a la velocidad
        // de una selección se veía aparecer la píldora ya hecha. Con medio
        // segundo largo la superficie se cuaja mientras sigues tirando, que es
        // el tiempo que dura el gesto.
        .animation(.smooth(duration: 0.55), value: isVisible)
    }

    /// El progreso del indicador, 0-1. Cero mientras este arrastre no pueda
    /// disparar: sin eso, un rebote por inercia dibujaría un aro llenándose
    /// que no va a hacer nada.
    private var progress: CGFloat {
        let overscroll = offset < 0 ? -offset : 0
        guard isEligible, threshold > Self.revealDistance else { return 0 }
        let raw = (overscroll - Self.revealDistance) / (threshold - Self.revealDistance)
        return hasFired ? 1 : min(max(raw, 0), 1)
    }

    /// El contenido de la píldora, **una sola vez**.
    ///
    /// Se usa dos veces —como contenido y como máscara de la capa invertida— y
    /// tiene que ser exactamente el mismo con exactamente los mismos márgenes,
    /// o las letras invertidas caen desplazadas respecto a las de debajo.
    private var pillContent: some View {
        HStack(spacing: WK.Spacing.s) {
            Image(systemName: symbol)
                .font(WK.Font.headline)
            Text(label)
                .font(WK.Font.headline)
                .lineLimit(1)
        }
        .padding(.horizontal, WK.Spacing.l)
        .padding(.vertical, WK.Spacing.s + 2)
    }

    private var indicator: some View {
        let isFull = progress == 1

        // **El mismo relleno que el botón de mejorar.**
        //
        // Antes esto se teñía con un aura difusa creciendo desde el centro y
        // el botón de mejorar se rellenaba de izquierda a derecha: dos formas
        // de decir lo mismo en la misma app. Gana el relleno recto, que además
        // dice **cuánto** queda para disparar, que es lo único que se quiere
        // saber mientras tiras. Ver `WKProgressFill`.
        return WKProgressFill(progress: progress, fill: Self.fill, ink: Self.fillInk) { color in
            pillContent.foregroundStyle(color)
        }
            .clipShape(.capsule)
            .adaptiveGlass(in: .capsule)
            // Aparece **donde está**, sin subir desde ningún sitio: la píldora
            // ya estaba ahí con opacidad cero, y el cristal se encarga de que
            // llegar no parezca un corte.
            .adaptiveGlassTransition()
            // **Sin rebote al completarse.** Lo que avisa de que ya está es el
            // háptico, y llega al mismo sitio sin mover nada: un salto de
            // tamaño en algo que estás mirando de cerca mientras arrastras se
            // lee como un tirón, no como una confirmación.
            .allowsHitTesting(false)
            .sensoryFeedback(.selection, trigger: isFull) { _, new in new }
    }

    private func fireIfDue() {
        if !isTouching, isEligible, -offset >= threshold, !hasFired {
            tips?.complete(.overscrollNewOutfit)
            action()
            hasFired = true
        }
        // Se rearma al volver al final. Con margen: pedir exactamente 0 no
        // ocurre casi nunca porque el rebote deja décimas.
        if hasFired, !isTouching, offset.rounded() > -10 {
            hasFired = false
        }
    }
}


/// El aura del tirón, **suelta**, para quien la necesite fuera de la píldora.
///
/// La usa la inspiración: tirar hacia abajo desde arriba enciende el botón de
/// barajar, y lo que dice cuánto llevas tirado es la misma nube que en el
/// indicador del final. Dos gestos que hacen lo mismo —pedir algo tirando— se
/// tienen que ver igual.
public struct WKAura: View {
    private let progress: CGFloat
    private let color: Color

    public init(progress: CGFloat, color: Color = Color.black.opacity(0.6)) {
        self.progress = progress
        self.color = color
    }

    public var body: some View {
        if progress <= 0 {
            Color.clear
        } else {
            EllipticalGradient(
                stops: [
                    .init(color: color, location: 0),
                    .init(color: color.opacity(0.62), location: 0.34),
                    .init(color: color.opacity(0.24), location: 0.62),
                    .init(color: color.opacity(0), location: 1),
                ],
                center: .center,
                startRadiusFraction: 0,
                endRadiusFraction: progress * 1.9
            )
        }
    }
}
