import Foundation

/// Entiende lo que se le pide al estilista **escrito a mano**.
///
/// ## Por qué esto no es un modelo de lenguaje
///
/// Porque lo que se le dice a un armario cabe en cuatro cosas: un color, una
/// ocasión, el frío que hace y una prenda concreta que quieres ponerte o no
/// volver a ver. Reconocer eso son listas de palabras y un poco de cuidado con
/// las negaciones; mandarlo a un servidor para que devuelva lo mismo sería
/// pagar y esperar por lo que ya está aquí. Y cuando no entiende algo, **lo
/// dice**, en vez de inventarse una respuesta convincente.
public enum StylistPhrase {

    /// Lo que se ha entendido de una frase.
    public struct Reading: Sendable {
        /// El encargo, con lo dicho ya aplicado encima del anterior.
        public var brief: StylistBrief
        /// Lo que se ha reconocido, en palabras, para poder confirmarlo.
        public var understood: [String]
        /// **Qué se puede tocar del conjunto que hay puesto.**
        ///
        /// "Cámbiame el pantalón" no es lo mismo que "algo azul": lo primero
        /// dice exactamente qué se queda y qué se va. Sin esto, cualquier
        /// petición rehacía el conjunto entero y se llevaba por delante las
        /// prendas que el usuario había puesto a mano.
        public var freedRoles: Set<StylistRole>
        /// `true` si de toda la frase no se sacó nada.
        public var isBlank: Bool { understood.isEmpty && freedRoles.isEmpty }
    }

    /// Aplica una frase sobre el encargo que hubiera.
    public static func read(
        _ text: String,
        wardrobe: [StylistGarment],
        base: StylistBrief
    ) -> Reading {
        var brief = base
        var freedRoles: Set<StylistRole> = []
        brief.note = text
        // Cada frase nueva pide conjuntos nuevos, aunque diga lo mismo.
        brief.seed = UInt64(truncatingIfNeeded: text.hashValue) ^ UInt64(Date().timeIntervalSince1970)
        var understood: [String] = []

        for clause in clauses(of: text) {
            let negated = clause.isNegated
            let words = clause.words

            for (family, synonyms) in colorWords {
                guard words.contains(where: { synonyms.contains($0) }) else { continue }
                if negated {
                    brief.avoidedColors.append(family)
                    brief.preferredColors.removeAll { $0 == family }
                    understood.append(String(localized: "wkcore.stylistphrase.no", defaultValue: "no \(String(describing: family))", bundle: .module))
                } else {
                    brief.preferredColors.append(family)
                    brief.avoidedColors.removeAll { $0 == family }
                    understood.append(String(localized: "wkcore.stylistphrase.with", defaultValue: "with \(String(describing: family))", bundle: .module))
                }
            }

            for (tag, synonyms) in occasionWords where words.contains(where: { synonyms.contains($0) }) {
                if !negated, !brief.requiredTags.contains(tag) {
                    brief.requiredTags.append(tag)
                    understood.append(tag.lowercased())
                }
            }

            if words.contains(where: { coldWords.contains($0) }) {
                brief.warmth = .winter
                understood.append(String(localized: "wkcore.stylistphrase.forColdWeather", defaultValue: "for cold weather", bundle: .module))
            } else if words.contains(where: { heatWords.contains($0) }) {
                brief.warmth = .summer
                understood.append(String(localized: "wkcore.stylistphrase.forWarmWeather", defaultValue: "for warm weather", bundle: .module))
            } else if words.contains(where: { midWords.contains($0) }) {
                brief.warmth = .midSeason
                understood.append(String(localized: "wkcore.stylistphrase.inBetweenWeather", defaultValue: "in-between weather", bundle: .module))
            }

            // Una parte nombrada: "cámbiame el pantalón", "sin chaqueta".
            //
            // Nombrar una parte con intención de cambio la **suelta**: deja de
            // estar fijada aunque esté puesta en el lienzo, que es justo lo
            // que se pide al decir "otro pantalón".
            let wantsChange = words.contains { changeWords.contains($0) }
            for (role, synonyms) in roleWords where words.contains(where: { synonyms.contains($0) }) {
                guard negated || wantsChange else { continue }
                freedRoles.insert(role)
                understood.append(negated ? String(localized: "wkcore.stylistphrase.without", defaultValue: "without \(String(describing: role.spokenName))", bundle: .module) : String(localized: "wkcore.stylistphrase.another", defaultValue: "another \(String(describing: role.spokenName))", bundle: .module))
            }

            // Una prenda nombrada: "con los vaqueros negros", "el jersey no".
            for garment in matches(in: words, wardrobe: wardrobe) {
                if negated {
                    brief.banned.insert(garment.id)
                    brief.pinned.remove(garment.id)
                    understood.append(String(localized: "wkcore.stylistphrase.no", defaultValue: "no \(String(describing: garment.name.lowercasedFirst))", bundle: .module))
                } else {
                    brief.pinned.insert(garment.id)
                    brief.banned.remove(garment.id)
                    understood.append(String(localized: "wkcore.stylistphrase.with", defaultValue: "with \(String(describing: garment.name.lowercasedFirst))", bundle: .module))
                }
            }
        }

        let folded = fold(text)
        if repeatWords.contains(where: { folded.contains($0) }) {
            understood.append(String(localized: "wkcore.stylistphrase.withoutRepeatingTheseLastDays", defaultValue: "without repeating these last days", bundle: .module))
        }

        return Reading(brief: brief, understood: uniqued(understood), freedRoles: freedRoles)
    }

