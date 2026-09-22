import Foundation
import SwiftData
import WKDesign
import WKPersistence

/// Lo mínimo que una celda necesita para pintarse.
///
/// POD y `Equatable`: SwiftUI lo difunde con `memcmp`. Pasar el `Garment` en su
/// lugar crearía una dependencia sobre **todas** sus propiedades, y cambiar la
/// talla de una prenda repintaría su celda aunque la celda no muestre la talla.
struct GarmentRef: Hashable, Identifiable {
    let id: UUID
    let persistentID: PersistentIdentifier
    let name: String
    let imageKey: String
    /// Inclinación al colgar, derivada del identificador y calculada **una vez**
    /// al construir la referencia. Calcularla en el `body` haría temblar la
    /// balda entera en cada reevaluación.
    let swayDegrees: Double
    /// Su sitio en la balda. Ver `Garment.shelfOrder`.
    let shelfOrder: Double
    let dateAdded: Date

    init(_ garment: Garment) {
        id = garment.id
        persistentID = garment.persistentModelID
        name = garment.name
        shelfOrder = garment.shelfOrder
        dateAdded = garment.dateAdded
        imageKey = garment.normalizedImageKey
        let bucket = Double(abs(garment.id.hashValue % 1000)) / 1000
        swayDegrees = (bucket * 2 - 1) * WK.Shelf.maxSwayDegrees
    }
}

/// Una balda entera, en forma de valor.
///
/// Que sea `Equatable` es lo que hace que editar una prenda de "Tops" no
/// reevalúe el cuerpo de "Chaquetas": su `ShelfData` no ha cambiado, así que
/// SwiftUI se salta la vista.
struct ShelfData: Hashable, Identifiable {
    let id: String
    let name: String
    let symbol: String?
    let garments: [GarmentRef]
}
