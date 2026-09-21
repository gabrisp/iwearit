import Foundation

/// Tabla de prompts ya codificados.
///
/// El codificador de **texto** no viaja al dispositivo: son 19M parámetros que
/// solo harían falta para codificar texto nuevo, y los prompts se conocen de
/// antemano. Se codifican una vez al convertir el modelo y se embarca la tabla:
/// unos cientos de KB en lugar de decenas de MB.
///
/// - Important: los vectores **tienen** que venir del mismo checkpoint que el
///   codificador de imagen. Si se regeneran por separado, los cosenos dejan de
///   significar nada y la clasificación se degrada sin dar ningún error.
public struct PromptBank: Sendable {

    public struct Entry: Sendable, Hashable {
        public let group: String
        /// Clave en español: lo que acaba viendo el usuario.
        public let key: String
        /// `GarmentKind` al que pertenece la subcategoría, si aplica.
        public let kind: GarmentKindName?
    }

    public let dimension: Int
    public let entries: [Entry]
    /// Todos los vectores concatenados, normalizados, en orden de `entries`.
    private let vectors: [Float]

    public init(decoding data: Data) throws {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        dimension = payload.dim
        entries = payload.entries.map {
            Entry(group: $0.group, key: $0.key, kind: $0.kind.flatMap(GarmentKindName.init(rawValue:)))
        }

        guard let raw = Data(base64Encoded: payload.vectorsBase64) else {
            throw PipelineError.maskGenerationFailed
        }
        // Llegan en Float16 para que la tabla ocupe la mitad; se expanden a
        // Float una vez al cargar, porque el producto escalar en Float16 pierde
        // precisión suficiente como para alterar el orden de los resultados.
        vectors = raw.withUnsafeBytes { buffer in
            buffer.bindMemory(to: Float16.self).map(Float.init)
        }
    }

    /// Las mejores coincidencias de un grupo para un embedding dado.
    ///
    /// El embedding de entrada y los del banco están **ambos normalizados**, así
    /// que el producto escalar ya es el coseno: no hace falta dividir por nada.
    public func best(
        group: String,
        for embedding: [Float],
        limit: Int = 1
    ) -> [(entry: Entry, similarity: Float)] {
        guard embedding.count == dimension else { return [] }

        var scored: [(Entry, Float)] = []
        for (index, entry) in entries.enumerated() where entry.group == group {
            let offset = index * dimension
            var total: Float = 0
            for component in 0..<dimension {
                total += vectors[offset + component] * embedding[component]
            }
            scored.append((entry, total))
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { (entry: $0.0, similarity: $0.1) }
    }

    /// La subcategoría más parecida, restringida a un tipo de prenda.
    ///
    /// Restringir importa: sin ello, una camiseta blanca sobre fondo blanco se
    /// parece lo bastante a "a pair of trousers" como para acabar en la balda
    /// equivocada. SegFormer ya nos dijo que es torso; el banco solo elige
    /// **cuál** de las prendas de torso es.
    public func bestSubcategory(
        for embedding: [Float],
        constrainedTo kinds: Set<GarmentKindName>
    ) -> (key: String, kind: GarmentKindName, similarity: Float)? {
        guard embedding.count == dimension else { return nil }

        var best: (String, GarmentKindName, Float)?
        for (index, entry) in entries.enumerated() {
            guard
                entry.group == "subcategory",
                let kind = entry.kind,
                kinds.contains(kind)
            else { continue }

            let offset = index * dimension
            var total: Float = 0
            for component in 0..<dimension {
                total += vectors[offset + component] * embedding[component]
            }
            if best == nil || total > best!.2 {
                best = (entry.key, kind, total)
            }
        }
        guard let best else { return nil }
        return (key: best.0, kind: best.1, similarity: best.2)
    }

    private struct Payload: Decodable {
        let dim: Int
        let entries: [RawEntry]
        let vectorsBase64: String

        struct RawEntry: Decodable {
            let group: String
            let key: String
            let kind: String?
        }
    }
}

/// Nombre de `GarmentKind` tal y como lo escribe el prompt bank.
///
/// Un tipo aparte y no `GarmentKind` directamente para que `WKVision` no
/// dependa del orden en que estén declarados los casos: el banco se genera en
/// Python y solo comparte las cadenas.
public enum GarmentKindName: String, Sendable, Hashable, CaseIterable {
    case upperBody, outerLayer, lowerBody, wholeBody, feet, head, bag, other
}
