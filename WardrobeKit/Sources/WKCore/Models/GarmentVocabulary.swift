import Foundation

/// El vocabulario con el que se describe una prenda.
///
/// En `WKCore` y como datos, no repartido por las vistas: lo usan las hojas de
/// selección, el nombrado de respaldo y, en F7, el prompt bank. Tres sitios que
/// tienen que coincidir palabra por palabra o la clasificación deja de casar
/// con lo que el usuario ve.
public enum GarmentVocabulary {

    /// Tipo de prenda por parte del cuerpo.
    ///
    /// Se ofrecen solo los tipos de **su** parte: enseñar "Falda" al editar
    /// unas zapatillas es ruido, y peor, invita a un error.
    public static func types(for kind: GarmentKind) -> [String] {
        switch kind {
        case .upperBody:
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