    /// Cómo contesta el estilista cuando ha entendido algo.
    public static func acknowledgement(_ reading: Reading, lookCount: Int) -> String {
        guard !reading.isBlank else {
            return lookCount > 0
                ? String(localized: "wkcore.stylistphrase.iDidnTQuiteGet", defaultValue: "I didn't quite get what you're after, but have a look at these.", bundle: .module)
                : String(localized: "wkcore.stylistphrase.iDidnTGetWhat", defaultValue: "I didn't get what you're after. Try a color, an occasion or a piece: «something blue for work», «no black», «with the white sneakers».", bundle: .module)
        }
        let asked = reading.understood.joined(separator: ", ")
        guard lookCount > 0 else {
            return String(localized: "wkcore.stylistphrase.nothingInTheClosetWorks", defaultValue: "\(String(describing: asked.capitalizedFirst)): nothing in the closet works with that. Try asking for fewer things at once.", bundle: .module)
        }
        // "Aquí van uno" no lo dice nadie.
        let tail = lookCount == 1 ? String(localized: "wkcore.stylistphrase.hereSOne", defaultValue: "Here's one.", bundle: .module) : String(localized: "wkcore.stylistphrase.hereAre", defaultValue: "Here are \(String(describing: lookCount)).", bundle: .module)
        return "\(asked.capitalizedFirst). \(tail)"
    }

    // MARK: Las palabras

    /// Una parte de la frase con su propio signo.
    ///
    /// Hace falta partirla porque "algo azul pero sin negro" tiene una cosa
    /// pedida y otra prohibida: mirar la frase entera daría las dos al mismo
    /// saco y acabaría proponiendo justo lo que no querías.
    private struct Clause {
        let words: [String]
        let isNegated: Bool
    }

    private static func clauses(of text: String) -> [Clause] {
        let folded = fold(text)
        let separators = CharacterSet(charactersIn: ",.;")
        var chunks: [String] = []
        for raw in folded.components(separatedBy: separators) {
            var current = raw
            for connector in [" pero ", " aunque ", " y sin ", " sin ", " nada de ", " menos "] {
                if let range = current.range(of: connector) {
                    chunks.append(String(current[..<range.lowerBound]))
                    current = connector.trimmingCharacters(in: .whitespaces) + " "
                        + String(current[range.upperBound...])
                }
            }
            chunks.append(current)
        }
        return chunks.compactMap { chunk in
            let words = chunk.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            guard !words.isEmpty else { return nil }
            return Clause(words: words, isNegated: words.contains { negationWords.contains($0) })
        }
    }

    private static let negationWords: Set<String> = [
        "sin", "no", "nada", "menos", "excepto", "salvo", "evita", "quita", "fuera", "odio",
    ]

    private static let repeatWords = [
        "no repet", "sin repet", "repetir", "otra cosa", "algo distinto", "algo diferente", "cambia",
    ]

    /// Palabras que piden cambio: "otro pantalón", "cámbiame los zapatos".
    private static let changeWords: Set<String> = [
        "cambia", "cambiame", "cambiar", "otro", "otra", "otros", "otras",
        "distinto", "distinta", "diferente", "quita", "saca", "sustituye",
    ]

