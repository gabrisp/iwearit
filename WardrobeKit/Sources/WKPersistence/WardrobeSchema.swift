import Foundation
import SwiftData
import WKCore

/// Versión 1 del esquema.
///
/// La maquinaria de migración existe **desde el día uno** aunque solo haya una
/// versión: cuando llegue V2, añadirla es mecánico. Descubrir que hace falta
/// migración cuando ya tienes usuarios con datos es lo que obliga a borrarles
/// el armario.
public enum WardrobeSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Garment.self,
            GarmentCategory.self,
            GarmentStack.self,
            Outfit.self,
            CanvasItem.self,
            PlannedDay.self,
            Suitcase.self,
            PackingEntry.self,
            BodyProfile.self,
            DownloadedModel.self,
            ScanSession.self,
        ]
    }
}

/// Plan de migración.
///
/// **Una sola versión.** Lo intuitivo al añadir campos es declarar una V2 y una
/// V3, pero un `VersionedSchema` se identifica por el *checksum de sus modelos*
/// y las tres reutilizaban las mismas clases: mismo checksum, tres versiones,
/// y SwiftData aborta al abrir el contenedor con "Duplicate version checksums
/// detected".
///
/// Una versión nueva de verdad exige **copiar los `@Model`** dentro de su
/// propio `enum` y que difieran. Mientras los cambios sean campos opcionales o
/// con valor por defecto —que es todo lo que ha habido: los stickers y el
/// volteo— SwiftData los añade solo, sin etapa ninguna. La maquinaria se queda
/// aquí para el día en que un cambio sí necesite transformar datos, que es
/// cuando hay que pagar el coste de duplicar los modelos.
public enum WardrobeMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [WardrobeSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public enum WardrobeStore {

    /// Construye el contenedor.
    ///
    /// - Parameter inMemory: para tests y previews. Cada llamada crea un store
    ///   aislado, así que los tests no se pisan entre sí.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: Schema(versionedSchema: WardrobeSchemaV1.self),
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(
            for: Schema(versionedSchema: WardrobeSchemaV1.self),
            migrationPlan: WardrobeMigrationPlan.self,
            configurations: configuration
        )
    }
}

// MARK: - Categorías semilla

public extension GarmentCategory {

    /// Las ocho baldas que existen desde la primera ejecución.
    ///
    /// No se pueden borrar porque son el destino de respaldo cuando ninguna
    /// categoría propia del usuario supera el umbral de similitud. Sí se
    /// renombran, reordenan y ocultan.
    static func seedDefinitions() -> [(slug: String, name: String, symbol: String, kind: GarmentKind)] {
        [
            ("outerwear",  "Chaquetas",     "jacket",            .outerLayer),
            ("whole-body", "Cuerpo entero", "figure.dress.line.vertical.figure", .wholeBody),
            ("tops",       "Tops",          "tshirt",            .upperBody),
            ("bottoms",    "Bottoms",       "rectangle.portrait", .lowerBody),
            ("shoes",      "Zapatos",       "shoe",              .feet),
            ("accessories","Accesorios",    "eyeglasses",        .head),
            ("bags",       "Bolsos",        "bag",               .bag),
            ("other",      "Otros",         "square.grid.2x2",   .other),
        ]
    }
}
