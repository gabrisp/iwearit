import Foundation
import Testing
@testable import WKCore

private func unit(_ values: [Float]) -> [Float] {
    EmbeddingMath.normalized(values) ?? values
}

@Suite("Matemática de embeddings")
struct EmbeddingMathTests {

    @Test("Un vector normalizado tiene módulo 1")
    func normalizationGivesUnitLength() throws {
        let vector = try #require(EmbeddingMath.normalized([3, 4, 0]))
        let magnitude = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()

        #expect(abs(magnitude - 1) < 1e-6)
        #expect(abs(vector[0] - 0.6) < 1e-6)
    }

    @Test("El vector cero no se puede normalizar")
    func zeroVectorIsRejected() {
        #expect(EmbeddingMath.normalized([0, 0, 0]) == nil)
    }

    /// Con ambos normalizados, el producto escalar **es** el coseno: 1 para
    /// idénticos, 0 para ortogonales.
    @Test("La similitud se comporta como un coseno")
    func similarityBehavesLikeCosine() {
        let a = unit([1, 0, 0])
        let b = unit([0, 1, 0])

        #expect(abs(EmbeddingMath.similarity(a, a) - 1) < 1e-6)
        #expect(abs(EmbeddingMath.similarity(a, b)) < 1e-6)
        #expect(EmbeddingMath.similarity(a, unit([1, 1, 0])) > 0.7)
    }

    @Test("Vectores de distinta longitud no son comparables")
    func mismatchedLengthsAreNotSimilar() {
        #expect(EmbeddingMath.similarity([1, 0], [1, 0, 0]) == -1)
    }

    /// Es lo que convierte "enséñame cuáles van aquí" en un clasificador.
    @Test("La media cae entre sus ejemplos")
    func meanSitsBetweenExamples() throws {
        let centre = try #require(EmbeddingMath.mean(of: [unit([1, 0, 0]), unit([0, 1, 0])]))

        #expect(abs(centre[0] - centre[1]) < 1e-6, "equidistante de ambos")
        #expect(abs(centre[2]) < 1e-6)
        #expect(abs(centre[0] - 0.5) < 1e-6, "es la media, no la dirección")
    }

    /// Lo que permite que una balda aprenda con cada prenda nueva sin releer y
    /// re-embeber todas las anteriores. Si esta equivalencia no se cumpliera,
    /// el centroide iría derivando y nadie se daría cuenta.
    @Test("Actualizar el centroide equivale a recalcularlo entero")
    func incrementalUpdateMatchesFullRecompute() throws {
        let members = [unit([1, 0.2, 0]), unit([0.9, 0.1, 0.1]), unit([0.8, 0.3, 0])]
        let newcomer = unit([0.7, 0.4, 0.1])

        let before = try #require(EmbeddingMath.mean(of: members))
        let incremental = try #require(
            EmbeddingMath.updatedMean(before, count: members.count, adding: newcomer)
        )
        let recomputed = try #require(EmbeddingMath.mean(of: members + [newcomer]))

        // Exacto, no aproximado: la fórmula **es** la definición de la media.
        for index in 0..<incremental.count {
            #expect(abs(incremental[index] - recomputed[index]) < 1e-6)
        }
    }

    /// Se guardan en Float16 para ocupar la mitad. La pérdida es irrelevante
    /// para un coseno —solo importa el orden— pero conviene acotarla.
    @Test("El round-trip a Float16 conserva la similitud")
    func float16RoundTripPreservesSimilarity() {
        let original = unit((0..<512).map { Float($0 % 17) - 8 })
        let restored = EmbeddingMath.decode(EmbeddingMath.encode(original))

        #expect(restored.count == original.count)
        #expect(EmbeddingMath.similarity(original, restored) > 0.9999)
    }
}
