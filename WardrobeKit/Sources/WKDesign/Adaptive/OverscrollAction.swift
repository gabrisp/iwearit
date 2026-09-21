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

    /// Cuánto se ha pasado del final. Negativo = desbordando.
    @State private var offset: CGFloat = 0
    /// Si el dedo está puesto en el scroll **ahora mismo**.
    @State private var isTouching = false
    /// Si **este** arrastre puede disparar. Ver el punto 1 de la nota.
    @State private var isEligible = false
    /// Ya disparado: no se repite hasta volver al final.
    @State private var hasFired = false

    /// La luz del aura.
    ///
    /// Blanca: no es un relleno que tapa, es un foco que se enciende detrás de
    /// la palabra. Un relleno oscuro tapaba lo que había debajo y la píldora
    /// dejaba de parecer cristal para parecer una pastilla pegada encima.
    ///
    /// Sin `blendMode` aditivo, por mucho que quede mejor: mezclar dentro del
    /// cristal es justo lo que lo deja fuera de su propia transición.
    static let fill = Color.white

    /// El aura: una luz blanca que se abre desde el centro.
    ///
    /// Elíptica y en fracciones del tamaño, así que no hay que medir la
    /// píldora y el foco escala solo si cambia el texto.
    ///
    /// A progreso cero devuelve transparente **explícitamente**: un degradado
    /// elíptico con radio cero es degenerado y algunas veces se pinta entero
    /// del primer color, que es por lo que la píldora aparecía rellena un
    /// instante al salir.
    @ViewBuilder
    static func aura(progress: CGFloat) -> some View {
        if progress <= 0 {
            Color.clear
        } else {
            EllipticalGradient(
                stops: [
                    .init(color: fill, location: 0),
                    .init(color: fill.opacity(0.55), location: 0.5),
                    .init(color: fill.opacity(0), location: 1),
                ],
                center: .center,
                startRadiusFraction: 0,
                // Más allá de la mitad: una píldora es mucho más ancha que
                // alta, y un foco que solo llegue a su borde corto deja las
                // puntas sin encender.
                endRadiusFraction: progress * 1.8
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
        let isFull = progress == 1

        return AdaptiveGlassContainer(spacing: WK.Spacing.s) {
            if isVisible { indicator }
        }
        // **El rebote, por fuera de la píldora.**
        //
        // Dentro se peleaba con lo que ya estaba pasando ahí: el cristal
        // formándose, el aura creciendo y el relleno avanzando bajo las
        // letras, todo a la vez y todo con su propia animación. Escalado desde
        // fuera, lo que rebota es la píldora entera como objeto, con su
        // contenido quieto por dentro. Y va con el háptico, que es lo que
        // avisa de que ya está.
        .keyframeAnimator(initialValue: 1.0, trigger: isFull) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            CubicKeyframe(1.1, duration: 0.15)
            CubicKeyframe(1, duration: 0.15)
        }
        .sensoryFeedback(.selection, trigger: isFull) { _, new in new }
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
        pillContent
            .foregroundStyle(WK.Palette.primaryText)
            // **Una luz que crece, no una barra que se rellena.**
            //
            // Y **sin desenfoque ni modo de mezcla**, que es lo que rompió
            // esto dos veces: cualquiera de los dos dentro de la vista que
            // lleva el `glassEffect` obliga a SwiftUI a rasterizar el grupo, y
            // un cristal rasterizado se queda fuera de la transición de su
            // contenedor — aparece con el desenfoque de material en vez de
            // formarse.
            //
            // Un degradado no rasteriza nada y da la misma luz: blanco en el
            // centro, transparente en el borde. Es un foco encendiéndose
            // detrás de la palabra.
            .background {
                Self.aura(progress: progress)
                    .clipShape(.capsule)
            }
            .adaptiveGlass(in: .capsule)
            .adaptiveGlassTransition()
            .allowsHitTesting(false)
    }

    private func fireIfDue() {
        if !isTouching, isEligible, -offset >= threshold, !hasFired {
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
