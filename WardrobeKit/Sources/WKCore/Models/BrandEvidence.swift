import Foundation

/// Una razón para creer que la prenda es de una marca.
///
/// ## Por qué no basta con un `String?`
///
/// Antes la marca era eso: un nombre o nada. Y con un solo nombre no se puede
/// hacer lo único que importa aquí, que es **no inventarla**. "Zara" leído
/// nítido en una etiqueta y "Zara" adivinado porque el embedding se parece un
/// poco no son la misma afirmación, y guardadas como el mismo `String` acaban
/// las dos en la ficha con la misma cara de certeza.
///
/// Con evidencias, la decisión se toma sumando lo que hay y comparándolo con un
/// listón. Por debajo del listón, `brand` es `nil` — que es una respuesta
/// correcta y además la buena: **"Camiseta negra" es mejor ficha que "Camiseta
/// negra de Zara" cuando no sabemos si es de Zara.**
public struct BrandEvidence: Sendable, Hashable, Codable {

    /// De dónde sale la sospecha.
    public enum Source: String, Sendable, Codable, CaseIterable {
        /// Texto leído en la propia prenda. La más fuerte: cuando acierta, lo
        /// hace con certeza y no con parecido.
        case ocr
        /// Parecido visual contra el banco de términos. Nunca decide sola.
        case embedding
        /// Lo que dijo el resolutor remoto sobre el recorte.
        case remote
        /// Lo escribió el usuario. Manda sobre todo lo demás, siempre.
        case user

        /// Cuánto pesa como mucho esta fuente.
        ///
        /// El techo del embedding está por debajo del listón a propósito: un
        /// parecido visual **nunca** debe bastar por sí solo para escribir una
        /// marca en la ficha. Puede confirmar lo que dijo el OCR; no puede
        /// sustituirlo.
        public var ceiling: Double {
            switch self {
            case .user: 1.0
            case .ocr: 0.9
            case .remote: 0.75
            case .embedding: 0.45
            }
        }
    }

    public let brand: String
    public let source: Source
    /// 0-1, ya acotada al techo de su fuente.
    public let confidence: Double

    public init(brand: String, source: Source, confidence: Double) {
        self.brand = brand
        self.source = source
        self.confidence = min(source.ceiling, max(0, confidence))
    }
}

/// Reúne las evidencias y decide si hay marca que enseñar.
public enum BrandVerdict {

    /// Por debajo de esto no se escribe ninguna marca.
    ///
    /// 0,7 no es un número redondo elegido al azar: deja pasar una lectura
    /// limpia de OCR (0,9) y una lectura con una errata confirmada por el
    /// resolutor remoto, y **no** deja pasar ni un parecido visual solo (0,45)
    /// ni una lectura dudosa sola (0,6).
    public static let displayThreshold = 0.7

    /// La marca que se puede afirmar, o `nil`.
    ///
    /// - Parameter evidence: todo lo que se sabe, sin ordenar.
    public static func resolve(_ evidence: [BrandEvidence]) -> String? {
        guard !evidence.isEmpty else { return nil }

        // Lo que escribe el usuario no se vota: se acata.
        if let byUser = evidence.first(where: { $0.source == .user }) {
            return byUser.brand
        }

        // Dos fuentes distintas que dicen lo mismo valen más que una, pero no
        // la suma de las dos: dos señales del 60% no son una certeza del 120%.
        // Se combinan como probabilidades independientes, que es lo que hace
        // que acumular evidencia floja nunca llegue sola a la certeza.
        var combined: [String: Double] = [:]
        for item in evidence {
            let previous = combined[item.brand] ?? 0
            combined[item.brand] = 1 - (1 - previous) * (1 - item.confidence)
        }

        guard let best = combined.max(by: { $0.value < $1.value }) else { return nil }

        // Y si dos marcas distintas empatan, no hay marca. Es exactamente el
        // caso en que inventarla sale más caro que callarse.
        let contenders = combined.filter { $0.value > best.value - 0.1 }
        guard contenders.count == 1, best.value >= displayThreshold else { return nil }
        return best.key
    }
}
