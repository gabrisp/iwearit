import SwiftData
import WKPersistence
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
        /// El chat con el estilista.
        case stylist

        var id: String {
            switch self {
            case let .garment(ref): "garment-\(ref.id)"
            case .stylist: "stylist"
            }
        }
    }

    var sheet: Sheet?

    /// Qué outfit hay que abrir en el editor, pedido desde una hoja.
    ///
    /// ## Por qué pasa por aquí
    ///
    /// Porque el editor es una pantalla de la pila de navegación y el
    /// estilista es una hoja puesta encima: desde dentro de la hoja no hay
    /// pila a la que empujar. La hoja pide, el router apunta y la pantalla de
    /// abajo —que sí tiene pila— lo empuja.
    var editRequest: OutfitRef?

    /// Si al cerrar ese editor hay que volver a abrir el estilista.
    ///
    /// Editar desde el chat es un paréntesis, no una salida: cierras, tocas,
    /// vuelves y la conversación sigue donde estaba (ver `StylistChat`).
    var reopensStylist = false

    /// Una referencia a un outfit que puede cruzar vistas.
    struct OutfitRef: Hashable, Identifiable {
        let id: UUID
        let persistentID: PersistentIdentifier
    }

    /// Cierra el estilista, abre el editor y deja dicho que hay que volver.
    func editFromStylist(_ outfit: Outfit) {
        editRequest = OutfitRef(id: outfit.stableID, persistentID: outfit.persistentModelID)
        reopensStylist = true
        sheet = nil
    }

    /// El editor se ha cerrado: si venía del estilista, se vuelve a él.
    func finishedEditing() {
        editRequest = nil
        guard reopensStylist else { return }
        reopensStylist = false
        sheet = .stylist
    }

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

    /// El chat **sí** es una hoja: se abre, se pide y se cierra. La
    /// inspiración, en cambio, es una pestaña: se pasa por delante.
    func openStylist() {
        sheet = .stylist
    }

    func close() {
        sheet = nil
    }
}
