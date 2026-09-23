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

    /// **Una sola hoja a la vez, y un solo `.sheet` que la presenta.**
    ///
    /// No es una preferencia de estilo: con dos `.sheet` puestos en la misma
    /// vista SwiftUI solo atiende a uno y el otro se queda mudo —ya nos pasó
    /// dentro del editor con el color de fondo—. Con un enum, añadir una hoja
    /// nueva es añadir un caso, y no hay forma de que la anterior deje de
    /// funcionar sin que se note.
    enum Sheet: Identifiable {
        /// La ficha de una prenda.
        case garment(GarmentRef)
        /// La inspiración con su chat.
        case inspo

        var id: String {
            switch self {
            case let .garment(ref): "garment-\(ref.id)"
            case .inspo: "inspo"
            }
        }
    }

    var sheet: Sheet?

    /// La prenda cuya ficha está abierta, si es eso lo que hay puesto.
    var garment: GarmentRef? {
        if case let .garment(ref) = sheet { return ref }
        return nil
    }

    func open(_ garment: GarmentRef) {
        sheet = .garment(garment)
    }

    func closeGarment() {
        guard case .garment = sheet else { return }
        sheet = nil
    }

    func openInspo() {
        sheet = .inspo
    }

    func close() {
        sheet = nil
    }
}
