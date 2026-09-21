import CoreGraphics
import Foundation
import Vision
import WKCore

/// Lee la marca de la prenda.
///
/// **OCR y no un modelo de logos.** La inmensa mayoría de las marcas de ropa
/// llevan su nombre escrito en la propia prenda —el pecho, la etiqueta, la
/// lengüeta de la zapatilla—, y leer texto lo hace Vision en el dispositivo,
/// gratis y sin descargar nada. Un clasificador de logotipos costaría otro
/// modelo que mantener, otra descarga y otro punto de fallo, y seguiría sin
/// leer "Massimo Dutti" en una etiqueta.
///
/// Lo que esto **no** hace es reconocer un logo sin texto: las tres bandas
/// solas, o el cocodrilo. Para eso está el embedder, que compara contra los
/// términos del banco de prompts; esto va primero porque cuando acierta, lo
/// hace con certeza y no con parecido.
public enum BrandRecognizer {

    /// Confianza mínima de la lectura.
    ///
    /// Alta a propósito: una marca inventada en la ficha de una prenda es peor
    /// que una ficha sin marca. El usuario puede escribirla; lo que no puede es
    /// adivinar que la que pone está mal.
    static let minimumConfidence: Float = 0.45

    /// Lo que se lee en la prenda, con lo seguro que se está de cada lectura.
    ///
    /// Una lectura exacta y una lectura con una errata **no valen lo mismo**, y
    /// devolver un `String?` las igualaba: la ficha acababa diciendo "Zara" con
    /// la misma cara tanto si estaba escrito nítido como si el OCR leyó "Zora"
    /// y alguien decidió que se parecía bastante.
    public static func evidence(in image: CGImage) async -> [BrandEvidence] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.customWords = Array(catalogue.keys)

        guard let observations = try? await request.perform(on: image) else { return [] }

        var found: [String: Double] = [:]
        for observation in observations {
            guard
                let candidate = observation.topCandidates(1).first,
                candidate.confidence >= minimumConfidence
            else { continue }
            guard let reading = read(candidate.string) else { continue }

            // La confianza del OCR entra en la cuenta: una etiqueta leída al
            // 50% no es lo mismo que una leída al 95%, aunque las dos casen.
            let score = reading.score * Double(candidate.confidence)
            found[reading.brand] = max(found[reading.brand] ?? 0, score)
        }

