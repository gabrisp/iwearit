import Foundation

/// Cómo se llama una prenda cuando nadie le ha puesto nombre.
///
/// Vive aquí y no dentro del actor que la guarda porque hacen falta **dos**
/// sitios: el armario al dar de alta, y la pantalla de revisión para enseñar,
/// antes de guardar, el nombre con el que se va a guardar. Con la regla en un
/// solo sitio, lo que se lee en la revisión es exactamente lo que acaba en la
/// balda; con dos copias, dejan de coincidir el día que alguien toca una.
public enum GarmentNaming {

    /// **Qué es, de qué color y de quién.**
    ///
    /// "Camiseta verde Stüssy" y no "Top en gris". Las tres piezas ya se
    /// calculan en cada importación y antes solo se usaban dos, así que la
    /// prenda llegaba al armario con un nombre que no distinguía una camisa de
    /// una sudadera — que es justo lo que hay que leer de un vistazo en una
    /// balda con treinta prendas.
    ///
    /// Se construye con lo que haya y nada más. Cada pieza que falta
    /// simplemente no aparece: sin marca reconocida, "Camiseta verde"; sin
    /// color medido, "Camiseta Stüssy". Rellenar el hueco con "Sin marca"
    /// ocuparía sitio en la balda para no decir nada.
    ///
    /// La marca va **al final y sin preposición**, que es como se nombra la
    /// ropa: "camiseta verde Stüssy", no "camiseta verde de Stüssy". Y solo
    /// entra si superó el listón de `BrandVerdict`: aquí llega ya decidida.
    /// Cuánto tiene que mandar un color para entrar en el nombre.
    ///
    /// **El color se mide, no se sabe.** Sale de un k-means sobre los píxeles
    /// del recorte, y en una prenda de cuadros, estampada o con dos tonos
    /// parecidos, el "dominante" gana por poco y puede ser el equivocado. Un
    /// color mal puesto en el nombre es peor que ninguno: se queda escrito en
    /// la balda, se busca por él y no aparece.
    ///
    /// Con menos del 45% del recorte, no se nombra. La prenda se llama
    /// "Camiseta Stüssy" y el color sigue estando en su ficha, que es donde se
    /// puede mirar y corregir sin que presuma de certeza.
    public static let colorNameThreshold = 0.45

    public static func name(
        kind: GarmentKind,
        subcategory: String?,
        colors: [NamedColor],
        brand: String?
    ) -> String {
        let noun = subcategory?.capitalized ?? defaultNoun(for: kind)
        let dominant = colors.max(by: { $0.weight < $1.weight })
        let color = (dominant?.weight ?? 0) >= colorNameThreshold ? dominant?.nameKey : nil
        return [noun, color, brand].compactMap { $0 }.joined(separator: " ")
    }

    public static func name(for draft: GarmentDraft) -> String {
        name(
            kind: draft.kind,
            subcategory: draft.subcategory,
            colors: draft.colors,
            brand: draft.brand
        )
    }

    /// El sustantivo cuando no hay subcategoría: lo más concreto que se puede
    /// decir sabiendo solo en qué parte del cuerpo va.
    public static func defaultNoun(for kind: GarmentKind) -> String {
        switch kind {
        case .upperBody: "Top"
        case .outerLayer: "Chaqueta"
        case .lowerBody: "Pantalón"
        case .wholeBody: "Vestido"
        case .feet: "Zapatos"
        case .head: "Accesorio"
        case .bag: "Bolso"
        case .other: "Prenda"
        }
    }
}
