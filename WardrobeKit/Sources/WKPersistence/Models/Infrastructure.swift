import Foundation
import SwiftData
import WKCore

/// Una cara o cuerpo subido por el usuario para el try-on. Máximo 3.
@Model
public final class BodyProfile {
    public var id: UUID = UUID()
    public var label: String = ""
    public var imageKey: String = ""
    public var createdAt: Date = Date()

    /// Sin esta fecha, **la imagen no sale del dispositivo**. El try-on corre en
    /// servidor, y una foto de cuerpo es dato personal de categoría sensible:
    /// el consentimiento es explícito, separado y revocable.
    public var consentAcceptedAt: Date?

    /// Lo que se ha probado con este perfil. La vuelta de `TryOnResult.profile`,
    /// que CloudKit exige. Sin borrado en cascada: quitar un perfil no tiene por
    /// qué llevarse las fotos de lo que te probaste.
    @Relationship(deleteRule: .nullify) public var tryOns: [TryOnResult]? = []

    // MARK: Quién es
    //
    // **Un perfil no es una foto: es una descripción.** Una foto tuya de
    // cuerpo entero con buena luz no la tiene casi nadie a mano, y pedirla
    // antes de poder probar nada es cerrar la puerta en el primer paso. Con
    // cuatro datos —estatura, complexión, cómo vistes— ya se puede dibujar a
    // alguien con tu forma llevando tu ropa, que es para lo que se usa esto:
    // ver cómo cae, no verte la cara.
    //
    // La foto sigue existiendo y es la versión buena cuando la hay. Los dos
    // caminos conviven porque resuelven dos momentos distintos.

    /// Estatura en centímetros. Es el dato que más cambia cómo cae la ropa.
    public var heightCentimetres: Int?
    /// Complexión. Ver `BodyProfile.Shape`.
    public var shapeRaw: String?
    /// Cómo se viste, que decide el corte y no el cuerpo. Ver `Presentation`.
    public var presentationRaw: String?
    /// Tono de piel, para que la persona dibujada se parezca a quien mira.
    public var skinToneRaw: String?
    /// Lo que no cabe en una lista: "llevo gafas", "barba", "pelo largo".
    public var notes: String?

    public init(
        label: String,
        imageKey: String = "",
        heightCentimetres: Int? = nil,
        shape: Shape? = nil,
        presentation: Presentation? = nil,
        skinTone: SkinTone? = nil,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.label = label
        self.imageKey = imageKey
        self.createdAt = Date()
        self.heightCentimetres = heightCentimetres
        self.shapeRaw = shape?.rawValue
        self.presentationRaw = presentation?.rawValue
        self.skinToneRaw = skinTone?.rawValue
        self.notes = notes
    }

    public static let maximumProfiles = 3
    /// Solo hay foto que mandar si hay foto **y** permiso.
    public var canLeaveDevice: Bool { consentAcceptedAt != nil }
    public var hasPhoto: Bool { !imageKey.isEmpty }

    public var shape: Shape? { shapeRaw.flatMap(Shape.init) }
    public var presentation: Presentation? { presentationRaw.flatMap(Presentation.init) }
    public var skinTone: SkinTone? { skinToneRaw.flatMap(SkinTone.init) }

    public enum Shape: String, Sendable, CaseIterable, Codable {
        case slim, athletic, average, curvy, large

        public var label: String {
            switch self {
            case .slim: "Delgada"
            case .athletic: "Atlética"
            case .average: "Media"
            case .curvy: "Con curvas"
            case .large: "Corpulenta"
            }
        }

        /// Cómo se le cuenta al modelo, que no entiende de etiquetas.
        public var described: String {
            switch self {
            case .slim: "complexión delgada"
            case .athletic: "complexión atlética, hombros marcados"
            case .average: "complexión media"
            case .curvy: "cuerpo con curvas, cintura marcada"
            case .large: "complexión corpulenta"
            }
        }
    }

