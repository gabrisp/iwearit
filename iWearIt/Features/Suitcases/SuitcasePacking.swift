import Foundation
import SwiftData
import WKCore
import WKPersistence

/// Reglas de qué entra en la maleta.
///
/// Aparte de las vistas porque lo usan tres sitios —los días del viaje, los
/// outfits preparados y el checklist— y duplicarlo llevaría a que una ruta
/// olvidara apuntar la prenda.
enum SuitcasePacking {

    /// Añade una prenda a un outfit **y** al checklist.
    ///
    /// Las dos cosas a la vez: preparar el outfit y hacer la maleta son la misma
    /// tarea desde el punto de vista del usuario.
    static func add(
        _ garment: Garment,
        to outfit: Outfit,
        suitcase: Suitcase,
        context: ModelContext
    ) {
        let step = Double(outfit.items.count)
        let item = CanvasItem(
            transform: ItemTransform(
                x: CanvasSpace.center.x + step * 26,
                y: CanvasSpace.center.y + step * 26,
                baseWidth: 300,
                baseHeight: 380,
                zIndex: outfit.nextZIndex
            ),
            garment: garment
        )
        item.outfit = outfit
        context.insert(item)
        ensureEntry(for: garment, in: suitcase, context: context)
    }

    /// Apunta la prenda en el checklist si no estaba ya.
    ///
    /// Idempotente: la misma camiseta en tres outfits del viaje es **una** línea
    /// del checklist, no tres. Solo se mete una vez en la maleta.
    static func ensureEntry(for garment: Garment, in suitcase: Suitcase, context: ModelContext) {
        let alreadyListed = suitcase.packingEntries.contains { $0.garment?.id == garment.id }
        guard !alreadyListed else { return }

        let entry = PackingEntry(garment: garment)
        context.insert(entry)
        entry.suitcase = suitcase
    }
}
