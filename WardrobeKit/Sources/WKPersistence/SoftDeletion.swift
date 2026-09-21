import Foundation
import SwiftData

/// Un objeto que se marca para eliminar en vez de borrarse.
///
/// ## Por qué no se borra de verdad
///
/// Porque va a haber sincronización, y en cuanto la hay el borrado es la única
/// operación que no tiene vuelta atrás. Todo lo demás converge: dos ediciones
/// se mezclan, dos objetos creados a la vez conviven, un cambio que llega tarde
/// se aplica tarde. Un borrado que llega por error se lleva algo que en el otro
/// dispositivo estaba perfectamente.
///
/// La regla de toda la sincronización es **conservar por encima de propagar el
/// borrado**, y esto es su forma concreta: `context.delete` desaparece del
/// código de producto y se sustituye por una marca. Lo marcado no se ve, pero
/// existe, se puede devolver y —sobre todo— no puede perderse por una carrera
/// entre dos dispositivos.
///
/// ## Qué no hace
///
/// No purga. En esta primera versión **nada se borra físicamente**: un
/// tombstone son unos cientos de bytes y la alternativa es arriesgar fotos del
/// usuario para ahorrar disco. Cuando haya datos reales de qué dispositivos han
/// visto qué, la purga se podrá añadir encima sin tocar esto.
public protocol SoftDeletable: AnyObject {
    var modifiedAt: Date { get set }
    var deletedAt: Date? { get set }
}

public extension SoftDeletable {

    /// Si el usuario debe verlo.
    var isVisible: Bool { deletedAt == nil }

    /// Lo esconde. No lo borra.
    ///
    /// **No toca `modifiedAt` a propósito.** Esa fecha es "cuándo se editó por
    /// última vez", y el borrado ya se anota en `deletedAt`. Si el borrado
    /// también contara como edición, las dos fechas quedarían iguales y la
    /// regla de resolución —que ante el empate conserva— devolvería el objeto
    /// en el mismo instante de marcarlo.
    func markDeleted(at date: Date = Date()) {
        guard deletedAt == nil else { return }
        deletedAt = date
    }

    /// Lo devuelve.
    ///
    /// Existe desde el primer día aunque todavía no haya pantalla que lo use:
    /// es lo que convierte el borrado en una operación reversible, y es lo que
    /// aplica la resolución de conflictos cuando una edición llega después de
    /// un borrado.
    func restore(at date: Date = Date()) {
        deletedAt = nil
        modifiedAt = date
    }

    /// Marca que ha cambiado.
    ///
    /// Hace falta para una sola decisión, pero es la importante: si un
    /// dispositivo marcó el objeto para borrar y otro lo estaba editando, gana
    /// la edición **si es posterior**. Sin una fecha de modificación las dos
    /// cosas llegan mezcladas y no hay forma de saber cuál iba después.
    func touch(_ date: Date = Date()) {
        modifiedAt = date
    }

    /// Resuelve el caso "uno lo borró, otro lo editó".
    ///
    /// Conservador por diseño: solo se queda borrado si **nadie** lo tocó
    /// después. En cualquier otro caso vuelve — incluido el empate, porque un
    /// empate es exactamente la duda que la regla manda resolver conservando.
    func resolveDeletionAgainstEdits() {
        guard let deletedAt else { return }
        if modifiedAt >= deletedAt { restore() }
    }
}

extension Garment: SoftDeletable {}
extension GarmentCategory: SoftDeletable {}
extension Outfit: SoftDeletable {}
extension Suitcase: SoftDeletable {}

// MARK: - Consultas que ya excluyen lo marcado

/// Las consultas de la app, con el filtro de tombstones **puesto de fábrica**.
///
/// La alternativa era añadir `deletedAt == nil` en los veintidós `@Query` de
/// las pantallas, y eso es una forma segura de que dentro de dos meses haya
/// una pantalla nueva que enseñe prendas borradas. Aquí el filtro vive en un
/// sitio y las pantallas piden la consulta por su nombre.
///
/// El subsistema de sincronización **no** usa estas: necesita ver lo marcado,
/// que para eso está marcado y no borrado.
public extension FetchDescriptor where T == Garment {

    static func visibleGarments(
        sortedBy order: SortOrder = .reverse
    ) -> FetchDescriptor<Garment> {
        FetchDescriptor<Garment>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.dateAdded, order: order)]
        )
    }

    static func visibleGarments(inCategoryWithSlug slug: String) -> FetchDescriptor<Garment> {
        FetchDescriptor<Garment>(
            predicate: #Predicate { $0.deletedAt == nil && $0.category?.slug == slug },
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
    }
}

public extension FetchDescriptor where T == GarmentCategory {

    static func visibleCategories() -> FetchDescriptor<GarmentCategory> {
        FetchDescriptor<GarmentCategory>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
    }
}

public extension FetchDescriptor where T == Suitcase {

    static func visibleSuitcases() -> FetchDescriptor<Suitcase> {
        FetchDescriptor<Suitcase>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }
}

public extension FetchDescriptor where T == Outfit {

    static func visibleOutfits() -> FetchDescriptor<Outfit> {
        FetchDescriptor<Outfit>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }
}

// MARK: - Relaciones

public extension Outfit {
    /// Las piezas que hay que dibujar.
    ///
    /// Una relación no entiende de tombstones: `items` trae también las prendas
    /// marcadas para borrar, y el lienzo las pintaría tan contento. Aquí se
    /// filtra por las dos vías —la pieza y la prenda a la que apunta—, que es
    /// lo que hace que borrar una prenda la quite de todos los outfits sin
    /// destruir la colocación por si vuelve.
    var visibleItems: [CanvasItem] {
        items.filter { item in
            guard let garment = item.garment else { return true }  // sticker o hueco
            return garment.deletedAt == nil
        }
    }
}

public extension Suitcase {
    var visibleOutfits: [Outfit] {
        outfits.filter { $0.deletedAt == nil }
    }
}

public extension GarmentCategory {
    var visibleGarments: [Garment] {
        garments.filter { $0.deletedAt == nil }
    }
}