    public enum Presentation: String, Sendable, CaseIterable, Codable {
        case woman, man, neutral

        public var label: String {
            switch self {
            case .woman: "Mujer"
            case .man: "Hombre"
            case .neutral: "Neutro"
            }
        }

        public var described: String {
            switch self {
            case .woman: "una mujer"
            case .man: "un hombre"
            case .neutral: "una persona de aspecto andrógino"
            }
        }
    }

    public enum SkinTone: String, Sendable, CaseIterable, Codable {
        case light, medium, tan, dark

        public var label: String {
            switch self {
            case .light: "Clara"
            case .medium: "Media"
            case .tan: "Morena"
            case .dark: "Oscura"
            }
        }

        public var described: String {
            switch self {
            case .light: "piel clara"
            case .medium: "piel de tono medio"
            case .tan: "piel morena"
            case .dark: "piel oscura"
            }
        }
    }

    /// El perfil en una frase, que es lo que viaja cuando no hay foto.
    ///
    /// Se arma aquí y no en la vista para que lo que se manda sea exactamente
    /// lo que se ve escrito en la ficha: sin adornos y sin nada que el usuario
    /// no haya puesto.
    public var described: String {
        var parts: [String] = [presentation?.described ?? "una persona"]
        if let heightCentimetres { parts.append("de \(heightCentimetres) cm") }
        if let shape { parts.append(shape.described) }
        if let skinTone { parts.append(skinTone.described) }
        if let notes, !notes.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(notes) }
        return parts.joined(separator: ", ")
    }
}

/// Un modelo de Core ML ya descargado, verificado y compilado.
@Model
public final class DownloadedModel {
    #Unique<DownloadedModel>([\.modelID])

    public var modelID: String = ""
    public var version: Int = 0
    public var sha256: String = ""
    /// Relativo a Application Support, no absoluto: la ruta del contenedor
    /// cambia entre instalaciones y un absoluto deja de resolver.
    public var compiledPath: String = ""
    public var sizeBytes: Int = 0
    public var downloadedAt: Date = Date()
    public var lastValidatedAt: Date?

    public init(modelID: String, version: Int, sha256: String, compiledPath: String, sizeBytes: Int) {
        self.modelID = modelID
        self.version = version
        self.sha256 = sha256
        self.compiledPath = compiledPath
        self.sizeBytes = sizeBytes
        self.downloadedAt = Date()
    }
}

/// Una sesión de escaneo de galería, reanudable.
///
/// iOS no da CPU sostenida en segundo plano para visión, así que el escaneo se
/// pausa al salir de la app. Esto es lo que permite volver y continuar donde se
/// quedó en vez de empezar de cero.
@Model
public final class ScanSession {
    public var id: UUID = UUID()
    public var startedAt: Date = Date()
    /// Último `PHAsset.localIdentifier` procesado.
    public var cursorAssetID: String?
    public var cursorIndex: Int = 0
    public var totalAssets: Int = 0
    public var photosProcessed: Int = 0
    public var garmentsFound: Int = 0
    public var outfitsFound: Int = 0
    public var stateRaw: String = State.running.rawValue

    public enum State: String, Sendable {
        case running, paused, finished, skipped
    }

    public init(totalAssets: Int) {
        self.id = UUID()
        self.startedAt = Date()
        self.totalAssets = totalAssets
    }

    public var state: State {
        get { State(rawValue: stateRaw) ?? .paused }
        set { stateRaw = newValue.rawValue }
    }

    public var fractionComplete: Double {
        totalAssets > 0 ? Double(photosProcessed) / Double(totalAssets) : 0
    }
}

