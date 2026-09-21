import CoreGraphics
import Foundation
import WKCore

/// Caja para cruzar imágenes entre actores.
///
/// `CGImage` es inmutable y seguro de leer desde varios hilos; CoreGraphics
/// simplemente nunca lo declaró `Sendable`. Envolverlo con la justificación a
/// la vista es preferible a esparcir `@unchecked` por todo el pipeline.
public struct ImmutableImage: @unchecked Sendable {
    public let cgImage: CGImage
    public init(_ cgImage: CGImage) { self.cgImage = cgImage }

    public var width: Int { cgImage.width }
    public var height: Int { cgImage.height }
}

/// Una prenda recortada de una foto, lista para guardarse.
public struct DetectedGarment: Sendable {
    public let kind: GarmentKind
    /// 0-1. En modo degradado no pasa de 0,35: la categoría sale de dónde cae
    /// la prenda respecto al esqueleto, no de reconocerla.
    public let confidence: Double
    /// Recortada, sin fondo, centrada y a escala coherente.
    public let normalized: ImmutableImage
    /// El recorte tal cual salió de la máscara, por si hace falta reprocesar.
    public let rawCrop: ImmutableImage
    public let colors: [NamedColor]
    /// Embedding para deduplicar y para las baldas propias.
    ///
    /// Viene de TinyCLIP si el modelo está, y de `VNGenerateImageFeaturePrint`
    /// si no. **No son comparables entre sí**: viven en espacios vectoriales
    /// distintos, así que un centroide aprendido con uno no sirve para el otro.
    public let featurePrint: Data?
    /// "cazadora", "vaqueros". Del prompt bank.
    public let subcategory: String?
    public let material: String?
    public let tags: [String]
    public let seasons: SeasonSet
    /// Leída de la propia prenda. `nil` cuando no se reconoce ninguna, que es
    /// lo normal en una prenda lisa.
    public let brand: String?
    /// **Por qué** se cree que es de esa marca.
    ///
    /// Se guarda además del nombre, y no en su lugar: es lo que permite volver
    /// a votar cuando llega una evidencia nueva —la del resolutor remoto, o la
    /// del propio usuario— sin haber perdido por el camino de dónde salía la
    /// primera.
    public let brandEvidence: [BrandEvidence]
    /// Cuál de las prendas de su misma clase es, de arriba abajo.
    ///
    /// Casi siempre 0, porque casi siempre hay una sola camiseta en la foto.
    /// Deja de serlo cuando el separador de instancias encuentra dos prendas
    /// que SegFormer había etiquetado igual —dos camisetas dobladas sobre la
    /// cama— y sirve para distinguirlas en la pantalla de revisión, donde si no
    /// aparecerían dos filas idénticas sin saber cuál es cuál.
    public let instanceIndex: Int
    /// Dónde estaba la prenda dentro de la foto de origen, normalizado 0-1 con
    /// el origen arriba-izquierda.
    ///
    /// Solo sirve para la animación de recorte: permite que la prenda salga
    /// exactamente del sitio de la foto en el que estaba en vez de aparecer de
    /// la nada. `nil` cuando no se pudo situar, y entonces sale del centro.
    public let sourceRect: CGRect?

    public init(
        kind: GarmentKind,
        confidence: Double,
        normalized: ImmutableImage,
        rawCrop: ImmutableImage,
        colors: [NamedColor],
        featurePrint: Data?,
        subcategory: String? = nil,
        material: String? = nil,
        tags: [String] = [],
        seasons: SeasonSet = .all,
        brand: String? = nil,
        brandEvidence: [BrandEvidence] = [],
        instanceIndex: Int = 0,
        sourceRect: CGRect? = nil
    ) {
        self.kind = kind
        self.confidence = confidence
        self.normalized = normalized
        self.rawCrop = rawCrop
        self.colors = colors
        self.featurePrint = featurePrint
        self.brand = brand
        self.brandEvidence = brandEvidence
        self.instanceIndex = instanceIndex
        self.sourceRect = sourceRect
        self.subcategory = subcategory
        self.material = material
        self.tags = tags
        self.seasons = seasons
    }
}

