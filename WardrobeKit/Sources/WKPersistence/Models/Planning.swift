import Foundation
import SwiftData

/// Un día del planificador.
@Model
public final class PlannedDay {
    // Sin `#Unique`: CloudKit no lo soporta. Dos dispositivos pueden crear el
    // mismo día a la vez; el arreglo es fusionarlos, no impedirlo.

    /// Normalizado a `startOfDay` en el calendario del usuario. Es la clave
    /// única, así que dos vistas nunca pueden crear dos días para la misma fecha.
    public var dayStart: Date = Date()
    public var note: String?

    /// Los outfits del día. **Varios, no uno.**
    ///
    /// Un día tiene más de un momento: lo que te pones para comer no es lo que
    /// te pones para cenar. Con un solo outfit por día había que elegir cuál de
    /// los dos merecía guardarse, que es una decisión que la app no tiene por
    /// qué pedir.
    ///
    /// Ordenados por `createdAt`: el orden en que se montaron es el orden en el
    /// que se recuerdan, y reordenarlos por otra cosa haría que el lienzo de
    /// arriba cambiara solo.
    @Relationship(deleteRule: .cascade, inverse: \Outfit.plannedDay)
    public var outfits: [Outfit] = []

    /// Los outfits en orden estable.
    public var orderedOutfits: [Outfit] {
        outfits.sorted { $0.createdAt < $1.createdAt }
    }

    public init(dayStart: Date, calendar: Calendar = .current) {
        self.dayStart = calendar.startOfDay(for: dayStart)
    }
}
