import Foundation

/// Cómo se distingue una maleta de otra de un vistazo.
///
/// Una paleta cerrada, no un selector libre. Con color libre cada maleta acaba
/// con un tono distinto y ninguno se reconoce; con diez que combinan entre sí,
/// "la verde" acaba significando algo.
///
/// **Sin nombres.** Un color se elige mirándolo: poner "Salvia" debajo obliga a
/// leer diez etiquetas para hacer lo que el ojo ya hizo, y además hay que
/// traducirlas.
public enum SuitcaseTint: String, Sendable, CaseIterable, Identifiable {
    case sand, clay, blush, coral, lilac, sky, teal, sage, olive, slate

    public var id: String { rawValue }

    public var components: (red: Double, green: Double, blue: Double) {
        switch self {
        case .sand:  (0.878, 0.816, 0.686)
        case .clay:  (0.816, 0.647, 0.553)
        case .blush: (0.906, 0.729, 0.722)
        case .coral: (0.886, 0.580, 0.518)
        case .lilac: (0.769, 0.733, 0.859)
        case .sky:   (0.639, 0.757, 0.867)
        case .teal:  (0.576, 0.769, 0.757)
        case .sage:  (0.686, 0.765, 0.667)
        case .olive: (0.635, 0.663, 0.486)
        case .slate: (0.667, 0.686, 0.722)
        }
    }
}

/// Los iconos entre los que elegir: **emoji**.
///
/// Eran símbolos SF y no funcionaba. Un glifo monocromo puesto sobre la maleta
/// se lee como parte del dibujo —una maleta con una maleta pintada encima— y no
/// como lo que es: una pegatina que le pusiste tú para reconocerla. El emoji
/// trae su propio color y su propia forma, así que se separa del cuerpo sin
/// necesidad de inventarle un marco.
///
/// Paleta cerrada y no el teclado del sistema: iOS no ofrece un teclado de solo
/// emoji, así que con un campo de texto libre acaba habiendo maletas llamadas
/// "🏖️ok" y maletas con la letra ñ de icono.
public enum SuitcaseEmoji: String, Sendable, CaseIterable, Identifiable {
    case suitcase = "🧳"
    case plane = "✈️"
    case beach = "🏖️"
    case mountain = "⛰️"
    case city = "🏙️"
    case backpack = "🎒"
    case gym = "💪"
    case ski = "🎿"
    case party = "🎉"
    case camping = "🏕️"
    case car = "🚗"
    case ship = "🛳️"
    case surf = "🏄"
    case work = "💼"
    case home = "🏡"
    case sun = "☀️"
    case snow = "❄️"
    case heart = "❤️"

    public var id: String { rawValue }

    /// Qué emoji enseñar para lo que haya guardado.
    ///
    /// Las maletas creadas antes llevan un nombre de símbolo SF en el mismo
    /// campo. En vez de migrar el esquema por un icono, se traducen aquí: el
    /// dato viejo sigue siendo válido y no hay ninguna maleta que se quede sin
    /// icono por haberse creado la semana pasada.
    public static func display(for raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return suitcase.rawValue }
        if let known = SuitcaseEmoji(rawValue: raw) { return known.rawValue }
        return legacy[raw] ?? suitcase.rawValue
    }

    private static let legacy: [String: String] = [
        "suitcase.fill": suitcase.rawValue,
        "backpack.fill": backpack.rawValue,
        "bag.fill": work.rawValue,
        "beach.umbrella.fill": beach.rawValue,
        "mountain.2.fill": mountain.rawValue,
        "building.2.fill": city.rawValue,
        "airplane": plane.rawValue,
        "figure.run": gym.rawValue,
    ]
}

// **Los símbolos SF de antes, comentados y no borrados.** Son los que siguen
// guardados en las maletas ya creadas —`SuitcaseEmoji.display(for:)` los
// traduce— y la lista es la referencia de qué significaba cada uno.
//
// public enum SuitcaseSymbol: String, Sendable, CaseIterable, Identifiable {
//     case suitcase = "suitcase.fill"
//     case backpack = "backpack.fill"
//     case duffle = "bag.fill"
//     case beach = "beach.umbrella.fill"
//     case mountain = "mountain.2.fill"
//     case city = "building.2.fill"
//     case plane = "airplane"
//     case gym = "figure.run"
//
//     public var id: String { rawValue }
// }
