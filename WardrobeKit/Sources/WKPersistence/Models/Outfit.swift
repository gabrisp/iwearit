import Foundation
import SwiftData
import WKCore

/// Un conjunto montado en el canvas.
@Model
public final class Outfit {
    public var id: UUID = UUID()
    public var name: String?
    public var createdAt: Date = Date()
    public var modifiedAt: Date = Date()
    public var deletedAt: Date?
    /// Render del canvas, regenerado al guardar. Clave de `ImageStore`.
    public var thumbnailKey: String?
    /// Fondo pastel elegido para este outfit. `nil` = el neutro por defecto.
    ///
    /// Se guarda el nombre y no el color: así cambiar la paleta no obliga a
    /// migrar documentos, y un outfit guardado con un tono que ya no existe
    /// cae al neutro en vez de romperse.
    public var backdropRaw: String?

    /// Lo pintado a mano encima, en JSON (`[CanvasStroke]`).
    ///
    /// **Un campo del outfit y no un modelo aparte**: la pintura no se mueve,
    /// no se selecciona y no se comparte entre outfits — es una capa de
    /// anotación sobre este conjunto concreto, así que vive con él y se borra
    /// con él. Una entidad propia añadiría una relación y una tabla para
    /// guardar una lista de puntos.
    ///
    /// Opcional a propósito: `nil` es "no hay nada pintado", que es el caso de
    /// casi todos los outfits, y así no ocupa ni un byte.
    public var drawingData: Data?

    /// Guardado a favoritos.
    ///
    /// Vale tanto para un conjunto tuyo como para uno que venía de
    /// inspiración: en cuanto lo guardas es tuyo y se edita igual que
    /// cualquier otro. Por eso no hay dos listas ni dos modelos — lo que
    /// cambia es de dónde salió, que es `originRaw`, y eso solo sirve para
    /// contarlo.
    public var isFavorite: Bool = false

    /// De dónde salió: `nil` lo montaste tú, `inspo` lo propuso el estilista.
    ///
    /// Como cadena y no como enum en el modelo, igual que el resto: un valor
    /// que llegue de un dispositivo con una versión más nueva no rompe nada,
    /// simplemente no se reconoce.
    public var originRaw: String?

    /// Imán opcional a la retícula. **Apagado por defecto**: el requisito es
    /// conservar 32,56° exactos, y un snap silencioso los destruiría.
    public var snapToGrid: Bool = false

    @Relationship(deleteRule: .cascade, originalName: "items", inverse: \CanvasItem.outfit)
    public var storedItems: [CanvasItem]? = []

    public var items: [CanvasItem] { storedItems ?? [] }

    public var plannedDay: PlannedDay?
    public var suitcase: Suitcase?

    /// Día del viaje al que pertenece, contando desde 0 en la fecha de salida.
    ///
    /// No se reutiliza `PlannedDay` porque su `dayStart` es único **global**:
    /// un día del planificador y un día de viaje que cayeran en la misma fecha
    /// se pisarían. Un índice relativo a la maleta los mantiene separados.
    ///
    /// `nil` significa outfit simplemente **preparado**, que es lo que ocurre en
    /// una maleta sin fechas.
    public var suitcaseDayIndex: Int?

    public init(id: UUID = UUID(), name: String? = nil) {
        self.id = id
        self.name = name
        self.createdAt = Date()
    }

    /// El identificador **estable**, el que no cambia nunca.
    ///
    /// Hace falta un nombre propio porque `outfit.id` visto desde fuera se
    /// resuelve al identificador de SwiftData, no a este: y ese cambia cuando
    /// el contexto guarda. Usarlo como identidad de vista hacía que un outfit
    /// recién creado cambiara de identidad a mitad de la animación y se
    /// pintaran los dos, el de antes y el de después.
    ///
    /// Y con sincronización importa el doble: este es el mismo en todos los
    /// dispositivos; el de SwiftData, no.
    /// Lo que se ha probado de este conjunto. Ver `TryOnResult`.
    ///
    /// Vacío por defecto y sin borrado en cascada: el probado es una foto
    /// tuya, no una propiedad del outfit.
    @Relationship(deleteRule: .nullify) public var tryOns: [TryOnResult]? = []

    public var stableID: UUID { id }

    /// Siguiente `zIndex` para traer una prenda al frente.
    ///
    /// Se suma sobre el máximo en vez de reindexar el array: reindexar es la
    /// forma clásica de perder el orden exacto al recargar.
    public var nextZIndex: Double {
        (items.map(\.zIndex).max() ?? 0) + 1
    }

    public var lowestZIndex: Double {
        (items.map(\.zIndex).min() ?? 0) - 1
    }

    /// Las prendas del conjunto, sin huecos ni stickers.
    public var garments: [Garment] {
        items.compactMap(\.garment).filter { $0.deletedAt == nil }
    }
}

/// De dónde salió un outfit.
public enum OutfitOrigin: String, Sendable {
    case inspo
}

public extension FetchDescriptor where T == Outfit {

