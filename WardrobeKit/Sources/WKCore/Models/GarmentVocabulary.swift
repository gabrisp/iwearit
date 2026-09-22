import Foundation

/// El vocabulario con el que se describe una prenda.
///
/// En `WKCore` y como datos, no repartido por las vistas: lo usan las hojas de
/// selección, el nombrado de respaldo y, en F7, el prompt bank. Tres sitios que
/// tienen que coincidir palabra por palabra o la clasificación deja de casar
/// con lo que el usuario ve.
public enum GarmentVocabulary {

    /// Materiales que se ofrecen al editar.
    ///
    /// Una lista corta y en español, no la etiqueta de composición: nadie
    /// busca "65% poliéster 35% algodón", busca "es de algodón". Lo que hace
    /// falta es distinguir cómo se comporta la prenda —abriga, transpira, se
    /// arruga— y para eso llega con una docena de palabras.
    public static let materials = [
        "Algodón", "Lino", "Lana", "Cachemir", "Seda", "Vaquero",
        "Cuero", "Ante", "Poliéster", "Nailon", "Punto", "Pana",
        "Plumas", "Mezcla",
    ]

    /// Tipo de prenda por parte del cuerpo.
    ///
    /// Se ofrecen solo los tipos de **su** parte: enseñar "Falda" al editar
    /// unas zapatillas es ruido, y peor, invita a un error.
    public static func types(for kind: GarmentKind) -> [String] {
        switch kind {
        case .upperBody:
            // Con la manga aparte: entre una camiseta de manga corta y una de
            // manga larga hay medio armario de diferencia, y es lo primero que
            // se corrige al revisar una prenda recién importada.
            // La manga ya no va aquí: es su propio campo. Ver `cuts(for:)`.
            // Sin "Top": no es una prenda, es una manera de decir "lo de
            // arriba", y eso es un filtro. Lo que se tiene en el armario es
            // una camiseta, una camisa o un polo.
            ["Camiseta", "Camisa", "Polo", "Blusa", "Jersey", "Sudadera", "Chaleco"]
        case .outerLayer:
            ["Chaqueta", "Cazadora", "Abrigo", "Gabardina", "Vaquera", "Cuero", "Blazer", "Plumífero"]
        case .lowerBody:
            // Lo que es el pantalón. El largo —short, capri— va en su propia
            // etiqueta, y "pantalones" es la balda, no un tipo.
            ["Vaqueros", "Chinos", "De vestir", "Chándal", "Jogger", "Cargo", "Leggings", "Falda"]
        case .wholeBody:
            ["Vestido", "Vestido largo", "Mono", "Peto"]
        case .feet:
            ["Zapatillas", "Botas", "Zapatos", "Sandalias", "Bailarinas", "Botines"]
        case .head:
            ["Gorra", "Gorro", "Sombrero", "Gafas de sol", "Diadema"]
        case .bag:
            ["Bolso", "Mochila", "Bandolera", "Tote"]
        case .other:
            ["Bufanda", "Cinturón", "Corbata", "Guantes"]
        }
    }

    /// Cómo se llama el corte de una prenda, según lo que sea.
    ///
    /// Lo que distingue a dos camisetas es la manga; a dos pantalones, el
    /// largo. Un solo campo con el nombre que le toca a cada una, y ninguno
    /// donde no significa nada —unos zapatos no tienen manga ni largo—.
    public static func cutTitle(for kind: GarmentKind) -> String? {
        switch kind {
        case .upperBody, .outerLayer: "Manga"
        case .lowerBody, .wholeBody: "Largo"
        default: nil
        }
    }

    /// Los cortes de siempre. **No es una lista cerrada**: se puede escribir
    /// uno propio, porque cada armario llama a sus pantalones a su manera.
    public static func cuts(for kind: GarmentKind) -> [String] {
        switch kind {
        // Tres, no seis: son las que se distinguen de un vistazo. Lo demás
        // —un "jort", unos tobilleros— se escribe con el "+".
        case .upperBody, .outerLayer:
            ["Sin manga", "Manga corta", "Manga larga"]
        case .lowerBody:
            ["Corto", "Capri", "Largo"]
        case .wholeBody:
            ["Mini", "Midi", "Largo"]
        default:
            []
        }
    }

    /// El nombre de la balda de un tipo de prenda, en plural.
    ///
    /// Lo que se enseña de una prenda es **qué es** —camiseta, pantalón—, no
    /// en qué parte del cuerpo va: eso es un filtro, no una balda.
    public static func shelfName(for kind: GarmentKind) -> String {
        switch kind {
        case .upperBody: "Camisetas"
        case .outerLayer: "Chaquetas"
        case .lowerBody: "Pantalones"
        case .wholeBody: "Vestidos"
        case .feet: "Zapatos"
        case .head: "Accesorios"
        case .bag: "Bolsos"
        case .other: "Otros"
        }
    }

