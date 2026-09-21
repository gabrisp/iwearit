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
        synced + localOnly
    }

    /// Lo que es del usuario y tiene que estar en todos sus dispositivos.
    ///
    /// Incluye `GarmentImageBlob`: sin los bytes, el otro dispositivo recibe un
    /// armario de claves que no resuelven.
    public static var synced: [any PersistentModel.Type] {
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
            GarmentImageBlob.self,
        ]
    }

    /// Lo que **no tiene sentido fuera de este dispositivo**.
    ///
    /// - `DownloadedModel` guarda una ruta relativa a un contenedor que cambia
    ///   por instalación: sincronizarlo haría que el iPad creyera tener un
    ///   modelo de Core ML que no ha descargado.
    /// - `ScanSession` guarda un cursor de `PHAsset`, que identifica una foto
    ///   **de esta galería**. En otro dispositivo no señala nada.
    public static var localOnly: [any PersistentModel.Type] {
        [
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

    /// El contenedor de CloudKit. Tiene que existir en la cuenta de
    /// desarrollador y estar declarado en los entitlements del target.
    public static let cloudContainerIdentifier = "iCloud.com.gabrisp.iWearIt"

    /// Dónde está el store que ya tiene el usuario.
    ///
    /// **Explícito y no el de por defecto**, y es lo que hace que esto no sea
    /// una migración peligrosa: al pasar de una configuración a dos, la
    /// sincronizada se queda **en el mismo fichero de siempre**. El armario no
    /// se mueve, no se copia y no se recrea; lo único que cambia es que ahora
    /// hay un segundo store al lado para lo que no debe viajar.
    ///
    /// Comprobado con un test: abrir ese fichero declarando menos entidades de
    /// las que contiene conserva todo lo demás.
    static var syncedStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    /// Y el de lo que es de este dispositivo. Fichero nuevo: aquí no había
    /// nada que conservar.
    static var localStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "local.store")
    }

    /// Construye el contenedor.
    ///
    /// - Parameters:
    ///   - inMemory: para tests y previews. Cada llamada crea un store aislado,
    ///     así que los tests no se pisan entre sí.
    ///   - syncsWithCloud: si el store del armario se replica en iCloud. Al
    ///     apagarlo, la app funciona exactamente igual contra el mismo fichero
    ///     local — que es lo que permite encender y apagar la sincronización
    ///     sin tocar los datos.
    public static func makeContainer(
        inMemory: Bool = false,
        syncsWithCloud: Bool = false
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WardrobeSchemaV1.self)

        guard !inMemory else {
            return try ModelContainer(
                for: schema,
                migrationPlan: WardrobeMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }

        let synced = ModelConfiguration(
            "wardrobe",
            schema: Schema(WardrobeSchemaV1.synced),
            url: syncedStoreURL,
            cloudKitDatabase: syncsWithCloud
                ? .private(cloudContainerIdentifier)
                : .none
        )
        let local = ModelConfiguration(
            "local",
            schema: Schema(WardrobeSchemaV1.localOnly),
            url: localStoreURL,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: WardrobeMigrationPlan.self,
            configurations: synced, local
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