    /// Los guardados, de lo último a lo primero.
    ///
    /// Sin los borrados y sin los que pertenecen a un día o a una maleta: esos
    /// ya tienen su sitio donde se ven. Favoritos es la estantería de los que
    /// no están en ningún calendario.
    static func favouriteOutfits() -> FetchDescriptor<Outfit> {
        var descriptor = FetchDescriptor<Outfit>(
            predicate: #Predicate { $0.isFavorite && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        return descriptor
    }
}

/// Una prenda colocada en un canvas, con su transformada exacta.
///
/// - Important: todos los campos numéricos son `Double` de 64 bits y **nada se
///   redondea, se cuantiza ni se hace snap** — ni al guardar, ni al cargar, ni
///   al renderizar. Las coordenadas están en `CanvasSpace` (1000×1400 pt), que
///   es fijo, así que el round-trip es exacto y el layout relativo es idéntico
///   en un iPhone SE y en un iPad.
@Model
public final class CanvasItem {
    public var id: UUID = UUID()

    /// Centro de la prenda, en puntos de canvas.
    public var x: Double = CanvasSpace.center.x
    public var y: Double = CanvasSpace.center.y
    /// Tamaño intrínseco al soltarla. `scale` multiplica sobre esto.
    public var baseWidth: Double = 240
    public var baseHeight: Double = 320
    public var scale: Double = 1
    /// Radianes, precisión completa.
    public var rotation: Double = 0
    public var zIndex: Double = 0
    /// Espejo horizontal.
    ///
    /// Campo aparte y no una escala negativa: `scale` es un `Double` que
    /// multiplica ancho y alto a la vez, así que meterle el signo volteaba
    /// también en vertical y además rompía cualquier comparación de tamaño.
    public var isFlipped: Bool = false

    /// `nullify`: borrar una prenda deja un hueco en el outfit, no lo destruye.
    public var garment: Garment?
    public var outfit: Outfit?

    // MARK: Stickers
    //
    // Un sticker **es un `CanvasItem`**, no un tipo nuevo. Se mueve, se gira,
    // se escala, se duplica y se apila exactamente igual que una prenda, así
    // que darle su propio modelo obligaría a duplicar toda la manipulación y a
    // mantener dos listas ordenadas por `zIndex` que hay que intercalar al
    // pintar. Lo que cambia es **qué se dibuja dentro**, y eso es un campo.
    //
    // Todos opcionales y con valor por defecto: así la migración desde V1 es
    // ligera y ningún outfit existente se toca.

    /// `nil` = prenda. Si no, `CanvasSticker.Kind`.
    public var stickerKindRaw: String?
    public var text: String?
    /// `#RRGGBB`. Se guarda el color escrito, no un índice de paleta: si algún
    /// día cambia la paleta, los stickers ya hechos no se recolorean solos.
    public var textColorHex: String?
    /// `nil` = sin caja detrás del texto.
    public var textBackgroundHex: String?
    public var textAlignmentRaw: String?
    /// Sticker de fecha.
    public var date: Date?
    /// Sticker de foto. La clave del `ImageStore`, nunca los bytes.
    public var imageKey: String?
    /// Sticker del tiempo, codificado.
    ///
    /// Como `Data` y no como seis columnas: son datos que solo se leen juntos
    /// y nunca se filtran ni se ordenan por ellos, así que desplegarlos en
    /// columnas solo añadiría seis campos que mantener alineados.
    public var weatherData: Data?

    public init(transform: ItemTransform, garment: Garment?) {
        self.id = UUID()
        self.garment = garment
        apply(transform)
    }

    /// Qué hay dentro de este item.
    ///
    /// Se lee, no se guarda: el modelo almacena campos planos —que es lo que
    /// SwiftData sabe migrar— y esto los interpreta.
    public var sticker: CanvasSticker? {
        guard let raw = stickerKindRaw, let kind = CanvasSticker.Kind(rawValue: raw) else {
            return nil
        }
        switch kind {
        case .date:
            return .date(date ?? Date())
        case .text:
            return .text(
                TextSticker(
                    string: text ?? "",
                    colorHex: textColorHex ?? "#FFFFFF",
                    backgroundHex: textBackgroundHex,
                    alignment: TextSticker.Alignment(rawValue: textAlignmentRaw ?? "") ?? .center
                )
            )
        case .photo:
            guard let imageKey else { return nil }
            return .photo(key: imageKey)
        case .weather:
            guard
                let weatherData,
                let snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: weatherData)
            else { return nil }
            return .weather(snapshot)
        }
    }

    public func apply(_ sticker: CanvasSticker) {
        switch sticker {
        case let .date(value):
            stickerKindRaw = CanvasSticker.Kind.date.rawValue
            date = value
        case let .text(value):
            stickerKindRaw = CanvasSticker.Kind.text.rawValue
            text = value.string
            textColorHex = value.colorHex
            textBackgroundHex = value.backgroundHex
            textAlignmentRaw = value.alignment.rawValue
        case let .photo(key):
            stickerKindRaw = CanvasSticker.Kind.photo.rawValue
            imageKey = key
        case let .weather(snapshot):
            stickerKindRaw = CanvasSticker.Kind.weather.rawValue
            weatherData = try? JSONEncoder().encode(snapshot)
        }
    }

    public var transform: ItemTransform {
        ItemTransform(
            x: x, y: y,
            baseWidth: baseWidth, baseHeight: baseHeight,
            scale: scale, rotation: rotation, zIndex: zIndex
        )
    }

    /// Escribe la transformada **tal cual**. Sin `rounded()`, sin clamps.
    public func apply(_ t: ItemTransform) {
        x = t.x
        y = t.y
        baseWidth = t.baseWidth
        baseHeight = t.baseHeight
        scale = t.scale
        rotation = t.rotation
        zIndex = t.zIndex
    }
}
