import Foundation

/// Lo que puede haber en el canvas además de ropa.
///
/// No es un modelo de persistencia: es cómo se **lee** un `CanvasItem` que no
/// lleva prenda. El item guarda campos planos, que es lo que SwiftData sabe
/// migrar sin escribir código, y esto los interpreta.
public enum CanvasSticker: Sendable, Equatable {
    case date(Date)
    case text(TextSticker)
    case photo(key: String)
    /// El tiempo que hacía —o que va a hacer— ese día. Guardado como foto
    /// fija: ver un outfit viejo y que diga el tiempo de hoy sería mentir
    /// sobre por qué te vestiste así.
    case weather(WeatherSnapshot)

    public enum Kind: String, Sendable, CaseIterable {
        case date, text, photo, weather
    }

    public var kind: Kind {
        switch self {
        case .date: .date
        case .text: .text
        case .photo: .photo
        case .weather: .weather
        }
    }
}

/// Un texto puesto en el canvas.
public struct TextSticker: Sendable, Equatable {
    public var string: String
    /// `#RRGGBB`. El color escrito y no un índice de paleta: si la paleta
    /// cambia, los stickers ya hechos no se recolorean solos a espaldas de
    /// quien los escribió.
    public var colorHex: String
    /// `nil` = texto suelto, sin caja detrás.
    public var backgroundHex: String?
    public var alignment: Alignment

    public enum Alignment: String, Sendable, CaseIterable {
        case leading, center, trailing
    }

    public init(
        string: String = "",
        colorHex: String = "#FFFFFF",
        backgroundHex: String? = nil,
        alignment: Alignment = .center
    ) {
        self.string = string
        self.colorHex = colorHex
        self.backgroundHex = backgroundHex
        self.alignment = alignment
    }

    /// Los colores del editor de texto.
    ///
    /// Blanco y negro primero: son los que se usan el 90% de las veces sobre
    /// un collage, y enterrarlos detrás de los colores vivos obliga a buscar
    /// lo más común.
    public static let palette = [
        "#FFFFFF", "#111111", "#E5484D", "#F5B14C",
        "#5AC8F5", "#3B5BDB", "#8B5CF6", "#3FA96B",
    ]
}
