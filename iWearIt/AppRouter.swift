import SwiftData
import SwiftUI

/// Quién presenta las hojas de la app.
///
/// ## Por qué existe
///
/// Porque una hoja presentada por la celda que la abre **se muere con ella**.
/// Tocabas una prenda, la borrabas o le quitabas el favorito estando en
/// Favoritas, y la prenda salía de la lista: la percha que sostenía la hoja
/// dejaba de existir y la hoja se desmontaba a medias —el borrón que se veía—
/// o se quedaba enseñando algo que ya no está.
///
/// Con un router en la raíz, la hoja la presenta quien no se va nunca. La
/// celda solo dice "abre esta prenda".
@MainActor
@Observable
final class AppRouter {
    /// La prenda cuya ficha está abierta.
    var garment: GarmentRef?

    func open(_ garment: GarmentRef) {
        self.garment = garment
    }

    func closeGarment() {
        garment = nil
    }
}