    /// Las partes del conjunto, en las palabras con las que se nombran.
    private static let roleWords: [(StylistRole, Set<String>)] = [
        (.bottom, ["pantalon", "pantalones", "vaqueros", "jeans", "falda", "shorts", "bermudas", "leggings"]),
        (.top, ["camiseta", "camisa", "jersey", "sudadera", "polo", "blusa", "top", "vestido", "chaleco"]),
        (.outer, ["chaqueta", "abrigo", "cazadora", "gabardina", "blazer", "plumifero", "chubasquero"]),
        (.shoes, ["zapatos", "zapatillas", "botas", "botines", "sandalias", "calzado", "deportivas"]),
        (.accessory, ["gorra", "gorro", "bolso", "mochila", "bufanda", "cinturon", "complemento", "complementos", "gafas"]),
    ]

    private static let coldWords: Set<String> = [
        "frio", "abrigo", "abrigar", "invierno", "nieve", "helada", "gelido",
    ]
    private static let heatWords: Set<String> = ["calor", "verano", "playa", "fresquito", "fresco"]
    private static let midWords: Set<String> = ["entretiempo", "primavera", "otono", "templado"]

    /// Ocasiones → etiquetas de uso. Las etiquetas son las del armario, no un
    /// vocabulario nuevo: si aquí se inventara "Boda", no casaría con nada.
    private static let occasionWords: [(String, Set<String>)] = [
        ("Deporte", ["deporte", "gym", "gimnasio", "correr", "entrenar", "padel", "futbol", "running"]),
        ("Trabajo", ["trabajo", "oficina", "curro", "reunion", "trabajar"]),
        ("Formal", ["formal", "boda", "bautizo", "comunion", "ceremonia", "elegante", "traje", "cena"]),
        ("Fiesta", ["fiesta", "salir", "discoteca", "copas", "cumple", "cumpleanos"]),
        (String(localized: "common.beach", defaultValue: "Beach", bundle: .module), ["playa", "piscina", "mar"]),
        ("Viaje", ["viaje", "viajar", "avion", "vuelo", "aeropuerto"]),
        ("Casa", ["casa", "comodo", "sofa", "tirado"]),
        ("Diario", ["diario", "normal", "cualquier", "calle", "paseo"]),
    ]

    /// Colores en las palabras con las que se piden, no en las de la tabla de
    /// ciento y pico: nadie escribe "azul acero".
    private static let colorWords: [(String, Set<String>)] = [
        ("negro", ["negro", "negros", "negra", "negras"]),
        ("blanco", ["blanco", "blancos", "blanca", "blancas"]),
        ("gris", ["gris", "grises"]),
        ("azul", ["azul", "azules", "vaquero", "denim", "marino"]),
        ("verde", ["verde", "verdes", "caqui", "oliva"]),
        ("rojo", ["rojo", "rojos", "roja", "rojas", "granate", "burdeos"]),
        ("rosa", ["rosa", "rosas", "rosado"]),
        ("amarillo", ["amarillo", "amarilla", "mostaza"]),
        ("naranja", ["naranja", "naranjas"]),
        ("morado", ["morado", "morada", "lila", "violeta"]),
        ("tierra", ["marron", "beige", "camel", "arena", "tierra", "crema"]),
    ]

    /// Las prendas del armario nombradas en la frase.
    ///
    /// Se exige **más de una palabra en común** —"vaqueros" y "negros"— o una
    /// que solo tenga esa prenda. Con una palabra suelta, "zapatillas" casaría
    /// con las seis que tienes y elegiría una al azar, que es peor que no
    /// entenderlo.
    private static func matches(in words: [String], wardrobe: [StylistGarment]) -> [StylistGarment] {
        let phrase = Set(words.filter { $0.count > 3 })
        guard !phrase.isEmpty else { return [] }

        var scored: [(StylistGarment, Int)] = []
        for garment in wardrobe {
            let garmentWords = Set(
                garment.searchText.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .map(String.init)
                    .filter { $0.count > 3 }
            )
            let shared = garmentWords.intersection(phrase)
            guard shared.count >= 2 else { continue }
            scored.append((garment, shared.count))
        }
        guard !scored.isEmpty else { return [] }
        let best = scored.map(\.1).max() ?? 0
        // Solo las que empatan en lo más específico, y como mucho dos: si la
        // frase señala a media docena, no señalaba a ninguna.
        let winners = scored.filter { $0.1 == best }.map(\.0)
        return winners.count <= 2 ? winners : []
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    private static func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