        return found
            .map { BrandEvidence(brand: $0.key, source: .ocr, confidence: $0.value) }
            .sorted { $0.confidence > $1.confidence }
    }

    /// Lo que casa, y **cómo** de bien.
    struct Reading {
        let brand: String
        /// 1 si el texto es exactamente el de la marca; menos si hizo falta
        /// perdonar una letra.
        let score: Double
    }

    /// Cuánto vale una lectura exacta.
    static let exactScore = 1.0
    /// Y una que necesitó perdonar una letra.
    ///
    /// Por debajo del listón de `BrandVerdict` a propósito: una lectura con
    /// errata **no basta sola** para escribir la marca, pero sí para que el
    /// resolutor remoto la confirme o la tire.
    static let typoScore = 0.62

    /// Lee el texto del recorte y lo casa contra el catálogo.
    ///
    /// - Parameter image: el recorte **sin normalizar**. Normalizado se ha
    ///   escalado a 768 y el texto de una etiqueta queda ilegible; en bruto
    ///   conserva los píxeles originales, que es lo que el OCR necesita.
    public static func brand(in image: CGImage) async -> String? {
        var request = RecognizeTextRequest()
        // `.accurate` y no `.fast`: el texto de una prenda va curvado sobre la
        // tela, en bajo contraste y a veces del revés. `.fast` está pensado
        // para documentos y aquí no lee nada.
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        // Sin corrección de idioma y con el catálogo como pistas: "adidas" no
        // está en ningún diccionario, y la corrección lo convertía en palabras
        // reales.
        request.customWords = Array(catalogue.keys)

        guard let observations = try? await request.perform(on: image) else { return nil }

        for observation in observations {
            guard
                let candidate = observation.topCandidates(1).first,
                candidate.confidence >= minimumConfidence
            else { continue }
            if let brand = match(candidate.string) { return brand }
        }
        return nil
    }

    /// Casa un trozo de texto leído contra el catálogo.
    ///
    /// Palabra a palabra y no la línea entera: el OCR devuelve "ADIDAS
    /// ORIGINALS" o "zara man" de una tirada, y buscar la línea completa no
    /// encontraría nada.
    static func match(_ text: String) -> String? {
        read(text)?.brand
    }

    /// Igual que `match`, pero diciendo si hubo que perdonar algo.
    static func read(_ text: String) -> Reading? {
        let normalized = normalize(text)
        if let exact = catalogue[normalized] { return Reading(brand: exact, score: exactScore) }

        // También sin espacios. Los signos de la marca —el apóstrofo de
        // "Levi's", el ampersand de "H&M"— se vuelven espacio al normalizar, y
        // buscar solo la forma separada dejaba fuera justo las marcas que
        // llevan signo en el nombre.
        let compact = normalized.replacingOccurrences(of: " ", with: "")
        if let exact = catalogue[compact] { return Reading(brand: exact, score: exactScore) }

        for word in normalized.split(separator: " ") where word.count >= 4 {
            if let exact = catalogue[String(word)] { return Reading(brand: exact, score: exactScore) }
            // Una letra de margen: el OCR confunde constantemente rn/m, l/I,
            // 0/O. Solo para palabras de cinco o más — con cuatro letras, una
            // de margen casa cualquier cosa con cualquier cosa.
            guard word.count >= 5 else { continue }
            for (key, brand) in catalogue where abs(key.count - word.count) <= 1 {
                if editDistanceIsAtMostOne(String(word), key) {
                    return Reading(brand: brand, score: typoScore)
                }
            }
        }
        return nil
    }

    /// Minúsculas, sin acentos y sin nada que no sea letra o número.
    ///
    /// "Levi's" y "LEVIS" tienen que caer en la misma clave, y el OCR devuelve
    /// una u otra según cómo pille el apóstrofo.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Distancia de edición ≤ 1, sin construir la matriz entera.
    ///
    /// Basta comparar en paralelo y permitir un solo desajuste: la matriz
    /// completa de Levenshtein sería recorrer n×m por cada marca del catálogo
    /// y por cada palabra leída, en cada prenda de un escaneo de galería.
    static func editDistanceIsAtMostOne(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let first = Array(a)
        let second = Array(b)
        if abs(first.count - second.count) > 1 { return false }

        var i = 0, j = 0
        var used = false
        while i < first.count, j < second.count {
            if first[i] == second[j] {
                i += 1
                j += 1
                continue
            }
            if used { return false }
            used = true
            if first.count > second.count {
                i += 1
            } else if second.count > first.count {
                j += 1
            } else {
                i += 1
                j += 1
            }
        }
        return true
    }

    /// Clave normalizada → nombre presentable.
    ///
    /// Una lista cerrada y no "cualquier texto es la marca": en una camiseta
    /// pone de todo —un lema, una ciudad, un número— y tomar la primera
    /// palabra legible por marca llenaría el armario de fichas equivocadas.
    ///
    /// Las variantes que el OCR produce de verdad tienen su propia entrada
    /// (`tommy` además de `tommy hilfiger`), porque un logo suele traer solo
    /// media marca.
    static let catalogue: [String: String] = {
        let brands: [(String, [String])] = [
            ("Adidas", ["adidas", "adidas originals"]),
            ("Nike", ["nike", "just do it"]),
            ("Zara", ["zara", "zara man", "zara woman"]),
            ("Bershka", ["bershka"]),
            ("Pull&Bear", ["pull bear", "pullbear"]),
            ("Stradivarius", ["stradivarius"]),
            ("Massimo Dutti", ["massimo dutti", "massimo"]),
            ("Mango", ["mango"]),
            ("H&M", ["h m", "hm", "divided"]),
            ("Uniqlo", ["uniqlo"]),
            ("Levi's", ["levis", "levi strauss"]),
            ("Lacoste", ["lacoste"]),
            ("Ralph Lauren", ["ralph lauren", "polo ralph lauren"]),
            ("Tommy Hilfiger", ["tommy hilfiger", "tommy jeans", "tommy"]),
            ("Calvin Klein", ["calvin klein", "calvin"]),
            ("The North Face", ["the north face", "north face"]),
            ("Carhartt", ["carhartt", "carhartt wip"]),
            ("Dickies", ["dickies"]),
            ("New Balance", ["new balance"]),
            ("Converse", ["converse", "all star"]),
            ("Vans", ["vans", "off the wall"]),
            ("Puma", ["puma"]),
            ("Reebok", ["reebok"]),
            ("Asics", ["asics"]),
            ("Salomon", ["salomon"]),
            ("Timberland", ["timberland"]),
            ("Dr. Martens", ["dr martens", "doc martens", "airwair"]),
            ("Columbia", ["columbia"]),
            ("Patagonia", ["patagonia"]),
            ("Jack & Jones", ["jack jones"]),
            ("Springfield", ["springfield"]),
            ("Desigual", ["desigual"]),
            ("Scalpers", ["scalpers"]),
            ("El Ganso", ["el ganso"]),
            ("Lefties", ["lefties"]),
            ("Primark", ["primark"]),
            ("Decathlon", ["decathlon", "quechua", "kalenji", "domyos"]),
            ("Hollister", ["hollister"]),
            ("Superdry", ["superdry"]),
            ("Champion", ["champion"]),
            ("Fila", ["fila"]),
            ("Ellesse", ["ellesse"]),
            ("Kappa", ["kappa"]),
            ("Umbro", ["umbro"]),
            ("Hugo Boss", ["hugo boss", "boss"]),
            ("Armani", ["armani", "emporio armani"]),
            ("Diesel", ["diesel"]),
            ("Guess", ["guess"]),
            ("Pepe Jeans", ["pepe jeans"]),
            ("G-Star", ["g star", "gstar"]),
            ("Wrangler", ["wrangler"]),
            ("Lee", ["lee"]),
            ("Nudie Jeans", ["nudie jeans"]),
            ("Stone Island", ["stone island"]),
            ("C.P. Company", ["cp company"]),
            ("Fred Perry", ["fred perry"]),
            ("Ben Sherman", ["ben sherman"]),
            ("Obey", ["obey"]),
            ("Stüssy", ["stussy"]),
            ("Supreme", ["supreme"]),
            ("Palace", ["palace"]),
            ("Thrasher", ["thrasher"]),
            ("Element", ["element"]),
            ("Quiksilver", ["quiksilver"]),
            ("Billabong", ["billabong"]),
            ("Rip Curl", ["rip curl"]),
            ("Oysho", ["oysho"]),
            ("Women'secret", ["women secret", "womensecret"]),
            ("Cortefiel", ["cortefiel"]),
            ("Skechers", ["skechers"]),
            ("Crocs", ["crocs"]),
            ("Birkenstock", ["birkenstock"]),
            ("Camper", ["camper"]),
            ("Geox", ["geox"]),
            ("Clarks", ["clarks"]),
            ("Havaianas", ["havaianas"]),
            ("Under Armour", ["under armour"]),
            ("Jordan", ["jordan", "air jordan"]),
            ("On", ["on running"]),
            ("Hoka", ["hoka", "hoka one one"]),
            ("Arc'teryx", ["arcteryx"]),
            ("Napapijri", ["napapijri"]),
            ("Ecoalf", ["ecoalf"]),
            ("Brava", ["brava fabrics"]),
            ("Sepiia", ["sepiia"]),
            ("Silbon", ["silbon"]),
            ("Hackett", ["hackett"]),
            ("Bimba y Lola", ["bimba y lola", "bimba lola"]),
            ("Loewe", ["loewe"]),
            ("Bottega Veneta", ["bottega veneta"]),
            ("Gucci", ["gucci"]),
            ("Prada", ["prada"]),
            ("Balenciaga", ["balenciaga"]),
            ("Burberry", ["burberry"]),
            ("Moncler", ["moncler"]),
            ("Lululemon", ["lululemon"]),
            ("Golden Goose", ["golden goose", "ggdb", "goldengoose", "ballstar", "superstar sneakers"]),
            ("Veja", ["veja"]),
            ("Autry", ["autry"]),
            ("Common Projects", ["common projects"]),
            ("Maison Margiela", ["maison margiela", "margiela"]),
            ("Off-White", ["off white"]),
            ("Acne Studios", ["acne studios"]),
            ("A.P.C.", ["apc"]),
            ("Sandro", ["sandro"]),
            ("The Kooples", ["the kooples"]),
            ("Salvatore Ferragamo", ["ferragamo"]),
            ("New Era", ["new era"]),
            ("Carolina Herrera", ["carolina herrera"]),
            ("Adolfo Domínguez", ["adolfo dominguez"]),
            ("Purificación García", ["purificacion garcia"]),
            ("Bimba", ["bimba"]),
            ("Gymshark", ["gymshark"]),
            ("Oysho Sport", ["oysho sport"]),
        ]

        var table: [String: String] = [:]
        for (name, keys) in brands {
            for key in keys { table[key] = name }
        }
        return table
    }()
}
