import CoreGraphics
import Foundation
import Vision
import WKCore

/// Lee la **ficha del producto** cuando la foto es de una tienda.
///
/// Una captura de la web o una foto de catálogo sobre fondo blanco casi
/// siempre llevan el nombre del producto escrito al lado —"Camiseta oversize
/// algodón", "Relaxed Fit Jeans"— y a menudo la marca en la cabecera. Eso dice
/// qué es la prenda mejor que cualquier modelo mirando píxeles, y
/// `BrandRecognizer` no lo veía nunca: solo lee **dentro** del recorte.
///
/// ## Cuándo se mira
///
/// Primero una pasada rápida sobre la foto entera. En una foto de calle no hay
/// texto (o hay un cartel suelto) y aquí se acaba. Solo si hay varias líneas
/// de texto —una página— se hace la pasada precisa, que es la cara.
public enum ProductPageReader {

    public struct Page: Sendable, Equatable {
        /// El nombre del producto, limpio de precios y de ruido.
        public var title: String?
        /// El tipo de prenda del vocabulario, sacado del título.
        public var type: String?
        public var kind: GarmentKind?
        public var material: String?
        public var brandEvidence: [BrandEvidence]
    }

    /// Líneas de texto a partir de las que la foto se trata como una página.
    static let minimumLines = 3

    public static func read(_ image: CGImage) async -> Page? {
        // **Sin exigir una página.** Antes hacía falta una pasada rápida con
        // tres líneas o más, y una foto de producto con solo su nombre escrito
        // —una línea— no se leía nunca. Una sola pasada, la precisa: la
        // rápida además se perdía la letra fina o sobre la foto.
        // guard let quick = await lines(in: image, accurate: false),
        //       quick.filter({ $0.text.count >= 3 }).count >= minimumLines
        // else { return nil }

        guard let lines = await lines(in: image, accurate: true), !lines.isEmpty else { return nil }
        let page = parse(lines, isProductShot: SolidBackground.isLikely(in: image))
        DiagnosticsLog.record(
            "FICHA",
            "título \(page.title ?? "—") · tipo \(page.type ?? "—")"
                + " · material \(page.material ?? "—")"
                + " · marcas \(page.brandEvidence.map(\.brand).joined(separator: ", "))"
        )
        return page.title == nil && page.brandEvidence.isEmpty && page.material == nil ? nil : page
    }

    // MARK: - OCR

    struct Line: Sendable {
        let text: String
        let confidence: Float
        /// Alto del texto, 0-1 de la foto. Un título se escribe más grande que
        /// la letra pequeña de la página.
        let height: Double
    }

