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
    #Unique<Garment>([\.id])

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
    public var wearCount: Int = 0
    public var lastWornAt: Date?
    public var isFavorite: Bool = false

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

    @Relationship(deleteRule: .cascade, inverse: \CanvasItem.garment)
    public var canvasItems: [CanvasItem] = []

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
