import Foundation

/// Decide si dos prendas son **la misma**.
///
/// ## Qué problema resuelve
///
/// Importar la misma camiseta dos veces —desde dos fotos distintas, o porque el
/// guardado falló y se repitió— deja dos entradas idénticas en el armario. Y no
/// molestan solo por ocupar sitio: rompen todo lo que cuenta. "Tienes 3 tops"
/// cuando tienes uno, dos filas iguales en el selector de prendas sin forma de
/// saber cuál tocar, y un contador de veces puestas repartido entre las dos.
///
/// La comparación es por **embedding**, no por imagen: dos fotos de la misma
/// camiseta no comparten ni un píxel —otra luz, otro ángulo, otro recorte— pero
/// sí caen casi en el mismo punto del espacio del embedder.
public enum DuplicateDetector {

    /// Por encima de este coseno, es la misma prenda.
    ///
    /// **Alto a propósito.** Dos camisetas negras lisas de marcas distintas
    /// pasan de 0,85 sin ser la misma, y fundirlas sería perder una prenda que
    /// el usuario tiene de verdad. Equivocarse hacia el otro lado cuesta mucho
    /// menos: un duplicado que se cuela se borra en dos toques, y además esto
    /// nunca decide solo — marca el candidato y deja la última palabra al
    /// usuario en la pantalla de revisión.
    public static let threshold: Float = 0.93

    /// Una prenda ya guardada contra la que comparar.
    public struct Known: Sendable {
        public let id: PersistentIdentifierBox
        public let name: String
        public let embedding: Data

        public init(id: PersistentIdentifierBox, name: String, embedding: Data) {
            self.id = id
            self.name = name
            self.embedding = embedding
        }
    }

    /// Lo que se encontró.
    public struct Match: Sendable {
        public let known: Known
        public let similarity: Float
    }

    /// Busca la prenda ya guardada que más se parece, si pasa el listón.
    ///
    /// - Parameter embedding: el de la prenda nueva. `nil` —sin embedder
    ///   cargado— devuelve `nil`: **sin vector no se compara nada**. Adivinar
    ///   duplicados por nombre o por color sería descartar prendas distintas
    ///   que resultan llamarse igual.
    public static func match(for embedding: Data?, among known: [Known]) -> Match? {
        guard
            let embedding,
            let direction = EmbeddingMath.direction(of: EmbeddingMath.decode(embedding))
        else { return nil }

        var best: Match?
        for candidate in known {
            // **Solo contra vectores del mismo espacio.**
            //
            // El embedding viene de TinyCLIP si el modelo está y de
            // `VNGenerateImageFeaturePrint` si no, y los dos espacios no son
            // comparables: un coseno alto entre ellos no significa nada. Se
            // distinguen por tamaño, que es la única marca que llevan encima.
            guard
                candidate.embedding.count == embedding.count,
                let other = EmbeddingMath.direction(of: EmbeddingMath.decode(candidate.embedding))
            else { continue }

            let similarity = EmbeddingMath.similarity(direction, other)
            guard similarity >= threshold else { continue }
            if similarity > (best?.similarity ?? -1) {
                best = Match(known: candidate, similarity: similarity)
            }
        }
        return best
    }

    /// Duplicados **dentro de la misma importación**.
    ///
    /// Pasa de verdad: una foto con la persona de frente y de lado, o una
    /// prenda que el segmentador partió y volvió a juntar en dos instancias
    /// casi iguales. Devuelve los índices que sobran, para poder desmarcarlos
    /// sin reordenar nada.
    ///
    /// Se queda siempre con el **primero**, que es el de más arriba en la foto
    /// y el que el usuario ve primero en la lista.
    public static func redundantIndices(in embeddings: [Data?]) -> Set<Int> {
        var redundant: Set<Int> = []
        for index in embeddings.indices {
            guard
                !redundant.contains(index),
                let data = embeddings[index],
                let direction = EmbeddingMath.direction(of: EmbeddingMath.decode(data))
            else { continue }

            for other in (index + 1)..<embeddings.count {
                guard
                    !redundant.contains(other),
                    let otherData = embeddings[other],
                    otherData.count == data.count,
                    let otherDirection = EmbeddingMath.direction(
                        of: EmbeddingMath.decode(otherData)
                    )
                else { continue }
                if EmbeddingMath.similarity(direction, otherDirection) >= threshold {
                    redundant.insert(other)
                }
            }
        }
        return redundant
    }
}

/// Un `PersistentIdentifier` que cruza actores sin arrastrar SwiftData.
///
/// `WKCore` no depende de SwiftData —ni debe—, y sin embargo lo que identifica
/// a una prenda guardada es su `PersistentIdentifier`. La caja lo transporta
/// como lo que es aquí: un valor opaco que solo significa algo al otro lado.
public struct PersistentIdentifierBox: @unchecked Sendable, Hashable {
    /// `AnyHashable` no es `Sendable` porque puede envolver cualquier cosa. Lo
    /// que entra aquí sí lo es —lo exige el `init`— y una vez dentro es
    /// inmutable, así que cruzar con él es seguro. La alternativa sería hacer
    /// genérico todo lo que lo toca para transportar un valor opaco.
    public let raw: AnyHashable

    public init(_ raw: some Hashable & Sendable) {
        self.raw = AnyHashable(raw)
    }
}