    static func lines(in image: CGImage, accurate: Bool) async -> [Line]? {
        var request = RecognizeTextRequest()
        request.recognitionLevel = accurate ? .accurate : .fast
        request.recognitionLanguages = [Locale.Language(identifier: "es-ES"), Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = true
        request.customWords = BrandRecognizer.catalogueWords
        guard let observations = try? await request.perform(on: image) else { return nil }
        return observations.compactMap { observation in
            guard let best = observation.topCandidates(1).first, best.confidence >= 0.3 else { return nil }
            return Line(
                text: best.string,
                confidence: best.confidence,
                height: Double(observation.boundingBox.height)
            )
        }
    }

    // MARK: - Lo que dice la página

    /// - Parameter isProductShot: fondo liso, de catálogo. Ahí cualquier
    ///   texto destacado es el nombre del producto aunque no diga qué prenda
    ///   es ("Air Force 1 '07"); en una foto de calle sería un cartel.
    static func parse(_ lines: [Line], isProductShot: Bool = false) -> Page {
        var page = Page(title: nil, type: nil, kind: nil, material: nil, brandEvidence: [])

        // El título: la línea más grande que diga qué prenda es.
        let titled = lines
            .compactMap { line -> (Line, String)? in
                guard !isInterface(line.text), let type = type(in: line.text) else { return nil }
                return (line, type)
            }
            .max { $0.0.height * Double($0.0.confidence) < $1.0.height * Double($1.0.confidence) }

        if let (line, type) = titled {
            page.title = cleanTitle(line.text)
            page.type = type
            page.kind = GarmentVocabulary.kind(forType: type)
            page.material = material(in: line.text)
        }
        // Sin tipo en ninguna línea: en una foto de producto, el texto más
        // grande es su nombre igualmente.
        if page.title == nil, isProductShot,
           let line = lines
            .filter({ isNameLike($0.text) })
            .max(by: { $0.height * Double($0.confidence) < $1.height * Double($1.confidence) }) {
            page.title = cleanTitle(line.text)
            page.material = material(in: line.text)
        }
        if page.material == nil {
            page.material = lines.lazy.compactMap { material(in: $0.text) }.first
        }

        // Las marcas, en cualquier línea. Leídas de una página impresa son
        // fiables: no hay tela curvada ni etiqueta arrugada.
        var best: [String: Double] = [:]
        for line in lines {
            guard let reading = BrandRecognizer.read(line.text) else { continue }
            let score = reading.score * Double(line.confidence)
            best[reading.brand] = max(best[reading.brand] ?? 0, score)
        }
        page.brandEvidence = best
            .map { BrandEvidence(brand: $0.key, source: .ocr, confidence: $0.value) }
            .sorted { $0.confidence > $1.confidence }
        return page
    }

    /// Palabras de tienda, en español y en inglés, → tipo del vocabulario.
    ///
    /// **El orden importa**: lo compuesto antes que lo suelto —"sweatshirt"
    /// contiene "shirt", "t-shirt" también—, así que lo más específico va
    /// primero.
    static let typeWords: [(needles: [String], type: String)] = [
        (["sudadera", "hoodie", "sweatshirt", "sweat shirt"], "Sudadera"),
        (["camiseta", "t-shirt", "tshirt", "t shirt", "tee"], "Camiseta"),
        (["polo"], "Polo"),
        (["camisa", "overshirt", "shirt"], "Camisa"),
        (["blusa", "blouse"], "Blusa"),
        (["jersey", "jersei", "sweater", "jumper", "cardigan", "cárdigan", "rebeca", "pullover"], "Jersey"),
        (["chaleco", "gilet", "vest"], "Chaleco"),
        (["gabardina", "trench"], "Gabardina"),
        (["plumifero", "plumífero", "puffer", "anorak"], "Plumífero"),
        (["abrigo", "coat", "parka"], "Abrigo"),
        (["cazadora", "bomber", "biker"], "Cazadora"),
        (["blazer", "americana"], "Blazer"),
        (["chaqueta", "jacket", "sobrecamisa"], "Chaqueta"),
        (["vaquero", "vaqueros", "jeans", "jean"], "Vaqueros"),
        (["chino", "chinos"], "Chinos"),
        (["chandal", "chándal", "tracksuit", "track pant"], "Chándal"),
        (["jogger", "joggers"], "Jogger"),
        (["cargo"], "Cargo"),
        (["leggings", "legging", "mallas"], "Leggings"),
        (["falda", "skirt"], "Falda"),
        (["pantalon de traje", "pantalón de traje", "trousers", "pantalon", "pantalón", "pants"], "De vestir"),
        (["peto", "dungarees"], "Peto"),
        (["mono", "jumpsuit"], "Mono"),
        (["vestido", "dress"], "Vestido"),
        (["zapatilla", "zapatillas", "sneaker", "sneakers", "trainers"], "Zapatillas"),
        (["botin", "botín", "botines", "ankle boot"], "Botines"),
        (["bota", "botas", "boots", "boot"], "Botas"),
        (["sandalia", "sandalias", "sandals"], "Sandalias"),
        (["bailarina", "bailarinas", "ballet flat"], "Bailarinas"),
        (["zapato", "zapatos", "loafer", "mocasin", "mocasín", "shoes"], "Zapatos"),
        (["gorra", "cap"], "Gorra"),
        (["gorro", "beanie"], "Gorro"),
        (["sombrero", "hat"], "Sombrero"),
        (["gafas de sol", "sunglasses"], "Gafas de sol"),
        (["mochila", "backpack"], "Mochila"),
        (["bandolera", "crossbody"], "Bandolera"),
        (["tote"], "Tote"),
        (["bolso", "bag"], "Bolso"),
        (["bufanda", "scarf"], "Bufanda"),
        (["cinturon", "cinturón", "belt"], "Cinturón"),
    ]

    static let materialWords: [(needles: [String], material: String)] = [
        (["algodon", "algodón", "cotton"], "Algodón"),
        (["lino", "linen"], "Lino"),
        (["cachemir", "cashmere"], "Cachemir"),
        (["lana", "wool", "merino"], "Lana"),
        (["seda", "silk", "satin", "satén"], "Seda"),
        (["denim", "tejano"], "Vaquero"),
        (["cuero", "piel", "leather"], "Cuero"),
        (["ante", "suede"], "Ante"),
        (["poliester", "poliéster", "polyester"], "Poliéster"),
        (["nailon", "nylon"], "Nailon"),
        (["punto", "knit"], "Punto"),
        (["pana", "corduroy"], "Pana"),
        (["plumas"], "Plumas"),
    ]

    /// Botones y avisos de la tienda: "Añadir a la cesta", "Guía de tallas".
    /// Nombran prendas —"bag", "cesta"— sin ser el título.
    static let interfaceWords = [
        "anadir", "add to", "comprar", "buy", "cesta", "carrito", "cart", "checkout",
        "envio", "shipping", "guia", "guide", "talla", "size", "devolucion", "returns",
        "ver mas", "see more", "similar", "wishlist", "favoritos",
    ]

    static func isInterface(_ text: String) -> Bool {
        let words = tokens(text)
        return interfaceWords.contains { contains(words, $0) }
    }

    /// Si una línea puede ser un nombre: con letras, sin ser un botón, un
    /// precio suelto o la marca sola.
    static func isNameLike(_ text: String) -> Bool {
        guard !isInterface(text), let clean = cleanTitle(text) else { return false }
        let letters = clean.filter(\.isLetter).count
        guard letters >= 3 else { return false }
        if let reading = BrandRecognizer.read(clean),
           tokens(clean).joined(separator: " ") == tokens(reading.brand).joined(separator: " ") {
            return false
        }
        return true
    }

    static func type(in text: String) -> String? {
        let words = tokens(text)
        return typeWords.first { rule in rule.needles.contains { contains(words, $0) } }?.type
    }

    static func material(in text: String) -> String? {
        let words = tokens(text)
        return materialWords.first { rule in rule.needles.contains { contains(words, $0) } }?.material
    }

    /// Por palabras enteras y no por subcadena: "tee" no puede casar dentro
    /// de "steel", ni "cap" dentro de "capri".
    static func contains(_ words: [String], _ needle: String) -> Bool {
        let parts = fold(needle).split(separator: " ").map(String.init)
        guard !parts.isEmpty, parts.count <= words.count else { return false }
        for start in 0...(words.count - parts.count) where Array(words[start..<(start + parts.count)]) == parts {
            return true
        }
        return false
    }

    static func tokens(_ text: String) -> [String] {
        fold(text)
            .replacingOccurrences(of: "-", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "t-shirt", with: "tshirt")
    }

    /// El título sin precio, sin referencias y con mayúsculas de frase.
    static func cleanTitle(_ raw: String) -> String? {
        var text = raw
        // Precios: "29,95 €", "€29.95", "$ 40".
        text = text.replacingOccurrences(
            of: #"[€$£]\s*\d+([.,]\d+)?|\d+([.,]\d+)?\s*(€|eur|usd|\$|£)"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Referencias de producto: "Ref. 1234/567".
        text = text.replacingOccurrences(of: #"ref\.?\s*[\d/.\-]+"#, with: "", options: [.regularExpression, .caseInsensitive])
        text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        guard text.count >= 3 else { return nil }
        if text.count > 48 { text = String(text.prefix(48)).trimmingCharacters(in: .whitespaces) }

        // Las tiendas escriben el título en mayúsculas; en la ficha se lee
        // mejor como frase.
        if text == text.uppercased() {
            let lower = text.lowercased()
            text = lower.prefix(1).uppercased() + lower.dropFirst()
        }
        return text
    }
}

extension DetectedGarment {
    /// La misma prenda con lo que dice la ficha del producto.
    func annotated(with page: ProductPageReader.Page, allowsKindChange: Bool) -> DetectedGarment {
        var newKind = kind
        var newSubcategory = subcategory
        if let type = page.type, let typeKind = page.kind {
            // Parte de arriba ↔ capa exterior sí: el segmentador no las
            // distingue. Cambiar un pantalón por unos zapatos, no.
            let torso: Set<GarmentKind> = [.upperBody, .outerLayer]
            if typeKind == kind {
                newSubcategory = type
            } else if allowsKindChange, torso.contains(typeKind), torso.contains(kind) {
                newKind = typeKind
                newSubcategory = type
            }
        }
        let evidence = brandEvidence + page.brandEvidence
        return DetectedGarment(
            kind: newKind,
            confidence: max(confidence, newSubcategory == page.type ? 0.9 : confidence),
            normalized: normalized,
            rawCrop: rawCrop,
            colors: colors,
            featurePrint: featurePrint,
            subcategory: newSubcategory,
            material: page.material ?? material,
            tags: tags,
            seasons: seasons,
            brand: BrandVerdict.resolve(evidence),
            brandEvidence: evidence,
            instanceIndex: instanceIndex,
            sourceRect: sourceRect,
            // El nombre, salvo que el título diga otra prenda que la que es.
            productName: page.type == nil || newSubcategory == page.type ? page.title : nil
        )
    }
}