    /// Todos los tipos, en el orden en que se enseñan.
    ///
    /// **Lo que se elige es la prenda, no la parte del cuerpo.** "Top" y
    /// "Bottom" son cómo está organizado esto por dentro; nadie tiene un top
    /// en el armario, tiene una camisa o una camiseta. Así que la lista es de
    /// prendas, y de la prenda se deduce la parte —ver `kind(forType:)`—, que
    /// es lo que decide en qué balda acaba.
    public static let allTypes: [String] = GarmentKind.allCases.flatMap(types(for:))

    /// De qué parte del cuerpo es un tipo.
    ///
    /// La vuelta de `types(for:)`, que es donde está escrito una sola vez a
    /// qué parte pertenece cada prenda. Comparación insensible a mayúsculas y
    /// acentos porque el tipo puede venir del modelo, del usuario o de una
    /// lista antigua.
    public static func kind(forType type: String) -> GarmentKind? {
        let needle = type.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        for kind in GarmentKind.allCases {
            let match = types(for: kind).contains {
                $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) == needle
            }
            if match { return kind }
        }
        return nil
    }

    /// El tipo que dice una balda por sí sola.
    ///
    /// Si una prenda va a Camisetas, es una camiseta: decir "Balda:
    /// Camisetas · Tipo: sin definir" es contradecirse. Las baldas que son una
    /// prenda concreta dan su tipo; las que agrupan varias —pantalones puede
    /// ser un vaquero o un chino, zapatos unas botas o unas zapatillas— no
    /// dicen nada, y ahí sí queda sin definir.
    public static func defaultType(forShelfSlug slug: String) -> String? {
        switch slug {
        case "camisetas": "Camiseta"
        case "polos": "Polo"
        case "camisas": "Camisa"
        case "sudaderas": "Sudadera"
        case "jerseys": "Jersey"
        case "vestidos": "Vestido"
        case "chaquetas": "Chaqueta"
        case "banadores": "Bañador"
        case "bolsos": "Bolso"
        default: nil
        }
    }

    /// El tipo tal y como se enseña, o `nil` si no es un tipo de verdad.
    ///
    /// El detector a veces contesta con palabras de parte del cuerpo —"top",
    /// "bottom"— que no son prendas. Esas se tratan como "sin definir" en vez
    /// de enseñarse como si lo fueran.
    public static func displayType(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let notTypes: Set<String> = ["top", "tops", "bottom", "bottoms", "upper", "lower"]
        guard !notTypes.contains(folded) else { return nil }

        // **El tipo, sin repetir la balda.** "Pantalón de chándal" dentro de
        // la balda Pantalones es decir pantalón dos veces: el tipo es
        // "Chándal". Lo mismo con "camiseta de tirantes" en Camisetas.
        let redundant = [
            "pantalones de ", "pantalon de ", "pantalón de ",
            "camisetas de ", "camiseta de ", "camisas de ", "camisa de ",
            "chaqueta de ", "zapatillas de ", "zapatos de ",
        ]
        var text = raw.trimmingCharacters(in: .whitespaces)
        for prefix in redundant where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        return text.prefix(1).uppercased() + text.dropFirst().lowercased()
    }

    /// Estilo. Hasta tres por prenda: con más, dejan de significar nada.
    public static let tags = [
        "Oficina", "Chic", "Casual", "Ecléctico", "Experimental", "Étnico",
        "Oriental", "Elegante", "Retro", "Edgy", "Y2K", "Deportivo",
    ]
    public static let maximumTags = 3

    /// Calidez. Tres niveles y no cuatro estaciones: lo que decide si una
    /// prenda vale para hoy es cuánto abriga, no el mes del calendario.
    public enum Warmth: String, CaseIterable, Sendable {
        case summer, midSeason, winter

        public var label: String {
            switch self {
            case .summer: "Verano"
            case .midSeason: "Entretiempo"
            case .winter: "Invierno"
            }
        }

        public var seasons: SeasonSet {
            switch self {
            case .summer: [.spring, .summer]
            case .midSeason: .all
            case .winter: [.autumn, .winter]
            }
        }

        public static func from(_ seasons: SeasonSet) -> Warmth {
            if seasons == [.spring, .summer] { return .summer }
            if seasons == [.autumn, .winter] { return .winter }
            return .midSeason
        }
    }
}
