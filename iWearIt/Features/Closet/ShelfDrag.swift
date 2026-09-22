import SwiftData
import SwiftUI
import WKDesign

/// Llevarse una prenda de una balda a otra, **a mano y no con el sistema**.
///
/// ## Por qué no `draggable`
///
/// El arrastre del sistema está pensado para copiar cosas entre apps, y se
/// nota: la vista que va bajo el dedo sale sobre una plancha cuadrada, lleva
/// el "+" verde de copiar y la prenda original se queda en la balda como si no
/// se hubiera movido. Aquí no se copia nada: la prenda **se descuelga**. Sale
/// de la balda —deja el hueco—, se levanta con su borde, va con el dedo y se
/// cuelga donde se suelte.
///
/// Y además el sistema no dejaba soltar en una balda vacía: sin prendas no
/// había sobre qué caer. Aquí el destino es la balda entera, con o sin ropa.
///
/// ## Cómo sabe dónde cae
///
/// Cada balda y cada prenda apuntan su marco al moverse la pantalla. Al
/// soltar se mira qué balda hay bajo el dedo y, dentro de ella, delante de qué
/// prenda: la primera cuyo centro queda a la derecha del dedo. Si no hay
/// ninguna, al final.
@MainActor
@Observable
final class ShelfDragModel {

    /// El espacio de coordenadas del armario, donde se miden todos los marcos
    /// y donde se dibuja la prenda levantada.
    static let space = "closet.drag"

    /// Lo que va colgando del dedo.
    private(set) var dragged: GarmentRef?
    /// De qué balda salió. Para devolverla si se suelta en ningún sitio.
    private(set) var origin: String?
    /// Dónde está el dedo.
    private(set) var location: CGPoint = .zero
    /// Dónde se agarró la prenda respecto a su centro, para que no salte al
    /// dedo al levantarla.
    private(set) var grab: CGSize = .zero
    /// Dónde caería si se soltara ahora.
    private(set) var target: GarmentDrop?
    /// Bajando a su sitio: la misma animación que al levantarla, al revés.
    private(set) var isLanding = false
    /// La que acaba de colgarse. Entra en la balda sin su animación de
    /// llegada, porque ya ha llegado: la que se ve bajar es ella.
    private(set) var justLanded: UUID?
    /// Su marco al descolgarla, para devolverla si se suelta en ningún sitio.
    @ObservationIgnored private var originFrame: CGRect = .zero
    /// Cuándo acabó el último arrastre.
    @ObservationIgnored private var endedAt: Date?

    /// Si una prenda debe ignorar un toque ahora mismo.
    ///
    /// Al soltar una prenda el dedo se levanta, y para el botón que hay debajo
    /// eso es un toque: sin esto, cada arrastre acababa abriendo la ficha de
    /// la prenda. Mientras se arrastra y un instante después, no se abre nada.
    var ignoresTaps: Bool {
        if dragged != nil { return true }
        guard let endedAt else { return false }
        return Date.now.timeIntervalSince(endedAt) < 0.6
    }

    var isDragging: Bool { dragged != nil }

    /// La prenda cuyo toque largo acaba de completarse, antes de moverse.
    ///
    /// Es el momento en que hay que **congelar el scroll**, no cuando el dedo
    /// empieza a moverse: entre una cosa y otra, la balda todavía se llevaba
    /// la prenda unos puntos con el dedo y el arrastre arrancaba desplazado.
    private(set) var armed: UUID?

    /// Si el scroll tiene que estar quieto.
    var locksScroll: Bool { dragged != nil || armed != nil }

    func arm(_ id: UUID) {
        guard armed != id else { return }
        armed = id
    }

    func disarm() { armed = nil }

    /// Los marcos. Fuera de la observación: se escriben en cada fotograma de
    /// scroll y nadie los pinta, solo se consultan al mover y al soltar.
    @ObservationIgnored private var shelfFrames: [String: CGRect] = [:]
    @ObservationIgnored private var itemFrames: [UUID: (slug: String, frame: CGRect)] = [:]

    func register(shelf slug: String, frame: CGRect) { shelfFrames[slug] = frame }

    /// La fila de prendas de cada balda, sin cabecera ni tablero. Hace falta
    /// para saber dónde colgar en una balda **vacía**: el marco de la balda
    /// entera incluye el título y el canto, y su centro no es donde van las
    /// prendas.
    @ObservationIgnored private var rowFrames: [String: CGRect] = [:]

    func register(row slug: String, frame: CGRect) { rowFrames[slug] = frame }

    func register(item id: UUID, in slug: String, frame: CGRect) {
        itemFrames[id] = (slug, frame)
    }

    func forget(item id: UUID) { itemFrames[id] = nil }

    /// Se descuelga.
    func begin(_ garment: GarmentRef, from slug: String, at point: CGPoint) {
        guard dragged == nil else { return }
        let frame = itemFrames[garment.id]?.frame ?? CGRect(origin: point, size: .zero)
        originFrame = frame
        grab = CGSize(width: point.x - frame.midX, height: point.y - frame.midY)
        location = point
        origin = slug
        dragged = garment
        target = drop(at: point)
    }

    func move(to point: CGPoint) {
        guard dragged != nil, !isLanding else { return }
        location = point
        let next = drop(at: point)
        if next != target { target = next }
    }

    /// Vuelve a mirar qué hay bajo el dedo sin que el dedo se haya movido:
    /// lo que se mueve es el armario por debajo.
    func refreshTarget() {
        guard dragged != nil, !isLanding else { return }
        let next = drop(at: location)
        if next != target { target = next }
    }

