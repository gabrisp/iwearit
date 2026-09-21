import Foundation
import SwiftData
import WKCore

/// Una balda del armario. **Aquí manda el usuario**, al contrario que en
/// `GarmentKind`.
///
/// Puede ser una de las ocho semilla o una inventada por el usuario ("Gorras").
/// Las inventadas se auto-rellenan por similitud de embeddings: ver
/// `promptEmbedding` y `centroidEmbedding`.
@Model
public final class GarmentCategory {
    // Sin `#Unique`: CloudKit no lo soporta. El `slug` sigue siendo la
    // identidad lógica de la balda, pero garantizarla pasa a ser trabajo de la
    // app —fusionar dos baldas con el mismo slug, nunca borrar una que tenga
    // prendas dentro—.

    public var id: UUID = UUID()
    /// Identidad estable, independiente del nombre visible. Las semilla usan
    /// `GarmentKind.seedCategorySlug`; las del usuario, un UUID.
    public var slug: String = ""
    public var name: String = ""
    /// Las ocho semilla no se pueden borrar — son el destino de respaldo
    /// cuando ninguna categoría propia supera el umbral. Sí se renombran,
    /// reordenan y ocultan.
    public var isBuiltIn: Bool = false
    public var isHidden: Bool = false
    public var sortOrder: Int = 0
    public var modifiedAt: Date = Date()
    public var deletedAt: Date?
    public var symbolName: String?
    /// `GarmentKind` que hereda una prenda asignada a mano a esta balda.
    public var defaultKindRaw: String?

    // MARK: Clasificación automática

    /// 512 `Float16`. Se copia del prompt bank cuando el nombre casa con un
    /// término conocido ("Gorra"): clasifica **desde la primera prenda**, sin
    /// necesitar ejemplos.
    public var promptEmbedding: Data?

    /// 512 `Float16`. Media normalizada de los miembros, para nombres libres
    /// que no están en el prompt bank ("Gorras de pádel"). Aprende del armario
    /// concreto del usuario, así que acaba siendo más preciso que el zero-shot.
    public var centroidEmbedding: Data?

    /// Cuántos miembros contribuyeron al centroide actual. Permite actualizarlo
    /// de forma incremental en vez de recalcularlo entero en cada alta.
    public var memberCountAtCentroid: Int = 0

    /// Coseno mínimo para asignar. Conservador a propósito: más vale no asignar
    /// que asignar mal, porque un error obliga al usuario a corregir a mano.
    public var minSimilarity: Double = 0.28
    public var autoAssignEnabled: Bool = false

    @Relationship(deleteRule: .nullify, originalName: "garments", inverse: \Garment.category)
    public var storedGarments: [Garment]? = []

    public var garments: [Garment] { storedGarments ?? [] }

    public init(
        slug: String,
        name: String,
        isBuiltIn: Bool = false,
        sortOrder: Int,
        symbolName: String? = nil,
        defaultKind: GarmentKind? = nil
    ) {
        self.id = UUID()
        self.slug = slug
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
        self.symbolName = symbolName
        self.defaultKindRaw = defaultKind?.rawValue
    }

    public var defaultKind: GarmentKind? {
        get { defaultKindRaw.flatMap(GarmentKind.init(rawValue:)) }
        set { defaultKindRaw = newValue?.rawValue }
    }

    /// Mínimo de ejemplos antes de fiarse del centroide. Con tres es ruidoso.
    public static let minimumExamplesForCentroid = 4
}

/// Un grupo de prendas que el pipeline cree que son la misma.
@Model
public final class GarmentStack {
    public var id: UUID = UUID()
    public var representativeGarmentID: UUID = UUID()
    public var centroidEmbedding: Data?
    /// `true` cuando el usuario ya decidió sobre este grupo (fusionar/descartar).
    public var isResolved: Bool = false

    @Relationship(deleteRule: .nullify, originalName: "members", inverse: \Garment.stack)
    public var storedMembers: [Garment]? = []

    public var members: [Garment] { storedMembers ?? [] }

    public init(representativeGarmentID: UUID, centroidEmbedding: Data? = nil) {
        self.id = UUID()
        self.representativeGarmentID = representativeGarmentID
        self.centroidEmbedding = centroidEmbedding
    }
}
