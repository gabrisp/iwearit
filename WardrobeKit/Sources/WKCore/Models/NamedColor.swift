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


public extension NamedColor {

    /// El color **en una palabra de las de siempre**.
    ///
    /// La tabla de colores tiene ciento y pico nombres —"chocolate", "teja",
    /// "topo"— y aciertan el matiz a costa de que nadie busque por ellos ni
    /// sepa bien qué color son. Para el nombre de una prenda basta la familia:
    /// "Camiseta azul", no "Camiseta azul acero". Sale del propio RGB, así que
    /// un color elegido a mano en el selector también tiene su palabra.
    var basicName: String {
        let r = red, g = green, b = blue
        let maxValue = max(r, g, b), minValue = min(r, g, b)
        let lightness = (maxValue + minValue) / 2
        let delta = maxValue - minValue
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))

        // Sin color: de negro a blanco.
        if saturation < 0.15 || delta < 0.06 {
            switch lightness {
            case ..<0.18: return "negro"
            case ..<0.45: return "gris oscuro"
            case ..<0.78: return "gris"
            default: return "blanco"
            }
        }

        var hue: Double
        switch maxValue {
        case r: hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        case g: hue = (b - r) / delta + 2
        default: hue = (r - g) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }

        // Los marrones y los beiges son naranjas apagados u oscuros: el ojo
        // no los llama naranja.
        if (15..<50).contains(hue) {
            if lightness > 0.72 { return "beige" }
            if lightness < 0.42 || saturation < 0.45 { return "marrón" }
        }
        if lightness < 0.14 { return "negro" }
        if lightness > 0.9 { return "blanco" }

        // Claro u oscuro cuando se nota: unos vaqueros lavados son "azul
        // claro", no "azul", y es lo que los distingue de los otros.
        let shade = lightness > 0.66 ? " claro" : (lightness < 0.28 ? " oscuro" : "")

        switch hue {
        case ..<15, 345...: return lightness > 0.7 ? "rosa" : "rojo"
        case ..<45: return "naranja"
        case ..<70: return "amarillo"
        case ..<165: return "verde" + shade
        case ..<255: return lightness < 0.3 ? "azul marino" : "azul" + shade
        case ..<290: return "morado"
        default: return "rosa"
        }
    }
}
