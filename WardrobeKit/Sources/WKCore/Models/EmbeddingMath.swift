import Foundation

// Matemática de vectores, en WKCore y no junto al modelo que los produce:
// la usan tanto quien los genera (WKVision) como quien los compara para
// asignar baldas (WKPersistence), y esas dos capas no se conocen entre sí.

/// Utilidades de vectores.
public enum EmbeddingMath {

    /// Producto escalar. Con ambos vectores normalizados, **es** el coseno.
    public static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return -1 }
        var total: Float = 0
        for index in 0..<a.count { total += a[index] * b[index] }
        return total
    }

    /// Media aritmética de un conjunto de ejemplos.
    ///
    /// Se guarda **sin normalizar**, y eso es deliberado: normalizar pierde la
    /// magnitud de la suma, y sin ella la actualización incremental no puede
    /// pesar correctamente lo que ya había frente a lo que llega.
    ///
    /// Para comparar se usa `direction(of:)`, que sí la normaliza. La magnitud
    /// de una media de vectores unitarios nunca pasa de 1, así que cabe de
    /// sobra en Float16.
    public static func mean(of vectors: [[Float]]) -> [Float]? {
        guard let first = vectors.first, !first.isEmpty else { return nil }
        let valid = vectors.filter { $0.count == first.count }
        guard !valid.isEmpty else { return nil }

        var sum = [Float](repeating: 0, count: first.count)
        for vector in valid {
            for index in 0..<vector.count { sum[index] += vector[index] }
        }
        let count = Float(valid.count)
        return sum.map { $0 / count }
    }

    /// Añade un ejemplo a una media sin recalcularla entera.
    ///
    /// Es **exacto**, no una aproximación: `(media·n + v) / (n+1)` es la
    /// definición de la nueva media. Lo que permite que una balda aprenda con
    /// cada prenda nueva sin releer y re-embeber todas las anteriores.
    ///
    /// - Warning: `mean` tiene que ser la media **sin normalizar**. Pasarle una
    ///   dirección ya normalizada hace que el peso de lo anterior sea
    ///   incorrecto, y el centroide **deriva** un poco con cada alta — sin dar
    ///   ningún error y empeorando la clasificación poco a poco.
    public static func updatedMean(
        _ mean: [Float],
        count: Int,
        adding vector: [Float]
    ) -> [Float]? {
        guard mean.count == vector.count, count >= 0 else { return nil }
        let weight = Float(count)
        let total = weight + 1
        var result = [Float](repeating: 0, count: mean.count)
        for index in 0..<mean.count {
            result[index] = (mean[index] * weight + vector[index]) / total
        }
        return result
    }

    /// La dirección de un vector: lo que se compara por coseno.
    public static func direction(of vector: [Float]) -> [Float]? {
        normalized(vector)
    }

    public static func normalized(_ vector: [Float]) -> [Float]? {
        var magnitude: Float = 0
        for value in vector { magnitude += value * value }
        magnitude = magnitude.squareRoot()
        guard magnitude > 1e-6 else { return nil }
        return vector.map { $0 / magnitude }
    }

    /// `[Float]` ↔ `Data` en Float16, que es como se guardan en SwiftData.
    ///
    /// La mitad de bytes, y la pérdida de precisión es irrelevante para un
    /// coseno: los vectores están normalizados y solo importa el orden.
    public static func encode(_ vector: [Float]) -> Data {
        var half = vector.map(Float16.init)
        return Data(bytes: &half, count: half.count * MemoryLayout<Float16>.size)
    }

    public static func decode(_ data: Data) -> [Float] {
        data.withUnsafeBytes { buffer in
            buffer.bindMemory(to: Float16.self).map(Float.init)
        }
    }
}
