import Foundation

/// Quién es dueño de qué, y cómo se firma en la etiqueta.
///
/// ## Para qué sirve esto de verdad
///
/// No para escribir "Inditex" en la ficha — a nadie le importa el grupo, a
/// todo el mundo le importa la tienda. Sirve para **corroborar**.
///
/// La etiqueta de composición de una prenda de tienda casi nunca lleva solo el
/// nombre comercial: lleva también el de la sociedad que la vende. Una camiseta
/// de Bershka pone "BERSHKA" grande y "INDUSTRIA DE DISEÑO TEXTIL, S.A."
/// pequeñito debajo. Y ese segundo texto es justo el que el OCR lee **bien**,
/// porque está impreso en tinta negra sobre tela blanca, mientras el logo
/// grande va bordado del mismo color que la prenda.
///
/// Así que cuando la lectura del nombre comercial sale con una errata —el
/// clásico "8ERSHKA"— y además se lee el nombre de la sociedad, no hay que
/// adivinar nada: las dos cosas se apoyan y la marca pasa el listón. Sin la
/// segunda, una lectura con errata se queda en sospecha y la ficha se queda sin
/// marca, que es lo correcto.
///
/// ## Lo que *no* está aquí
///
/// Los nombres legales que identifican a **una sola** marca de cara al público
/// —"Punto Fa" es Mango y nada más, "Devanlay" es Lacoste y nada más— no son
/// grupos: son la marca escrita de otra forma, y viven en el catálogo de
/// `BrandRecognizer` como cualquier otro alias. Aquí solo hay lo que cubre a
/// varias marcas a la vez y por tanto **no puede nombrar la tienda solo**.
enum RetailGroups {

    /// Cuánto sube una lectura que además viene firmada por su grupo.
    ///
    /// Se combina como probabilidad independiente, igual que hace
    /// `BrandVerdict`: una lectura con errata (0,56) corroborada llega a 0,73 y
    /// pasa el listón; una lectura que no casaba con nada sigue sin existir,
    /// porque corroborar la nada no da nada.
    static let corroboration = 0.4

    /// Marca → grupo. Construida al revés de como se lee, que es como se
    /// escribe sin repetirse.
    static let owner: [String: String] = {
        let groups: [(String, [String])] = [
            ("Inditex", [
                "Zara", "Bershka", "Pull&Bear", "Stradivarius",
                "Massimo Dutti", "Oysho", "Lefties",
            ]),
            ("H&M Group", ["H&M"]),
            ("Tendam", ["Springfield", "Cortefiel", "Women'secret"]),
            ("PVH", ["Tommy Hilfiger", "Calvin Klein"]),
            ("VF", ["The North Face", "Vans", "Timberland", "Dickies", "Napapijri"]),
            ("Bestseller", ["Jack & Jones"]),
            ("Kering", ["Gucci", "Balenciaga", "Bottega Veneta"]),
            ("LVMH", ["Loewe"]),
            ("Nike Inc.", ["Nike", "Jordan", "Converse"]),
            ("Decathlon", ["Decathlon"]),
        ]
        var table: [String: String] = [:]
        for (group, brands) in groups {
            for brand in brands { table[brand] = group }
        }
        return table
    }()

    /// Texto normalizado que aparece en la etiqueta → grupo.
    ///
    /// Solo firmas largas y sin ambigüedad. Nada de siglas de tres letras: en
    /// una etiqueta con veinte palabras, tres letras casan por accidente.
    static let signatures: [String: String] = [
        "inditex": "Inditex",
        "industria de diseno textil": "Inditex",
        "hennes mauritz": "H&M Group",
        "h m hennes mauritz": "H&M Group",
        "tendam": "Tendam",
        "grupo cortefiel": "Tendam",
        "pvh corp": "PVH",
        "tommy hilfiger licensing": "PVH",
        "vf corporation": "VF",
        "vf outdoor": "VF",
        "bestseller": "Bestseller",
        "kering": "Kering",
        "lvmh": "LVMH",
        "nike inc": "Nike Inc.",
        "nike retail": "Nike Inc.",
        "oxylane": "Decathlon",
        "decathlon espana": "Decathlon",
    ]

    /// El grupo de una marca, si es de alguno.
    static func group(of brand: String) -> String? { owner[brand] }

    /// El grupo que firma un texto ya normalizado, si lo firma alguno.
    ///
    /// Busca la firma **dentro** de la línea y no la línea entera: lo que
    /// devuelve el OCR es "industria de diseno textil s a" con la forma social
    /// pegada detrás, y exigir igualdad no encontraría nada.
    static func signature(in normalized: String) -> String? {
        for (needle, group) in signatures where normalized.contains(needle) {
            return group
        }
        return nil
    }

    /// Todo lo que conviene pasarle al OCR como vocabulario.
    static var vocabulary: [String] { Array(signatures.keys) }
}
