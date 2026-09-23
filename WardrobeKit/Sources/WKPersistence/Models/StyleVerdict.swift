import Foundation
import SwiftData
import WKCore

/// Lo que opinas de un conjunto, **guardado como dato y no como un número**.
///
/// ## Por qué existe
///
/// Porque hasta ahora un "no me gusta" era medio punto en un diccionario de
/// `UserDefaults`: bastaba para que ese pantalón saliera menos, y no servía
/// para nada más. No se podía saber si lo tiraste por el color, por el calor
/// que hacía o porque ya te lo habías puesto el martes; ni si lo guardaste
/// para un viaje o para un lunes de oficina.
///
/// Aquí cada veredicto es una fila con su contexto: qué prendas, qué día, qué
/// tiempo hacía, de dónde salió la propuesta y qué dijo el estilista al
/// proponerla. Con eso, las recomendaciones dejan de ser "esto pesa menos" y
/// pasan a poder contestar preguntas — qué colores guardas y cuáles tiras, si
/// las propuestas con chaqueta te gustan cuando hace menos de quince grados,
/// qué prenda aparece en todo lo que descartas.
///
/// ## Y se sincroniza
///
/// Va en el almacén sincronizado: tus gustos son tuyos, no de este teléfono.
/// Al estrenar un iPad, lo que te gusta ya está ahí.
@Model
public final class StyleVerdict {

    public var id: UUID = UUID()
    public var createdAt: Date = Date()

    /// Qué dijiste. Ver `StyleVerdict.Kind`.
    public var verdictRaw: String = Kind.liked.rawValue
    /// Las prendas del conjunto, en el orden en que se propuso.
    ///
    /// Los identificadores y no la relación: un veredicto sobre un conjunto
    /// que ya no existe —porque era una propuesta y nunca se guardó— sigue
    /// diciendo algo, y una relación obligaría a inventar un outfit para poder
    /// opinar de él.
    public var garmentIDs: [UUID] = []
    /// Cómo se llamaba la propuesta: "Azul y arena".
    public var headline: String?
    /// Lo que el estilista dijo al proponerla, tal cual. Es la explicación que
    /// tenías delante al decir que sí o que no.
    public var reason: String?
    /// De dónde salió: `inspo`, `estilista`, `maleta`.
    public var sourceRaw: String = Source.inspo.rawValue

    /// El tiempo que hacía, porque la misma propuesta no es la misma en enero.
    public var temperature: Double?
    public var weatherRaw: String?

    public init(
        verdict: Kind,
        garmentIDs: [UUID],
        headline: String? = nil,
        reason: String? = nil,
        source: Source = .inspo,
        temperature: Double? = nil,
        weather: String? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.verdictRaw = verdict.rawValue
        self.garmentIDs = garmentIDs
        self.headline = headline
        self.reason = reason
        self.sourceRaw = source.rawValue
        self.temperature = temperature
        self.weatherRaw = weather
    }

    public var verdict: Kind { Kind(rawValue: verdictRaw) ?? .liked }
    public var source: Source { Source(rawValue: sourceRaw) ?? .inspo }

    /// Qué se dijo de la propuesta.
    ///
    /// Cuatro y no dos: guardar y descartar son opiniones, pero ponerse algo un
    /// día y llevárselo de viaje son **hechos**, y valen más que una opinión.
    /// Quien guarda por si acaso guarda mucho; quien se pone algo, se lo pone.
    public enum Kind: String, Sendable, CaseIterable, Codable {
        case liked
        case disliked
        /// Le puso fecha: se lo va a poner.
        case planned
        /// Se lo llevó de viaje.
        case packed

        /// Cuánto pesa a favor (positivo) o en contra (negativo).
        ///
        /// Un descarte pesa más que un guardado porque es más raro: la gente
        /// pasa propuestas sin decir nada, y molestarse en tirar una es una
        /// señal más fuerte que darle al corazón.
        public var weight: Double {
            switch self {
            case .liked: 0.6
            case .disliked: -1.0
            case .planned: 1.0
            case .packed: 0.8
            }
        }
    }

    public enum Source: String, Sendable, CaseIterable, Codable {
        case inspo
        case stylist
        case suitcase
    }
}

public extension FetchDescriptor where T == StyleVerdict {

    /// Lo último que has opinado. Con tope: para recomendar, lo de hace un año
    /// dice menos que lo del mes pasado, y recorrer diez mil filas en el hilo
    /// principal no lo paga nadie.
    static func recentVerdicts(limit: Int = 400) -> FetchDescriptor<StyleVerdict> {
        var descriptor = FetchDescriptor<StyleVerdict>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }
}
