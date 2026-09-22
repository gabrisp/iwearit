import Foundation
import SwiftData
import WKCore

/// Una prenda del armario.
///
/// Los tipos `@Model` viven en `WKPersistence` y no en `WKCore` a propósito:
/// así `WKCore` no importa ningún framework y sus tipos (`GarmentDraft`,
/// `GarmentKind`) pueden cruzar actores sin arrastrar SwiftData detrás.
@Model
public final class Garment {
    // **Sin `#Unique`.** CloudKit no soporta restricciones de unicidad, y con
    // sincronización el `id` deja de poder garantizarse en la base: dos
    // dispositivos pueden crear el mismo objeto lógico sin saberlo. La
    // unicidad pasa a ser cosa de la app —y conservadora: ante la duda, dos
    // prendas parecidas se quedan las dos. Ver `DuplicateDetector`.

    public var id: UUID = UUID()
    public var name: String = ""

    /// `GarmentKind` serializado. **Lo decide la IA y el usuario no lo edita.**
    /// Es lo que usa el combinador de outfits; si fuera editable, "un outfit
    /// necesita torso + piernas" se rompería en cuanto alguien inventara una
    /// categoría "Verano".
    public var kindRaw: String = GarmentKind.other.rawValue

    public var subcategory: String?
    public var colors: [NamedColor] = []
    public var brand: String?
    public var size: String?
    public var material: String?
    /// El corte: la manga en lo de arriba, el largo en lo de abajo. Opcional
    /// y con nombre libre —se puede escribir uno propio—; ver
    /// `GarmentVocabulary.cuts(for:)`.
    public var cut: String?
    public var seasonsRaw: Int = SeasonSet.all.rawValue
    public var tags: [String] = []
    public var notes: String?

    // MARK: Imágenes — solo claves. Los bytes viven en disco (`ImageStore`).

    public var normalizedImageKey: String = ""
    public var rawCropImageKey: String?
    /// `PHAsset.localIdentifier` de la foto de origen, para "ver foto original".
    /// Ocupa 0 bytes, pero deja de resolver si el usuario borra la foto.
    public var sourcePhotoLocalIdentifier: String?

    /// 512 `Float16` de MobileCLIP. `nil` en modo degradado.
    public var embedding: Data?

    public var dateAdded: Date = Date()
    /// Cuándo se tocó por última vez. Ver `SoftDeletable`.
    public var modifiedAt: Date = Date()
    /// Cuándo se marcó para eliminar. `nil` = viva. Ver `SoftDeletable`.
    public var deletedAt: Date?
    public var wearCount: Int = 0
    public var lastWornAt: Date?
    public var isFavorite: Bool = false
    /// Dónde va dentro de su balda, si el usuario la ha colocado.
    ///
    /// `Double` y no `Int` a propósito: arrastrar una prenda entre otras dos
    /// es ponerle el punto medio de sus vecinas, y con enteros habría que
    /// renumerar la balda entera en cada arrastre —que es la forma clásica de
    /// perder el orden a la tercera.
    ///
    /// Cero para todo lo que nadie ha tocado, y entonces manda la fecha: una
    /// balda recién llenada sale como siempre, con lo último delante.
    public var shelfOrder: Double = 0

    /// `true` si la categoría viene del modo degradado o de una clasificación dudosa.
    public var needsReview: Bool = false
    /// 0-1. Ordena la pantalla de revisión: lo dudoso primero.
    public var confidence: Double = 1

    /// Si el usuario movió esta prenda de balda a mano, la auto-clasificación
    /// **no vuelve a tocarla**. Arrastrar una gorra a "Sombreros" y que el
    /// modelo te la devuelva al día siguiente es una forma rápida de perder la
    /// confianza del usuario.
    public var categoryLockedByUser: Bool = false

    public var category: GarmentCategory?
    public var stack: GarmentStack?

    // **Guardado como opcional, leído como lista.**
    //
    // CloudKit exige que toda relación sea opcional: un `[CanvasItem]` a secas
    // hace que el store no cargue con réplica —comprobado ejecutándolo—. El
    // `originalName` conserva la columna que ya existe, así que esto no migra
    // nada; y el accesorio de abajo deja el resto del código exactamente igual
    // que estaba.
    @Relationship(deleteRule: .cascade, originalName: "canvasItems", inverse: \CanvasItem.garment)
    public var storedCanvasItems: [CanvasItem]? = []

    public var canvasItems: [CanvasItem] { storedCanvasItems ?? [] }

    /// Las entradas de equipaje que la nombran.
    ///
    /// Existe para darle **inverso** a `PackingEntry.garment`: sin él, CloudKit
    /// rechaza el modelo entero. Nadie la lee; la relación se sigue usando
    /// desde el otro lado.
    @Relationship(deleteRule: .cascade, inverse: \PackingEntry.garment)
    public var storedPackingEntries: [PackingEntry]? = []

    public init(
        id: UUID = UUID(),
        name: String,
        kind: GarmentKind,
        normalizedImageKey: String,
        confidence: Double = 1
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.normalizedImageKey = normalizedImageKey
        self.confidence = confidence
        self.needsReview = confidence < GarmentDraft.reviewConfidenceThreshold
        self.dateAdded = Date()
    }

    public var kind: GarmentKind {
        get { GarmentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    public var seasons: SeasonSet {
        get { SeasonSet(rawValue: seasonsRaw) }
        set { seasonsRaw = newValue.rawValue }
    }

    public var dominantColor: NamedColor? {
        colors.max { $0.weight < $1.weight }
    }
}
