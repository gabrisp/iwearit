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

    var isDragging: Bool { dragged != nil }

    /// Los marcos. Fuera de la observación: se escriben en cada fotograma de
    /// scroll y nadie los pinta, solo se consultan al mover y al soltar.
    @ObservationIgnored private var shelfFrames: [String: CGRect] = [:]
    @ObservationIgnored private var itemFrames: [UUID: (slug: String, frame: CGRect)] = [:]

    func register(shelf slug: String, frame: CGRect) { shelfFrames[slug] = frame }

    func register(item id: UUID, in slug: String, frame: CGRect) {
        itemFrames[id] = (slug, frame)
    }

    func forget(item id: UUID) { itemFrames[id] = nil }

    /// Se descuelga.
    func begin(_ garment: GarmentRef, from slug: String, at point: CGPoint) {
        guard dragged == nil else { return }
        let frame = itemFrames[garment.id]?.frame ?? CGRect(origin: point, size: .zero)
        grab = CGSize(width: point.x - frame.midX, height: point.y - frame.midY)
        location = point
        origin = slug
        dragged = garment
        target = drop(at: point)
    }

    func move(to point: CGPoint) {
        guard dragged != nil else { return }
        location = point
        let next = drop(at: point)
        if next != target { target = next }
    }

    /// Se cuelga donde esté el dedo. Devuelve si se movió.
    @discardableResult
    func end(in context: ModelContext) -> Bool {
        defer {
            dragged = nil
            origin = nil
            target = nil
        }
        guard let dragged, let target else { return false }
        // Soltarla delante de sí misma es dejarla donde estaba.
        if case let .before(id) = target, id == dragged.id { return false }
        GarmentMover.move(dragged.id, to: target, in: context)
        return true
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
        if let garment = model.dragged {
            HangingGarmentView(garment: garment)
                .frame(width: WK.Shelf.garmentWidth)
                // **El borde.** Tres halos blancos apilados dibujan el canto
                // de pegatina alrededor de la silueta —no un rectángulo—, que
                // es lo que hace que se lea como la prenda despegándose y no
                // como una captura de pantalla.
                .shadow(color: .white, radius: 0.8)
                .shadow(color: .white, radius: 0.8)
                .shadow(color: .white, radius: 0.8)
                // Y la sombra de estar en el aire, más lejos cuanto más alta.
                .shadow(color: WK.Palette.ink(0.28), radius: isLifted ? 22 : 6, y: isLifted ? 18 : 4)
                .scaleEffect(isLifted ? 1.12 : 1)
                .rotationEffect(.degrees(isLifted ? 4 : 0))
                .position(
                    x: model.location.x - model.grab.width,
                    y: model.location.y - model.grab.height
                )
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.spring(duration: 0.3, bounce: 0.35)) { isLifted = true }
                }
                .onDisappear { isLifted = false }
        }
    }
}