    /// **Se cuelga, bajando.** Devuelve si se movió.
    ///
    /// Primero baja a su hueco con la misma animación con la que se levantó
    /// —al revés: pierde el tamaño, la inclinación y la sombra— y solo
    /// entonces se escribe el cambio, con la prenda ya en su sitio. Sin esto
    /// la levantada desaparecía de golpe y la de la balda aparecía creciendo:
    /// dos prendas para un solo movimiento.
    ///
    /// Soltada en ningún sitio, vuelve a donde estaba igual.
    @discardableResult
    func land(in context: ModelContext) async -> Bool {
        guard let dragged, !isLanding else { return false }

        let moves: Bool
        let point: CGPoint
        if let target, target != .before(dragged.id) {
            moves = true
            point = landingPoint(for: target)
        } else {
            moves = false
            point = CGPoint(x: originFrame.midX, y: originFrame.midY)
        }

        withAnimation(Self.lift) {
            isLanding = true
            location = point
            grab = .zero
        }
        try? await Task.sleep(for: .milliseconds(280))

        // **Sin animar el cambio.** La levantada ya está encima de su hueco,
        // y el hueco mide lo mismo que la prenda: cambiar una por otra de
        // golpe no mueve nada. Animándolo, la prenda de la balda —que es la
        // misma vista que se descolgó— aparecía un instante en su sitio de
        // antes y viajaba hasta el nuevo.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            justLanded = dragged.id
            if moves, let target { GarmentMover.move(dragged.id, to: target, in: context) }
            self.dragged = nil
            self.target = nil
            origin = nil
            isLanding = false
        }
        endedAt = .now
        armed = nil
        try? await Task.sleep(for: .milliseconds(500))
        justLanded = nil
        return moves
    }

    /// El muelle de levantar y de posar: el mismo en los dos sentidos.
    static let lift = Animation.spring(duration: 0.3, bounce: 0.35)

    /// Dónde queda su centro una vez colgada.
    private func landingPoint(for target: GarmentDrop) -> CGPoint {
        switch target {
        case let .before(id):
            // Ocupa el sitio donde ahora empieza la de delante: su marco ya
            // incluye el hueco que se le ha abierto.
            let frame = itemFrames[id]?.frame ?? originFrame
            return CGPoint(x: frame.minX + WK.Shelf.garmentWidth / 2, y: frame.midY)
        case let .endOf(slug):
            let last = itemFrames
                .filter { $0.value.slug == slug && $0.key != dragged?.id }
                .max { $0.value.frame.maxX < $1.value.frame.maxX }?
                .value.frame
            if let last {
                // El marco ya incluye la separación de detrás.
                return CGPoint(
                    x: last.maxX + WK.Shelf.garmentWidth / 2,
                    y: last.midY
                )
            }
            // **Balda vacía:** al principio de su fila y a la altura a la que
            // cuelgan las prendas —pegadas abajo, como en cualquier balda—.
            // Antes se calculaba sobre la balda entera, cabecera y canto
            // incluidos, y caía por debajo de donde luego aparecía.
            let row = rowFrames[slug] ?? shelfFrames[slug] ?? originFrame
            let itemHeight = itemFrames.values.first?.frame.height ?? originFrame.height
            return CGPoint(
                x: row.minX + WK.Spacing.screenInset + WK.Shelf.garmentWidth / 2,
                y: row.maxY - itemHeight / 2
            )
        }
    }

    /// Qué balda hay bajo el dedo y delante de qué prenda.
    private func drop(at point: CGPoint) -> GarmentDrop? {
        guard let slug = shelfFrames.first(where: { $0.value.contains(point) })?.key else {
            return nil
        }
        let next = itemFrames
            .filter { $0.value.slug == slug && $0.key != dragged?.id }
            .sorted { $0.value.frame.minX < $1.value.frame.minX }
            .first { $0.value.frame.midX > point.x }
        if let next { return .before(next.key) }
        return .endOf(slug: slug)
    }
}

/// La prenda levantada, siguiendo al dedo por encima de todo el armario.
struct ShelfDragOverlay: View {
    let model: ShelfDragModel

    @State private var isLifted = false

    var body: some View {
        // Levantada mientras va en el dedo; al posarse, deshace exactamente
        // lo mismo con el mismo muelle.
        let isLifted = isLifted && !model.isLanding
        if let garment = model.dragged {
            HangingGarmentView(garment: garment)
                .frame(width: WK.Shelf.garmentWidth)
                // Sin borde ni sombra añadidos: la prenda en el dedo es la
                // misma que colgaba, con su propia sombra y nada más. Lo que la
                // levanta es el tamaño y la inclinación.
                //
                // .shadow(color: .white, radius: 0.8)
                // .shadow(color: .white, radius: 0.8)
                // .shadow(color: .white, radius: 0.8)
                // .shadow(color: WK.Palette.ink(0.28), radius: isLifted ? 22 : 6, y: isLifted ? 18 : 4)
                .scaleEffect(isLifted ? 1.12 : 1)
                .rotationEffect(.degrees(isLifted ? 4 : 0))
                .position(
                    x: model.location.x - model.grab.width,
                    y: model.location.y - model.grab.height
                )
                .allowsHitTesting(false)
                .animation(ShelfDragModel.lift, value: model.isLanding)
                .onAppear {
                    withAnimation(ShelfDragModel.lift) { self.isLifted = true }
                }
                .onDisappear { self.isLifted = false }
        }
    }
}
