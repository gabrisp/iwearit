import CoreGraphics
import Foundation

/// Un color dominante extraído de una prenda, con su nombre legible.
///
/// El nombre sale de una tabla de ~140 colores con nombre, no de un modelo:
/// dar nombre a un RGB es una búsqueda en el espacio Lab, no una tarea de IA.
public struct NamedColor: Codable, Sendable, Hashable {
    /// Clave de localización, no texto ya traducido: la tabla es la misma en
    /// todos los idiomas y se traduce al mostrarla.
    public let nameKey: String
    public let red: Double
    public let green: Double
    public let blue: Double
    /// Fracción de píxeles de la prenda que caen en este color, 0-1.
    /// Ordena cuál es el color principal.
    public let weight: Double

    public init(nameKey: String, red: Double, green: Double, blue: Double, weight: Double) {
        self.nameKey = nameKey
        self.red = red
        self.green = green
        self.blue = blue
        self.weight = weight
    }
}

/// Temporadas en las que se lleva una prenda. `OptionSet` porque casi todas
/// valen para varias, y un enum simple obligaría a elegir una sola.
public struct SeasonSet: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let spring = SeasonSet(rawValue: 1 << 0)
    public static let summer = SeasonSet(rawValue: 1 << 1)
    public static let autumn = SeasonSet(rawValue: 1 << 2)
    public static let winter = SeasonSet(rawValue: 1 << 3)

    public static let all: SeasonSet = [.spring, .summer, .autumn, .winter]
}
