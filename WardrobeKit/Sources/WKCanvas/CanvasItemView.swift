import SwiftUI
import WKCore
import WKDesign

/// Una prenda colocada en el canvas, con manipulación directa.
///
/// ## Dónde vive el estado
///
/// Durante el gesto, el delta vive **aquí** (`live`). La transformada ya
/// confirmada llega desde el padre como valor POD. Así arrastrar invalida el
/// `body` de esta prenda y de ninguna otra: el padre no tiene estado de gesto
/// que tocar, y no se escribe en la base de datos hasta soltar.
public struct CanvasItemView<Content: View>: View {

    private struct Live {
        var scale: Double = 1
        var rotation: Double = 0
        var drag: CGSize = .zero
        var anchor: UnitPoint = .center

        var isIdle: Bool { scale == 1 && rotation == 0 && drag == .zero }
    }

    private let transform: ItemTransform
    private let isSelected: Bool
    /// Hay otra prenda seleccionada. Esta se aparta visualmente.
    private let isDimmed: Bool
    /// Puntos de canvas por punto de pantalla. Convierte el arrastre.
    private let canvasScale: Double
    private let mask: AlphaMask?
    private let content: Content
    private let onSelect: () -> Void
    private let onCommit: (ItemTransform) -> Void

    @State private var live = Live()

    public init(
        transform: ItemTransform,
        isSelected: Bool,
        isDimmed: Bool = false,
        canvasScale: Double,
        mask: AlphaMask?,
        onSelect: @escaping () -> Void,
        onCommit: @escaping (ItemTransform) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.transform = transform
        self.isSelected = isSelected
        self.isDimmed = isDimmed
        self.canvasScale = canvasScale
        self.mask = mask
        self.onSelect = onSelect
        self.onCommit = onCommit
        self.content = content()
    }

    /// Lo que se ve ahora: lo confirmado más el gesto en vuelo.
    private var previewTransform: ItemTransform {
        guard !live.isIdle else { return transform }
        return CanvasMath.applying(
            scale: live.scale,
            rotation: live.rotation,
            drag: live.drag,
            about: live.anchor,
            to: transform
        )
    }

    public var body: some View {
        #if DEBUG
        let _ = Self._logChanges()
        #endif
        let current = previewTransform
        let isLifted = isSelected || !live.isIdle

        // ## Por qué este orden exacto
        //
        // La forma de toque y los gestos van **antes** de `position`, y ese es
        // el arreglo de verdad de "seleccionar y mover va mal".
        //
        // `position` hace que la vista ocupe **todo el padre** y coloque su
        // contenido dentro. Puesto después, `contentShape(AlphaShape(...))`
        // extendía la máscara sobre el lienzo entero: cada prenda era tocable
        // en toda la pantalla, y como están apiladas por `zIndex`, cualquier
        // toque se lo llevaba la de encima sin importar dónde cayera el dedo.
        // Por eso seleccionar la que querías era cuestión de suerte y tocar
        // fuera casi nunca deseleccionaba.
        //
        // Aquí la forma se define sobre el tamaño propio de la prenda, y
        // `scaleEffect` y `rotationEffect` —que sí transforman el hit testing—
        // la llevan a donde se ve. Los gestos van con ella por la misma razón.
        content
            .frame(width: current.baseWidth, height: current.baseHeight)
            // **Margen para cogerla, solo cuando ya está cogida.**
            //
            // Sin seleccionar, el toque sigue el alfa al píxel: es lo que hace
            // que tocar la esquina vacía de una chaqueta alcance lo que hay
            // debajo. Pero una vez seleccionada, el gesto que toca es pellizcar
            // y girar —dos dedos— y en un tirante o en unas gafas no caben dos
            // dedos dentro del alfa. Ahí se pasa a la caja con margen.
            //
            // Dividido por la escala para que el margen sea **el mismo en
            // pantalla** con la prenda grande o pequeña: sin eso, justo la
            // prenda diminuta —la que más lo necesita— era la que menos margen
            // recibía.
            .padding(isSelected ? CanvasItemMetrics.grabMargin / max(current.scale, 0.25) : 0)
            // **La silueta manda también cuando está cogida.**
            //
            // Antes, al seleccionar, la forma de toque pasaba a ser el
            // rectángulo entero —y encima levantado por encima de todo—, así
            // que la prenda seleccionada se comía cualquier toque que cayera
            // dentro de su caja aunque ahí no hubiera tela. Por eso cambiar de
            // una prenda a otra obligaba a deseleccionar primero: el toque
            // nunca llegaba a la de abajo.
            //
            // El margen para pellizcar se conserva de otra forma: el `padding`
            // de arriba agranda el rectángulo sobre el que se dibuja la
            // silueta, y la dilatación la engorda un par de celdas más. Sigue
            // habiendo dónde poner dos dedos en un tirante, pero lo
            // transparente vuelve a dejar pasar.
            .contentShape(AnyShape(AlphaShape(mask: mask, dilation: isSelected ? 2 : 0)))
            // **Primero se coge, luego se mueve.** Con el gesto siempre activo,
            // cualquier roce al desplazarse por un lienzo lleno descolocaba la
            // prenda que hubiera debajo del dedo, y deshacerlo exige darse
            // cuenta primero. Un toque selecciona —y saca sus opciones—; a
            // partir de ahí sí responde al arrastre desde el primer píxel.
            .gesture(manipulation, including: isSelected ? .all : .subviews)
            // El toque **solo mientras no está cogida**, y por eso va con
            // `including:` y no como `onTapGesture` suelto.
            //
            // Con los dos activos a la vez, el toque y el arrastre compiten:
            // el arrastre arranca sin distancia mínima, SwiftUI reconoce el
            // toque, **cancela el arrastre** y `onEnded` no llega nunca. Como
            // el commit vive ahí, `live` se descartaba y la prenda volvía de un
            // salto al sitio donde estaba.
            .gesture(
                TapGesture().onEnded { onSelect() },
                including: isSelected ? .subviews : .all
            )
            // **La única señal de que está cogida.**
            //
            // Un pelo más grande y con sombra, y nada más. El recuadro
            // punteado que había antes sobraba: con la prenda ya levantada
            // solo añadía una caja alrededor de un recorte que no es
            // rectangular, y tapaba justo lo que intentas ver al superponer.
            .scaleEffect(current.scale * (isLifted ? 1.06 : 1))
            .rotationEffect(.radians(current.rotation))
            .shadow(
                color: .black.opacity(isLifted ? 0.3 : 0),
                radius: isLifted ? 20 / canvasScale : 0,
                y: isLifted ? 10 / canvasScale : 0
            )
            // Las demás se apartan. Bajar el resto lee mucho mejor que
            // resaltar la elegida: no hay que comparar dos brillos, la
            // seleccionada es sencillamente la única que sigue entera.
            .opacity(isDimmed ? 0.5 : 1)
            .position(x: current.x, y: current.y)
            // **Encima mientras se edita, y solo mientras.**
            //
            // Es un `zIndex` de vista, no el del modelo: la prenda se pone
            // delante para poder verla entera mientras se coloca, y al
            // deseleccionar vuelve a su sitio en la pila sin haber tocado nada
            // guardado. Manipular algo que está medio tapado por otra prenda
            // es adivinar dónde queda.
            .zIndex(isLifted ? CanvasItemMetrics.liftedZIndex : current.zIndex)
            .animation(WKAnimation.interactive, value: live.isIdle)
            .animation(WKAnimation.selection, value: isSelected)
            .animation(WKAnimation.selection, value: isDimmed)
            // Al seleccionar, no al soltar: el golpe confirma que has cogido
            // la prenda que querías, que con prendas superpuestas no es obvio.
            .sensoryFeedback(.selection, trigger: isSelected)
    }

