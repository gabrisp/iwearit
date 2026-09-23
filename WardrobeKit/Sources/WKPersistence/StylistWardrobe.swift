import Foundation
import SwiftData
import WKCore

public extension Garment {
    /// La prenda como la ve el estilista.
    var stylistValue: StylistGarment {
        StylistGarment(
            id: id,
            kind: kind,
            name: name,
            colors: colors,
            seasons: seasons,
            tags: tags,
            subcategory: subcategory,
            material: material,
            lastWornAt: lastWornAt,
            wearCount: wearCount,
            isFavorite: isFavorite,
            imageKey: normalizedImageKey
        )
    }
}

public extension ModelContext {

    /// Todo el armario, como valores.
    ///
    /// Se lee entero y de una vez: el estilista necesita ver todo lo que hay
    /// para combinar, y una consulta por hueco sería cuatro viajes a la base
    /// para acabar con lo mismo.
    func stylistWardrobe() -> [StylistGarment] {
        let garments = (try? fetch(FetchDescriptor<Garment>.visibleGarments())) ?? []
        return garments
            // Sin recorte no se puede enseñar, y un conjunto con un hueco no
            // es una propuesta.
            .filter { !$0.normalizedImageKey.isEmpty }
            // Y sin las baldas que has dejado fuera. Ver
            // `GarmentCategory.isExcludedFromInspo`.
            .filter { $0.category?.isExcludedFromInspo != true }
            .map(\.stylistValue)
    }

    /// Qué te pusiste estos días atrás, según el planificador.
    ///
    /// Esto es lo que permite decir "el vaquero de ayer no". No se mira
    /// `wearCount` ni `lastWornAt` a secas porque esos solo se mueven si
    /// marcas la prenda a mano; el plan, en cambio, **ya está escrito**: si
    /// ayer montaste un conjunto para ayer, ahí está lo que llevabas.
    /// - Parameter days: cuántos días hacia atrás contar.
    func recentlyWornGarments(days: Int = 10, from date: Date = Date()) -> [UUID: Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        guard let floor = calendar.date(byAdding: .day, value: -days, to: today) else { return [:] }

        let descriptor = FetchDescriptor<PlannedDay>(
            predicate: #Predicate { $0.dayStart >= floor && $0.dayStart <= today }
        )
        let plannedDays = (try? fetch(descriptor)) ?? []

        var worn: [UUID: Date] = [:]
        for day in plannedDays {
            for outfit in day.orderedOutfits {
                for garment in outfit.garments {
                    // La más reciente manda: si una prenda salió el lunes y el
                    // jueves, lo que pesa es el jueves.
                    if let existing = worn[garment.id], existing >= day.dayStart { continue }
                    worn[garment.id] = day.dayStart
                }
            }
        }
        return worn
    }
}
