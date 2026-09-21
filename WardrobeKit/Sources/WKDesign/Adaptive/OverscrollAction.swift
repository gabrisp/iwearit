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
    /// La identidad del cristal. Ver `pill`.
    @Namespace private var glass

    /// La luz del aura.
    ///
    /// Blanca y **aditiva**: no es un relleno que tapa, es un foco que se
    /// enciende detrás de la palabra. Un relleno oscuro tapaba lo que había
    /// debajo y la píldora dejaba de parecer cristal para parecer una pastilla
    /// pegada encima; sumando luz, lo de debajo sigue estando y solo se
    /// ilumina.
    static let fill = Color.white

    /// El aura: **un punto desenfocado** que crece desde el centro.
    ///
    /// Un círculo pequeño con mucho desenfoque, y no un degradado, por dos
    /// razones.
    ///
    /// La primera es un fallo: con el progreso a cero el degradado elíptico es
    /// degenerado —radio cero— y se pinta **entero del primer color**. Por eso
    /// la píldora salía rellena durante un instante y luego se corregía. Un
    /// punto a escala cero mide cero y no hay nada que corregir.
    ///
    /// La segunda es que un degradado de tres paradas, por suave que sea,
    /// tiene un sitio donde acaba. Un punto desenfocado no acaba en ninguna
    /// parte: es una mancha de luz detrás de la palabra que se va comiendo la
    /// píldora.
    static func aura(_ color: Color, progress: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: dotSize, height: dotSize)
            .blur(radius: dotBlur)
            // Suma luz en vez de pintar encima: es lo que hace que la píldora
            // parezca encenderse y no mancharse.
            .blendMode(.plusLighter)
            // Hasta cubrir la píldora entera. Llega deslavazado a las puntas,
            // que es justo lo que se quiere: se tiñen las últimas y sin canto.
            .scaleEffect(max(0, progress) * dotGrowth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// De qué tamaño parte el punto, cuánto se difumina y cuánto crece.
    ///
    /// El desenfoque es casi tan grande como el punto: por debajo de eso se le
    /// ve la forma de círculo y deja de ser un aura.
    private static let dotSize: CGFloat = 22
    private static let dotBlur: CGFloat = 16
    private static let dotGrowth: CGFloat = 14

    /// Cuánto hay que desbordar para que el indicador acabe de aparecer.
    /// Separa "estás desbordando" de "estás pidiendo algo".
    private static let revealDistance: CGFloat = 50

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
            if isVisible {
                indicator
                    // **El cristal necesita nombre.**
                    //
                    // `glassEffectTransition(.matchedGeometry)` no transiciona
                    // nada por sí solo: empareja superficies que comparten
                    // `glassEffectID`. Sin id no hay a quién parecerse, así que
                    // iOS caía a su transición por defecto —la que se ve como
                    // un desenfoque sustituyendo a otro— y el modificador no
                    // pintaba nada.
                    .adaptiveGlassID("overscroll", in: glass)
                    // Y una entrada dicha explícitamente, para que no vuelva a
                    // decidirla nadie por nosotros: crece un pelo y aparece.
                    // El desenfoque sobra: el aura de dentro ya es todo lo
                    // difuso que esto tiene que ser.
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
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
            // El corte recto de una barra de progreso marca una frontera, y
            // una frontera pide leerse: la mitad llena y la mitad vacía
            // parecían dos píldoras pegadas. Un punto de luz difuminado no
            // tiene borde en ninguna parte: la píldora se va encendiendo.
            .background {
                Self.aura(Self.fill, progress: progress)
                    .clipShape(.capsule)
            }
            // **Sin letras invertidas.** Existían para salvar el texto de un
            // relleno oscuro que le pasaba por debajo. Con luz en vez de
            // relleno no hay nada de lo que salvarlas: la palabra se queda
            // igual y lo que cambia es cuánta luz tiene detrás.
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