    /// Arrastrar, escalar y girar **a la vez**, en un solo gesto continuo.
    ///
    /// `minimumDistance: 0` es deliberado: una vez cogida la prenda, se mueve
    /// desde el primer píxel, sin long-press. Es posible porque solo está
    /// activo en la prenda seleccionada, así que no compite ni con el paso de
    /// página ni con el toque de las demás.
    private var manipulation: some Gesture {
        SimultaneousGesture(
            // `.global` y no el espacio local por defecto: el local **es el de
            // la prenda**, que está rotada y escalada, así que en una prenda
            // girada 30° el dedo iba en una dirección y la prenda en otra. En
            // global la traslación son puntos de pantalla de verdad, y
            // dividirla por `canvasScale` la deja justo bajo el dedo.
            DragGesture(minimumDistance: 0, coordinateSpace: .global),
            SimultaneousGesture(MagnifyGesture(), RotateGesture())
        )
        .onChanged { value in
            if let drag = value.first {
                // De puntos de pantalla a puntos de canvas. La rotación y la
                // escala son adimensionales y no se convierten.
                live.drag = CGSize(
                    width: drag.translation.width / canvasScale,
                    height: drag.translation.height / canvasScale
                )
            }
            if let magnify = value.second?.first {
                live.scale = magnify.magnification
                live.anchor = magnify.startAnchor
            }
            if let rotation = value.second?.second {
                live.rotation = rotation.rotation.radians
            }
        }
        .onEnded { _ in
            // Una única escritura, con el valor exacto. Nada de redondear.
            let committed = previewTransform
            live = Live()
            onCommit(committed)
        }
    }
}

/// Números de la manipulación.
///
/// Fuera de `CanvasItemView` porque es genérica, y Swift no admite propiedades
/// estáticas almacenadas en un tipo genérico: cada especialización necesitaría
/// la suya, y estos valores son uno solo para todas.
enum CanvasItemMetrics {
    /// Cuánto margen se le da a la prenda seleccionada para cogerla, en puntos
    /// de pantalla.
    static let grabMargin: CGFloat = 14

    /// Por encima de cualquier `zIndex` real.
    ///
    /// Los del modelo crecen de uno en uno desde cero al traer al frente, así
    /// que este no se alcanza salvo tras un millón de operaciones — y para
    /// entonces habría problemas peores.
    static let liftedZIndex: Double = 1_000_000

    /// Y la pintura, por encima incluso de eso.
    ///
    /// Hace falta un número explícito: las prendas llevan su propio `zIndex`
    /// —que crece cada vez que traes una al frente— y una capa sin `zIndex`
    /// vale cero, así que cualquier prenda que hubiera subido alguna vez se
    /// dibujaba **encima** de lo pintado. La pintura es una anotación sobre el
    /// conjunto entero: va arriba siempre, incluso sobre la prenda que estás
    /// moviendo.
    static let drawingZIndex: Double = 2_000_000
}
