import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WKCore
import WKPersistence

/// Mover prendas: dentro de su balda y de una balda a otra.
///
/// ## Por qué arrastrando y no con un menú
///
/// "Mover a…" con una lista de baldas es correcto y es lo que hace todo el
/// mundo, pero un armario no se ordena así: se ordena cogiendo una prenda y
/// poniéndola donde va. Arrastrar dice a la vez **qué** se mueve, **dónde** y
/// **en qué sitio exacto** de la balda, que son tres respuestas en un gesto.
///
/// El pulsar y mantener es lo que separa arrastrar de hacer scroll: sin él,
/// pasar la balda con el dedo se llevaría la prenda por delante.
struct GarmentTransfer: Codable, Transferable {
    /// El identificador estable, no el `PersistentIdentifier`: este viaja por
    /// el portapapeles del sistema y tiene que poder leerse al otro lado.
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .iWearItGarment)
    }
}

extension UTType {
    /// Tipo propio y no `.text`: así una prenda solo se puede soltar en sitios
    /// de esta app que sepan qué hacer con ella, y arrastrarla a Mensajes no
    /// deja caer un UUID suelto.
    ///
    /// `nonisolated` porque lo lee la representación de transferencia, que el
    /// sistema evalúa fuera del hilo principal.
    nonisolated static let iWearItGarment = UTType(exportedAs: "com.gabrisp.iWearIt.garment")
}

/// Dónde cae una prenda soltada.
enum GarmentDrop: Equatable {
    /// Antes de esta otra prenda.
    case before(UUID)
    /// Al final de esta balda.
    case endOf(slug: String)
}

/// Aplica el movimiento sobre la base de datos.
///
/// En un sitio y no repartido por las vistas: mover una prenda es cambiarle la
/// balda **y** su sitio dentro de ella, y hacer solo una de las dos cosas deja
/// la prenda colocada donde no la soltaste.
@MainActor
enum GarmentMover {

    /// Cuánto se separa una prenda de la siguiente cuando se pone al final.
    private static let step: Double = 1024

    static func move(_ id: UUID, to drop: GarmentDrop, in context: ModelContext) {
        guard let moved = garment(id, in: context) else { return }

        // **Se renumera la balda de destino entera.**
        //
        // Antes se ponía la prenda a medio camino entre sus dos vecinas. Pero
        // todas las prendas nacen con el orden a cero, así que entre dos que
        // nadie había tocado el "medio camino" era cero otra vez: empataba con
        // todas, el desempate lo decidía la fecha, y la prenda caía a veces
        // donde la soltabas y a veces al principio.
        //
        // Numerando la balda de nuevo —en el orden en que se ve, con la prenda
        // ya metida en su sitio— no queda ningún empate que desempatar. Son
        // tantas escrituras como prendas tiene la balda, que son pocas.
        let category: GarmentCategory
        var sequence: [Garment]

        switch drop {
        case let .before(targetID):
            guard
                let target = garment(targetID, in: context),
                target.id != moved.id,
                let targetCategory = target.category
            else { return }
            category = targetCategory
            sequence = ordered(in: category, excluding: moved)
            let index = sequence.firstIndex { $0.id == target.id } ?? sequence.count
            sequence.insert(moved, at: index)

        case let .endOf(slug):
            guard let slugCategory = self.category(slug, in: context) else { return }
            category = slugCategory
            sequence = ordered(in: category, excluding: moved)
            sequence.append(moved)
        }

        for (position, item) in sequence.enumerated() {
            let order = Double(position + 1) * step
            // Solo lo que cambia: escribir el mismo valor también cuenta como
            // cambio para la sincronización.
            if item.shelfOrder != order { item.shelfOrder = order }
        }
        moved.category = category
        moved.categoryLockedByUser = true

        moved.modifiedAt = .now
    }

    /// Las prendas de una balda, en el orden en que se ven.
    ///
    /// Con el mismo criterio que la balda: lo colocado a mano primero y, a
    /// igualdad, lo más reciente. Ordenar aquí de otra manera dejaría la
    /// prenda en un sitio distinto del que se ve al soltarla.
    private static func ordered(
        in category: GarmentCategory,
        excluding excluded: Garment
    ) -> [Garment] {
        category.garments
            .filter { $0.deletedAt == nil && $0.id != excluded.id }
            .sorted {
                $0.shelfOrder == $1.shelfOrder
                    ? $0.dateAdded > $1.dateAdded
                    : $0.shelfOrder < $1.shelfOrder
            }
    }

    private static func garment(_ id: UUID, in context: ModelContext) -> Garment? {
        var descriptor = FetchDescriptor<Garment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func category(_ slug: String, in context: ModelContext) -> GarmentCategory? {
        var descriptor = FetchDescriptor<GarmentCategory>(predicate: #Predicate { $0.slug == slug })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
