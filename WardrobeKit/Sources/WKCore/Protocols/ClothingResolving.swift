import Foundation

/// Quien puede mirar un recorte y decir qué es, cuando el dispositivo no llega.
///
/// ## Qué sale del iPhone y qué no
///
/// **La foto original no sale nunca.** Lo único que se envía es el recorte ya
/// normalizado: la prenda sobre fondo transparente, sin cara, sin habitación,
/// sin el resto de la gente que hubiera en la foto. Eso no es una política que
/// se aplique más arriba y se pueda olvidar: es lo único que este contrato
/// sabe transportar — `RemoteGarmentQuery` no tiene un campo para la original.
///
/// **La clave de OpenRouter no vive en la app.** La app habla con una Function
/// de Appwrite; la Function, que corre en el servidor, es la única que conoce
/// la clave. Un `.ipa` es un fichero zip que cualquiera puede abrir: una clave
/// embarcada es una clave publicada.
public protocol ClothingResolving: Sendable {
    func resolve(_ query: RemoteGarmentQuery) async throws -> RemoteGarmentAnswer

    /// Devuelve la prenda como foto de catálogo: plana, de frente, sobre
    /// blanco.
    ///
    /// ## Qué es y qué no es
    ///
    /// **Esto reconstruye, no recorta.** El recorte quita el fondo; esto
    /// redibuja la prenda quitándole la percha, la mano que la sujeta y las
    /// arrugas de estar colgada. Es la diferencia entre la foto que hiciste y
    /// la foto que haría una tienda.
    ///
    /// Y por eso **no sustituye al recorte**: el recorte es la verdad —esos
    /// píxeles estuvieron delante de la cámara— y esto es una interpretación,
    /// por buena que salga. Se guardan los dos y el usuario puede comparar.
    ///
    /// Cuesta dinero y unos segundos por prenda, así que no se llama sola:
    /// se llama cuando alguien la pide.
    ///
    /// - Parameter imageJPEG: el recorte ya normalizado.
    /// - Returns: la imagen generada, en los bytes que devuelva el modelo.
    func restyle(_ imageJPEG: Data) async throws -> Data
}

/// Lo que se manda a resolver.
public struct RemoteGarmentQuery: Sendable, Codable {
    /// El recorte **ya normalizado**, JPEG sobre fondo blanco.
    ///
    /// A 512 y no a 1024: el modelo no ve más por el doble de píxeles, y son
    /// ~40 KB contra ~150 KB por prenda. JPEG y no PNG porque la transparencia
    /// no se transporta y el alfa ya hizo su trabajo al recortar.
    public let imageJPEG: Data

    /// Lo que el dispositivo ya cree saber.
    ///
    /// Se manda **a propósito**: sin contexto, el modelo remoto contesta de
    /// cero y contradice al segmentador en cosas que el segmentador sabe mejor.
    /// Con contexto, su trabajo es el que de verdad no sabemos hacer aquí —
    /// afinar la subcategoría y confirmar o tirar una marca.
    public let kind: String?
    public let subcategory: String?
    public let dominantColor: String?
    /// Marcas que el OCR cree haber leído, para confirmar o descartar. Vacío
    /// cuando no se leyó nada — y entonces el modelo **no debe inventar una**.
    public let brandCandidates: [String]

    public init(
        imageJPEG: Data,
        kind: String?,
        subcategory: String?,
        dominantColor: String?,
        brandCandidates: [String]
    ) {
        self.imageJPEG = imageJPEG
        self.kind = kind
        self.subcategory = subcategory
        self.dominantColor = dominantColor
        self.brandCandidates = brandCandidates
    }
}

/// Lo que contesta.
///
/// Todo opcional, y `nil` es una respuesta válida y preferible a una inventada.
public struct RemoteGarmentAnswer: Sendable, Codable {
    public let kind: String?
    public let subcategory: String?
    /// El color **con su matiz**, nombrado por quien mira la prenda.
    ///
    /// El del dispositivo sale de un k-means sobre los píxeles y promedia: un
    /// azul marino cae del lado del negro y un verde oliva del lado del gris.
    /// Es el error que más se nota, porque el color va dentro del nombre.
    public let colorName: String?
    public let material: String?
    public let pattern: String?
    /// **Solo si se ve escrita o el logotipo es inequívoco.** `nil` es la
    /// respuesta correcta para una prenda lisa, y es la que se espera casi
    /// siempre.
    public let brand: String?
    /// 0-1, lo seguro que está de la marca. Entra en el recuento de evidencias
    /// como una más, no como la última palabra.
    public let brandConfidence: Double?
    public let confidence: Double?
    /// **Qué se ve**, no cómo lo razonó.
    ///
    /// "cuello con botones", "suela de goma blanca", "etiqueta bordada en el
    /// pecho": cosas comprobables mirando la misma imagen. No se pide ni se
    /// acepta cadena de razonamiento — no es verificable, ocupa tokens y da
    /// una sensación de rigor que no corresponde a nada.
    public let reasoningSignals: [String]?

    public init(
        kind: String? = nil,
        subcategory: String? = nil,
        colorName: String? = nil,
        material: String? = nil,
        pattern: String? = nil,
        brand: String? = nil,
        brandConfidence: Double? = nil,
        confidence: Double? = nil,
        reasoningSignals: [String]? = nil
    ) {
        self.kind = kind
        self.subcategory = subcategory
        self.colorName = colorName
        self.material = material
        self.pattern = pattern
        self.brand = brand
        self.brandConfidence = brandConfidence
        self.confidence = confidence
        self.reasoningSignals = reasoningSignals
    }
}

public enum ClothingResolverError: Error, Sendable {
    case notConfigured
    case transport(String)
    case badResponse(String)
    case rateLimited
}
