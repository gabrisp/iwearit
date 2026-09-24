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

    /// - Parameter material: la textura, que entra **solo cuando no hay
    ///   marca**: "Polo Golden Goose" ya dice todo lo que hay que saber, y
    ///   añadirle "algodón azul" detrás lo alarga sin distinguir nada.
    public static func name(
        kind: GarmentKind,
        subcategory: String?,
        material: String? = nil,
        colors: [NamedColor],
        brand: String?
    ) -> String {
        let noun = subcategory?.capitalized ?? defaultNoun(for: kind)

        // **Un apellido, no tres.** "Zapatillas Golden Goose", "Cazadora
        // cuero", "Camiseta azul": el tipo y lo que más la distingue. Con
        // marca, la marca, que es como se llama a una prenda; sin marca, el
        // material, que distingue una cazadora de cuero de una vaquera; y si
        // no, el color. Juntarlos todos daba "Polo algodón azul marino
        // Stüssy", que no es un nombre sino una ficha.
        if let brand, !brand.isEmpty { return "\(noun) \(brand)" }
        if let material, !material.isEmpty { return "\(noun) \(titled(material))" }

        // **Siempre con color.** Antes solo entraba si mandaba en más del 45%
        // del recorte, y en la mayoría de prendas no llegaba: el nombre se
        // quedaba en "Vaqueros" a secas. Ahora va el dominante siempre, en su
        // palabra de las de siempre y concordando con la prenda: "Camiseta
        // Roja", "Vaqueros Negros", "Vaqueros Azul Claro".
        guard let dominant = colors.max(by: { $0.weight < $1.weight }) else { return noun }
        return "\(noun) \(titled(agree(dominant.basicName, with: noun)))"
    }

    /// El color concordado con la prenda.
    ///
    /// "Camiseta negra", "Vaqueros negros", "Zapatillas blancas". Los colores
    /// compuestos —azul claro, azul marino, gris oscuro— y los que son nombre
    /// de cosa —rosa, naranja, beige— no cambian: "vaqueros azul claro",
    /// "camisetas rosa".
    static func agree(_ color: String, with noun: String) -> String {
        guard !color.contains(" ") else { return color }

        let lower = noun.lowercased()
        let plural = lower.hasSuffix("s") && !["chándal", "jersey"].contains(lower)
        let singular = plural ? String(lower.dropLast(lower.hasSuffix("es") && !lower.hasSuffix("tes") ? 0 : 1)) : lower
        let feminine = singular.hasSuffix("a") || lower.hasSuffix("as")

        switch color {
        case "negro", "blanco", "rojo", "amarillo", "morado":
            let stem = String(color.dropLast())
            return stem + (feminine ? "a" : "o") + (plural ? "s" : "")
        case "gris", "azul", "marrón":
            guard plural else { return color }
            return color == "marrón" ? "marrones" : color + "es"
        case "verde":
            return plural ? "verdes" : color
        default:
            return color
        }
    }

    /// Con mayúscula en cada palabra, como el resto del nombre.
    static func titled(_ text: String) -> String {
        text.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    public static func name(for draft: GarmentDraft) -> String {
        name(
            kind: draft.kind,
            subcategory: draft.subcategory,
            material: draft.material,
            colors: draft.colors,
            brand: draft.brand
        )
    }

    /// El sustantivo cuando no hay subcategoría: lo más concreto que se puede
    /// decir sabiendo solo en qué parte del cuerpo va.
    ///
    /// **Nombres de prenda, no de parte del cuerpo.** "Top chocolate" y
    /// "Bottom en azul" son la organización interna asomando: nadie llama top
    /// a su camiseta. Cuando no se sabe el tipo exacto se pone el más común de
    /// esa parte, que se lee como ropa y se corrige de un toque.
    public static func defaultNoun(for kind: GarmentKind) -> String {
        switch kind {
        case .upperBody: "Camiseta"
        case .outerLayer: "Chaqueta"
        case .lowerBody: "Pantalón"
        case .wholeBody: "Vestido"
        case .feet: String(localized: "common.shoes", defaultValue: "Shoes", bundle: .module)
        case .head: "Gorra"
        case .bag: "Bolso"
        case .other: String(localized: "wkcore.garmentnaming.item", defaultValue: "Item", bundle: .module)
        }
    }
}
