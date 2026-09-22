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
            ["Camiseta", "Camisa", "Blusa", "Polo", "Top", "Jersey", "Sudadera", "Chaleco"]
        case .outerLayer:
            ["Chaqueta", "Cazadora", "Abrigo", "Gabardina", "Vaquera", "Cuero", "Blazer", "Plumífero"]
        case .lowerBody:
            ["Vaqueros", "Pantalones", "Chinos", "Shorts", "Shorts vaqueros", "Falda", "Leggings"]
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
        case .upperBody, .outerLayer:
            ["Sin manga", "Tirantes", "Manga corta", "Manga 3/4", "Manga larga"]
        case .lowerBody:
            ["Short", "Jort", "Bermuda", "Capri", "Tobillero", "Largo"]
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
