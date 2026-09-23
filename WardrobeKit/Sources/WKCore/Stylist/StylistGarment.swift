import Foundation

/// Una prenda **como la ve el estilista**: lo justo para decidir si pega.
///
/// ## Por qué un valor y no el `@Model`
///
/// Porque combinar outfits es aritmética sobre unos cuantos números —tono,
/// claridad, cuánto abriga, cuándo te la pusiste— y hacerla sobre objetos de
/// SwiftData ataría el motor al hilo principal y al contexto. Así es un
/// `Sendable` puro: se puede probar sin base de datos y calcular fuera del
/// hilo de la interfaz sin que nada se entere.
public struct StylistGarment: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let kind: GarmentKind
    public let name: String
    public let colors: [NamedColor]
    public let seasons: SeasonSet
    public let tags: [String]
    public let subcategory: String?
    public let material: String?
    /// La manga o el largo: lo que decide si una prenda abriga de verdad.
    public let cut: String?
    public let lastWornAt: Date?
    public let wearCount: Int
    public let isFavorite: Bool
    /// Clave de `ImageStore`, para pintarla. El motor no la mira.
    public let imageKey: String

    public init(
        id: UUID,
        kind: GarmentKind,
        name: String,
        colors: [NamedColor],
        seasons: SeasonSet,
        tags: [String] = [],
        subcategory: String? = nil,
        material: String? = nil,
        cut: String? = nil,
        lastWornAt: Date? = nil,
        wearCount: Int = 0,
        isFavorite: Bool = false,
        imageKey: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.colors = colors
        self.seasons = seasons
        self.tags = tags
        self.subcategory = subcategory
        self.material = material
        self.cut = cut
        self.lastWornAt = lastWornAt
        self.wearCount = wearCount
        self.isFavorite = isFavorite
        self.imageKey = imageKey
    }

    /// El color que manda, ya en tono/saturación/claridad.
    public var tone: ColorTone {
        ColorTone(colors.max { $0.weight < $1.weight })
    }

    /// El papel que juega en el conjunto.
    public var role: StylistRole { StylistRole(kind) }

    /// Abriga de verdad: punto, lana, plumas, pana.
    var isWarm: Bool {
        let words = Self.fold([subcategory ?? "", material ?? "", name].joined(separator: " "))
        return ["lana", "punto", "plumas", "plumifero", "pana", "cachemir", "polar", "abrigo", "jersey", "sudadera"]
            .contains { words.contains($0) }
    }

    /// Es de ir fresco: manga corta, sin manga, pantalón corto, lino.
    var isAiry: Bool {
        let words = Self.fold([cut ?? "", subcategory ?? "", material ?? ""].joined(separator: " "))
        return ["sin manga", "manga corta", "corto", "corta", "short", "banador", "lino", "sandalias", "tirantes"]
            .contains { words.contains($0) }
    }

    /// Punto grueso: un jersey, una sudadera, un cárdigan.
    ///
    /// Hace falta porque el detector manda muchos de estos a "capa exterior"
    /// —y con razón: se llevan encima— pero **no se llevan encima de otro
    /// igual**. Dos jerséis en el mismo conjunto no es una forma de vestir, es
    /// un fallo de la máquina.
    var isKnit: Bool {
        let words = Self.fold([name, subcategory ?? "", material ?? ""].joined(separator: " "))
        return ["jersey", "sudadera", "cardigan", "punto", "hoodie", "sueter", "chaleco"]
            .contains { words.contains($0) }
    }

    /// Abrigo de verdad: lo que sí se pone encima de cualquier cosa.
    var isTrueOuter: Bool {
        let words = Self.fold([name, subcategory ?? ""].joined(separator: " "))
        return [
            "chaqueta", "abrigo", "cazadora", "gabardina", "blazer", "plumifero",
            "chubasquero", "parka", "trench", "vaquera", "cuero", "bomber",
        ].contains { words.contains($0) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// Cómo se llama en una frase: "los vaqueros azules".
    public var searchText: String {
        ([name, subcategory ?? "", material ?? "", tone.familyName] + tags)
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}

/// El hueco que ocupa una prenda en un conjunto.
///
/// Es el `GarmentKind` agrupado por **lo que hace**: para combinar da igual si
/// es gorra o bolso —ninguna de las dos compite con la otra— pero un pantalón
/// y una falda sí compiten, porque solo se lleva uno.
public enum StylistRole: String, Sendable, CaseIterable, Hashable {
    case top, bottom, outer, shoes, accessory

    public init(_ kind: GarmentKind) {
        switch kind {
        case .upperBody, .wholeBody: self = .top
        case .lowerBody: self = .bottom
        case .outerLayer: self = .outer
        case .feet: self = .shoes
        case .head, .bag, .other: self = .accessory
        }
    }

    /// Cómo se llama en una frase: "otro pantalón".
    public var spokenName: String {
        switch self {
        case .top: "arriba"
        case .bottom: "pantalón"
        case .outer: "abrigo"
        case .shoes: "calzado"
        case .accessory: "complemento"
        }
    }

    /// Sin esto no hay conjunto. Los complementos y la chaqueta se añaden si
    /// aportan; el torso y el calzado no son opcionales.
    public var isEssential: Bool {
        switch self {
        case .top, .shoes: true
        case .bottom, .outer, .accessory: false
        }
    }
}

/// Un color en lo único que decide si pega con otro: tono, cuánto color tiene
/// y cuánta luz.
///
/// ## Por qué no basta el nombre
///
/// Porque "azul" y "azul marino" combinan de forma distinta con un beige, y
/// porque el nombre es una etiqueta de una tabla de ciento y pico entradas: al
/// comparar dos nombres solo se puede decir si son iguales. Con tono y
/// claridad se puede decir *cuánto* se parecen, que es lo que hace falta.
public struct ColorTone: Sendable, Hashable {
    /// 0-360. `nil` cuando no hay color que valga (negros, grises, blancos).
    public let hue: Double?
    public let saturation: Double
    public let lightness: Double

    public init(hue: Double?, saturation: Double, lightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.lightness = lightness
    }

    public init(_ color: NamedColor?) {
        guard let color else {
            self.init(hue: nil, saturation: 0, lightness: 0.5)
            return
        }
        let r = color.red, g = color.green, b = color.blue
        let maxValue = max(r, g, b), minValue = min(r, g, b)
        let lightness = (maxValue + minValue) / 2
        let delta = maxValue - minValue
        let denominator = 1 - abs(2 * lightness - 1)
        let saturation = delta == 0 || denominator == 0 ? 0 : delta / denominator

        guard delta > 0.02 else {
            self.init(hue: nil, saturation: saturation, lightness: lightness)
            return
        }
        var hue: Double
        switch maxValue {
        case r: hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        case g: hue = (b - r) / delta + 2
        default: hue = (r - g) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        self.init(hue: hue, saturation: saturation, lightness: lightness)
    }

    /// Un neutro se lleva con todo: negro, blanco, gris, y los apagados
    /// —beige, caqui, marrón— que el ojo trata igual.
    public var isNeutral: Bool {
        guard let hue else { return true }
        if saturation < 0.22 { return true }
        // Los tierra: naranjas oscuros o muy claros. Un camel no compite con
        // ningún color, hace de fondo.
        if (15..<55).contains(hue), saturation < 0.55 || lightness > 0.72 || lightness < 0.35 {
            return true
        }
        return false
    }

    /// La familia de color, en la palabra de siempre. Para escribir el porqué.
    public var familyName: String {
        guard let hue, !isNeutral else {
            switch lightness {
            case ..<0.2: return "negro"
            case ..<0.45: return "gris oscuro"
            case ..<0.72: return saturation > 0.12 ? "tierra" : "gris"
            default: return "claro"
            }
        }
        switch hue {
        case ..<15, 345...: return "rojo"
        case ..<45: return "naranja"
        case ..<70: return "amarillo"
        case ..<165: return "verde"
        case ..<200: return "turquesa"
        case ..<255: return lightness < 0.3 ? "azul marino" : "azul"
        case ..<290: return "morado"
        default: return "rosa"
        }
    }

    /// Distancia entre dos tonos por el camino corto del círculo: 0-180.
    public func hueDistance(to other: ColorTone) -> Double? {
        guard let a = hue, let b = other.hue else { return nil }
        let raw = abs(a - b).truncatingRemainder(dividingBy: 360)
        return raw > 180 ? 360 - raw : raw
    }
}
