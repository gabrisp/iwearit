import Foundation
import SwiftData
import WKCore
import WKPersistence

/// Deshacer y rehacer en el editor, **sin el `UndoManager` de SwiftData**.
///
/// ## Por qué no el del contexto
///
/// Porque se probó dos veces y las dos se llevó la app por delante. Puesto en
/// el contexto de la aplicación, el editor ni se abría; puesto en el de la
/// sesión, reventaba al deshacer. El registro automático de SwiftData deshace
/// cambios **de objetos y relaciones** en un grafo que además está detrás de
/// la sincronización, y ahí hay demasiadas piezas que no controlamos.
///
/// ## Qué hace esto en su lugar
///
/// Guarda **cómo estaba el lienzo**, no qué cambió. Un lienzo son diez o
/// quince piezas con su posición, su giro y qué llevan dentro: cabe entero en
/// una estructura de valor y copiarla cuesta menos que lo que tarda el dedo en
/// levantarse. Deshacer es volver a escribir una de esas copias.
///
/// La ventaja no es solo que no explota: una instantánea no puede quedarse a
/// medias. El registro de operaciones sí — basta con que una operación no se
/// registre para que deshacer deje el lienzo en un estado que nunca existió.
@MainActor
@Observable
final class CanvasHistory {

    /// Cuántos pasos atrás se pueden dar.
    ///
    /// Veinte y no ilimitado: cada uno es una copia del lienzo entero, y más
    /// allá de veinte nadie deshace — se sale sin guardar, que además es
    /// instantáneo.
    static let depth = 20

    private var past: [CanvasSnapshot] = []
    private var future: [CanvasSnapshot] = []

    /// Lo que el propio deshacer acaba de escribir.
    ///
    /// **Una bandera no servía**, y ese era el bucle: `onChange` no se dispara
    /// mientras se escribe, sino en la siguiente pasada de la vista, cuando la
    /// bandera ya se había bajado. Así que el deshacer se apuntaba como un
    /// paso más, y volver a pulsar deshacía el deshacer: la pila entera se
    /// convertía en dos estados dando vueltas.
    ///
    /// Guardando **qué** se escribió, el aviso que llega después se reconoce
    /// por su contenido y no por el momento en que llega.
    private var justApplied: CanvasSnapshot?

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    /// Apunta cómo estaba el lienzo **antes** del cambio que acaba de pasar.
    /// - Parameters:
    ///   - previous: cómo estaba antes del cambio.
    ///   - current: cómo está ahora. Sirve para reconocer el eco del propio
    ///     deshacer.
    func record(_ previous: CanvasSnapshot, current: CanvasSnapshot) {
        if let justApplied, justApplied == current {
            self.justApplied = nil
            return
        }
        past.append(previous)
        if past.count > Self.depth { past.removeFirst() }
        // Rehacer deja de tener sentido en cuanto haces algo nuevo: la rama
        // que llevaba a ese futuro ya no existe.
        future.removeAll()
    }

    /// El estado al que volver, guardando el actual para poder rehacer.
    func undo(from current: CanvasSnapshot) -> CanvasSnapshot? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }

    func redo(from current: CanvasSnapshot) -> CanvasSnapshot? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }

    /// Anuncia lo que se va a escribir, para que el aviso de cambio que
    /// llegue después se reconozca y no se apunte como un paso nuevo.
    func willApply(_ state: CanvasSnapshot) {
        justApplied = state
    }
}

/// Cómo estaba el lienzo en un momento dado.
///
/// Campos planos y no el `CanvasSticker` compuesto: estos son exactamente los
/// que guarda el modelo, así que comparar dos instantáneas es comparar lo que
/// de verdad se escribe, y restaurar es copiarlos de vuelta sin interpretar
/// nada por el camino.
struct CanvasSnapshot: Equatable {

    struct Item: Equatable {
        var id: UUID
        var transform: ItemTransform
        var isFlipped: Bool
        var garment: PersistentIdentifier?

        var stickerKindRaw: String?
        var text: String?
        var textColorHex: String?
        var textBackgroundHex: String?
        var textAlignmentRaw: String?
        var date: Date?
        var imageKey: String?
        var weatherData: Data?
    }

    var items: [Item]
    var drawing: Data?
    var backdrop: String?

    init(_ outfit: Outfit) {
        // Ordenadas por id: el orden en que SwiftData devuelve la relación no
        // está garantizado, y sin ordenar dos instantáneas idénticas podrían
        // compararse distintas y apuntar un paso que no existió.
        items = outfit.visibleItems
            .map { item in
                Item(
                    id: item.id,
                    transform: item.transform,
                    isFlipped: item.isFlipped,
                    garment: item.garment?.persistentModelID,
                    stickerKindRaw: item.stickerKindRaw,
                    text: item.text,
                    textColorHex: item.textColorHex,
                    textBackgroundHex: item.textBackgroundHex,
                    textAlignmentRaw: item.textAlignmentRaw,
                    date: item.date,
                    imageKey: item.imageKey,
                    weatherData: item.weatherData
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        drawing = outfit.drawingData
        backdrop = outfit.backdropRaw
    }

    /// Vuelve a dejar el lienzo como estaba.
    ///
    /// Reconcilia en vez de borrar y rehacer: lo que sigue existiendo se
    /// actualiza, lo que sobra se borra y lo que falta se crea. Borrarlo todo
    /// y recrearlo daría el mismo dibujo con objetos nuevos, y con ellos se
    /// perdería la selección, las máscaras cacheadas y cualquier animación en
    /// curso.
    func restore(into outfit: Outfit, context: ModelContext) {
        let existing = Dictionary(
            outfit.items.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let wanted = Set(items.map(\.id))

        for item in outfit.items where !wanted.contains(item.id) {
            context.delete(item)
        }

        for snapshot in items {
            let item = existing[snapshot.id] ?? make(snapshot, in: outfit, context: context)
            item.apply(snapshot.transform)
            item.isFlipped = snapshot.isFlipped
            item.stickerKindRaw = snapshot.stickerKindRaw
            item.text = snapshot.text
            item.textColorHex = snapshot.textColorHex
            item.textBackgroundHex = snapshot.textBackgroundHex
            item.textAlignmentRaw = snapshot.textAlignmentRaw
            item.date = snapshot.date
            item.imageKey = snapshot.imageKey
            item.weatherData = snapshot.weatherData

            // La prenda se resuelve en **este** contexto: un
            // `PersistentIdentifier` es válido en cualquiera, pero el objeto
            // no, y asignar uno de otro contexto es lo que revienta.
            if let id = snapshot.garment {
                item.garment = context.model(for: id) as? Garment
            } else {
                item.garment = nil
            }
        }

        outfit.drawingData = drawing
        outfit.backdropRaw = backdrop
    }

    private func make(
        _ snapshot: Item,
        in outfit: Outfit,
        context: ModelContext
    ) -> CanvasItem {
        let item = CanvasItem(transform: snapshot.transform, garment: nil)
        // **El mismo id que tenía.** Es lo que hace que deshacer un borrado
        // devuelva la pieza y no una copia: la siguiente instantánea la
        // reconoce, y rehacer vuelve a quitarla sin dejar huérfanos.
        item.id = snapshot.id
        item.outfit = outfit
        context.insert(item)
        return item
    }
}