public enum PipelineError: Error, Sendable {
    case noSubjectFound
    case noPersonFound
    case maskGenerationFailed
    case renderFailed
    /// Vision no puede ejecutar sus modelos en este entorno.
    ///
    /// Pasa **siempre en el simulador de iOS**: las peticiones neuronales
    /// (pose, máscara de sujeto, feature print, estética) necesitan un
    /// dispositivo de cómputo real y fallan con "No available compute device"
    /// o "Failed to create espresso context". Medido, no supuesto.
    ///
    /// En un iPhone real no ocurre, pero merece su propio caso para que la UI
    /// diga algo útil en vez de enseñar el error de CoreML en crudo.
    case visionUnavailable
    /// Una etapa de Vision se quedó esperando. Pasa con la ANE ocupada o con
    /// un modelo a medio instalar, y sin tope la pantalla se queda colgada sin
    /// decir por qué.
    case timedOut
    /// El segmentador todavía no está cargado y lo nativo no respondió.
    ///
    /// Caso propio porque la salida es **esperar**, no cambiar de foto: decir
    /// "prueba con otra foto" cuando lo que pasa es que el modelo sigue
    /// cargando manda al usuario a repetir el mismo fallo con otra imagen.
    case modelNotReady
}

extension PipelineError: LocalizedError {
    /// Sin esto, `localizedDescription` sobre un `enum` de Swift produce
    /// "The operation couldn't be completed. (WKVision.PipelineError error 2.)",
    /// que no le dice nada a nadie — ni al usuario ni a quien depura.
    public var errorDescription: String? {
        switch self {
        case .noPersonFound:
            "No se reconoce a nadie en la foto."
        case .noSubjectFound:
            "No se pudo separar el sujeto del fondo."
        case .maskGenerationFailed:
            "No se pudo generar la máscara de recorte."
        case .renderFailed:
            "No se pudo dibujar el recorte."
        case .timedOut:
            "Está tardando demasiado"
        case .visionUnavailable:
            "El reconocimiento de imágenes no está disponible ahora mismo."
        case .modelNotReady:
            "El modelo todavía se está preparando"
        }
    }

    /// Qué puede hacer el usuario al respecto. Un error sin salida es solo una
    /// mala noticia.
    public var recoverySuggestion: String? {
        switch self {
        case .noPersonFound:
            "Prueba con una foto de cuerpo entero donde se te vea de frente."
        case .timedOut:
            "Vuelve a intentarlo. Si sigue pasando, cierra y abre la app."
        case .noSubjectFound, .maskGenerationFailed:
            "Prueba con una foto de fondo despejado y buena luz."
        case .renderFailed:
            "Prueba con otra foto."
        case .visionUnavailable:
            "El Neural Engine está ocupado —normalmente cargando un modelo o con la cámara abierta—. "
                + "Espera unos segundos y vuelve a intentarlo."
        case .modelNotReady:
            "Espera a que termine de descargarse y cargarse. Lo verás en Ajustes › Modelos."
        }
    }
}

/// Traduce los errores de Vision a algo accionable.
public enum PipelineErrorMapper {
    /// Firmas que delatan que Vision no tiene dónde ejecutar sus modelos.
    private static let unavailableSignatures = [
        "No available compute device",
        "Could not create inference context",
        "Failed to create espresso context",
    ]

    public static func map(_ error: Error) -> PipelineError {
        if let pipelineError = error as? PipelineError { return pipelineError }
        let description = String(describing: error)
        if unavailableSignatures.contains(where: description.contains) {
            return .visionUnavailable
        }
        return .noSubjectFound
    }
}

/// En qué banda del cuerpo cae una región.
///
/// Es la base del **modo degradado**: sin un modelo de segmentación de moda, la
/// única señal fiable de qué tipo de prenda es algo es dónde está respecto al
/// esqueleto. Tosco, pero produce prendas de verdad y funciona sin red.
public enum BodyBand: Sendable, CaseIterable {
    case aboveShoulders
    case torso
    case legs
    case feet

    public var kind: GarmentKind {
        switch self {
        case .aboveShoulders: .head
        case .torso: .upperBody
        case .legs: .lowerBody
        case .feet: .feet
        }
    }
}

public extension DetectedGarment {
    /// La misma prenda con otro recorte.
    ///
    /// Existe porque el recorte se decide **después** de saber qué prenda es:
    /// el pipeline genera varios —segmentador, sujeto, color— y se queda con el
    /// que mejor puntúa, conservando todo lo demás. Ver `CutoutQuality`.
    func replacingImages(normalized: ImmutableImage, rawCrop: ImmutableImage) -> DetectedGarment {
        DetectedGarment(
            kind: kind,
            confidence: confidence,
            normalized: normalized,
            rawCrop: rawCrop,
            colors: colors,
            featurePrint: featurePrint,
            subcategory: subcategory,
            material: material,
            tags: tags,
            seasons: seasons,
            brand: brand,
            brandEvidence: brandEvidence,
            instanceIndex: instanceIndex,
            sourceRect: sourceRect
        )
    }
}
