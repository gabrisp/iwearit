import Foundation

/// Qué **es** una prenda, según el modelo de visión.
///
/// Esto lo decide la IA y **el usuario no lo edita nunca**. Es la materia prima
/// del combinador de outfits ("un outfit necesita un `upperBody` + un `lowerBody`
/// + unos `feet`"). Si fuera editable, esa lógica se rompería en cuanto alguien
/// creara una categoría propia llamada "Verano".
///
/// No confundir con `GarmentCategory`, que es **la balda** y ahí sí manda el usuario.
public enum GarmentKind: String, Codable, Sendable, CaseIterable, Hashable {
    /// Camisetas, camisas, jerséis, tops. Clase 4 de SegFormer resuelta como capa interior.
    case upperBody
    /// Chaquetas, abrigos, cazadoras. Clase 4 de SegFormer resuelta como capa exterior.
    case outerLayer
    /// Pantalones, faldas, shorts. Clases 5 y 6.
    case lowerBody
    /// Vestidos y monos. Clase 7.
    case wholeBody
    /// Calzado. Clases 9 y 10 **fusionadas en una sola prenda** (si no, cada par
    /// generaría dos entradas y la balda quedaría llena de duplicados falsos).
    case feet
    /// Gorras, gorros, gafas. Clases 1 y 3.
    case head
    /// Bolsos y mochilas. Clase 16.
    case bag
    /// Bufandas, cinturones y cualquier cosa que no encaje arriba.
    case other

    /// Identificador de la categoría semilla donde cae una prenda de este tipo
    /// cuando ninguna categoría propia del usuario supera el umbral de similitud.
    public var seedCategorySlug: String {
        switch self {
        case .upperBody:  "tops"
        case .outerLayer: "outerwear"
        case .lowerBody:  "bottoms"
        case .wholeBody:  "whole-body"
        case .feet:       "shoes"
        case .head:       "accessories"
        case .bag:        "bags"
        case .other:      "other"
        }
    }

    /// Un outfit "completo" necesita cubrir torso y piernas, o bien una prenda de cuerpo entero.
    public var coversTorso: Bool { self == .upperBody || self == .wholeBody || self == .outerLayer }
    public var coversLegs: Bool  { self == .lowerBody || self == .wholeBody }
}
