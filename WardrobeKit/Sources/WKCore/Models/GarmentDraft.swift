import Foundation

/// Lo que el pipeline de visión produce por prenda detectada, antes de que
/// exista en la base de datos.
///
/// Es un `struct` `Sendable` **a propósito**: los tipos `@Model` de SwiftData no
/// son `Sendable`, así que no pueden cruzar actores. El pipeline corre fuera del
/// hilo principal, acumula estos borradores y los entrega en lotes al
/// `WardrobeActor`, que es quien los convierte en `Garment`.
public struct GarmentDraft: Sendable, Hashable {
    public var kind: GarmentKind
    public var subcategory: String?
    public var material: String?
    public var cut: String?
    public var colors: [NamedColor]
    public var seasons: SeasonSet
    public var tags: [String]
    /// sha256 de la imagen normalizada, ya escrita en disco por el `ImageStore`.
    public var normalizedImageKey: String
    public var rawCropImageKey: String?
    public var sourcePhotoLocalIdentifier: String?
    /// 512 valores `Float16` de MobileCLIP. `nil` en modo degradado.
    public var embedding: Data?
    /// 0-1. Por debajo de ~0.5 la prenda va marcada para revisar.
    public var confidence: Double
    /// Nombre propuesto. Si es `nil`, se compone con color + subcategoría.
    public var proposedName: String?
    /// Marca leída de la propia prenda.
    ///
    /// El plan decía que la marca era siempre manual, y era razonable mientras
    /// la única forma de saberla fuera adivinarla. Leerla del texto de la
    /// prenda no es adivinar: o pone "adidas" o no pone nada. Se escribe solo
    /// cuando la ficha no tiene marca, así que nunca pisa lo que el usuario
    /// haya puesto.
    public var brand: String?

    public init(
        kind: GarmentKind,
        subcategory: String? = nil,
        material: String? = nil,
        cut: String? = nil,
        colors: [NamedColor] = [],
        seasons: SeasonSet = .all,
        tags: [String] = [],
        normalizedImageKey: String,
        rawCropImageKey: String? = nil,
        sourcePhotoLocalIdentifier: String? = nil,
        embedding: Data? = nil,
        confidence: Double,
        proposedName: String? = nil,
        brand: String? = nil
    ) {
        self.kind = kind
        self.subcategory = subcategory
        self.material = material
        self.cut = cut
        self.colors = colors
        self.seasons = seasons
        self.tags = tags
        self.normalizedImageKey = normalizedImageKey
        self.rawCropImageKey = rawCropImageKey
        self.sourcePhotoLocalIdentifier = sourcePhotoLocalIdentifier
        self.embedding = embedding
        self.confidence = confidence
        self.proposedName = proposedName
        self.brand = brand
    }

    /// Umbral por debajo del cual la prenda entra en la pantalla de revisión.
    public static let reviewConfidenceThreshold = 0.5
    public var needsReview: Bool { confidence < Self.reviewConfidenceThreshold }
}