/// Un probado que ya se hizo.
///
/// ## Por qué se guarda
///
/// Porque cuesta dinero y cuesta tiempo. Generar cómo te queda un conjunto son
/// unos segundos de espera y una moneda del bote, y hasta ahora el resultado
/// vivía en memoria: cerrabas la hoja y se iba. Volver a verlo significaba
/// volver a pagarlo, y comparar dos conjuntos probados era imposible.
///
/// Guarda **la clave** de la imagen, no los bytes: van al disco como cualquier
/// otra foto de la app. Ver `ImageStore`.
@Model
public final class TryOnResult {
    public var id: UUID = UUID()
    /// La imagen generada, en el almacén de imágenes.
    public var imageKey: String = ""
    /// Dónde se puso. Ver `TryOnScene` en la app.
    public var sceneRaw: String?
    public var createdAt: Date = Date()

    /// De qué conjunto es. Opcional y con `nullify`: borrar un outfit no tiene
    /// por qué llevarse por delante la foto de cómo te quedaba.
    @Relationship(inverse: \Outfit.tryOns) public var outfit: Outfit?
    /// Y con qué perfil se hizo, para saber quién es el de la foto.
    ///
    /// **Con su inversa en `BodyProfile.tryOns`.** Sin ella CloudKit no abre
    /// el almacén —exige que toda relación tenga vuelta—, la app caía a local
    /// y en cada arranque volvía a ofrecer encender iCloud.
    @Relationship(inverse: \BodyProfile.tryOns) public var profile: BodyProfile?

    public init(
        imageKey: String,
        sceneRaw: String? = nil,
        outfit: Outfit? = nil,
        profile: BodyProfile? = nil
    ) {
        self.id = UUID()
        self.imageKey = imageKey
        self.sceneRaw = sceneRaw
        self.createdAt = Date()
        self.outfit = outfit
        self.profile = profile
    }
}

/// Una prenda **encontrada y todavía no aceptada**.
///
/// ## Por qué existe
///
/// El escaneo de la galería encuentra lo que encuentra, y decidir qué entra al
/// armario es del usuario. Hasta ahora lo encontrado vivía en memoria mientras
/// se decidía: si saltabas el paso, cerrabas la app o se quedaba colgada, se
/// perdía todo y había que volver a escanear. Aquí queda guardado hasta que
/// alguien dice sí —y entra al armario— o no —y se descarta—; y se puede
/// decidir en el momento o días después, desde el armario.
///
/// **Solo en este dispositivo.** Es trabajo a medio hacer sobre la galería de
/// este iPhone: sincronizarlo llenaría el iPad de propuestas de fotos que no
/// tiene. Ver `WardrobeSchemaV1.localOnly`.
///
/// Guarda el borrador entero codificado en vez de un campo por propiedad: es
/// un estado de paso, nadie lo consulta por partes, y así un campo nuevo en
/// `GarmentDraft` no obliga a tocar este modelo.
@Model
public final class PendingGarment {
    public var id: UUID = UUID()
    /// La clave del recorte, ya escrito en disco. Es también lo que lo hace
    /// único: el mismo recorte dos veces es el mismo pendiente.
    public var imageKey: String = ""
    public var kindRaw: String = ""
    public var draftData: Data = Data()
    /// Cuándo lo encontró el escaneo.
    public var foundAt: Date = Date()
    /// Cuándo se hizo la foto de la que sale, para ordenar lo reciente primero.
    public var photoDate: Date?
    /// De qué foto sale, para no volver a mirarla en el siguiente escaneo.
    public var sourcePhotoID: String?

    public init(draft: GarmentDraft, photoDate: Date?) {
        self.id = UUID()
        self.imageKey = draft.normalizedImageKey
        self.kindRaw = draft.kind.rawValue
        self.draftData = (try? JSONEncoder().encode(draft)) ?? Data()
        self.foundAt = Date()
        self.photoDate = photoDate
        self.sourcePhotoID = draft.sourcePhotoLocalIdentifier
    }

    /// El borrador, tal como salió del escaneo.
    public var draft: GarmentDraft? {
        try? JSONDecoder().decode(GarmentDraft.self, from: draftData)
    }

    public var kind: GarmentKind { GarmentKind(rawValue: kindRaw) ?? .other }
}
