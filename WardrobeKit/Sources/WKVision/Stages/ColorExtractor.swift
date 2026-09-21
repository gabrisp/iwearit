import CoreGraphics
import Foundation
import WKCore

/// Saca los colores dominantes de una prenda ya recortada.
///
/// No hace falta ningún modelo: poner nombre a un RGB es una búsqueda por
/// cercanía en un espacio perceptual, no una tarea de IA. Se agrupa en **Lab**
/// y no en RGB porque en RGB la distancia euclídea no se parece a lo que el ojo
/// considera "parecido": un azul marino y un negro están cerca en RGB y son
/// colores distintos para cualquiera.
public enum ColorExtractor {

    /// Solo cuentan los píxeles claramente opacos: los del borde están
    /// mezclados con el fondo y contaminan la media.
    static let alphaThreshold: UInt8 = 200

    public static func dominantColors(in image: CGImage, count: Int = 3) -> [NamedColor] {
        let samples = sampleLab(image)
        guard !samples.isEmpty else { return [] }

        let clusters = kMeans(samples, k: min(count, max(1, samples.count / 64)))
        let total = clusters.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }

        return clusters
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
            .map { cluster in
                let rgb = labToRGB(cluster.center)
                return NamedColor(
                    nameKey: NamedColorTable.closestName(toLab: cluster.center),
                    red: rgb.0, green: rgb.1, blue: rgb.2,
                    weight: Double(cluster.count) / Double(total)
                )
            }
    }

    // MARK: - Muestreo

    /// Submuestrea a como mucho ~10.000 píxeles. Durante el escaneo masivo esto
    /// corre miles de veces, y leer cada píxel de una imagen de 768² sería el
    /// tramo más caro de una etapa que debería ser gratis.
    private static func sampleLab(_ image: CGImage) -> [SIMD3<Double>] {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }

        guard
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let stride = max(1, Int((Double(width * height) / 10_000).squareRoot().rounded()))
        var samples: [SIMD3<Double>] = []
        samples.reserveCapacity(10_000)

        for y in Swift.stride(from: 0, to: height, by: stride) {
            for x in Swift.stride(from: 0, to: width, by: stride) {
                let alpha = buffer[x, y, 3]
                guard alpha >= alphaThreshold else { continue }
                // Premultiplicado: hay que deshacerlo antes de mirar el color.
                let a = Double(alpha) / 255
                samples.append(rgbToLab(
                    Double(buffer[x, y, 0]) / 255 / a,
                    Double(buffer[x, y, 1]) / 255 / a,
                    Double(buffer[x, y, 2]) / 255 / a
                ))
            }
        }
        return samples
    }

    // MARK: - k-means

    struct Cluster {
        var center: SIMD3<Double>
        var count: Int
    }

    static func kMeans(_ samples: [SIMD3<Double>], k: Int, iterations: Int = 8) -> [Cluster] {
        guard !samples.isEmpty, k > 0 else { return [] }
        let k = min(k, samples.count)

        // Siembra determinista y repartida: sin `random`, para que la misma
        // imagen dé siempre los mismos colores. Un nombre de prenda que cambia
        // entre ejecuciones es un bug que nadie sabe reproducir.
        var centers = (0..<k).map { samples[$0 * samples.count / k] }
        var assignment = [Int](repeating: 0, count: samples.count)

        for _ in 0..<iterations {
            var moved = false
            for (index, sample) in samples.enumerated() {
                var best = 0
                var bestDistance = Double.infinity
                for (c, center) in centers.enumerated() {
                    let delta = sample - center
                    let distance = (delta * delta).sum()
                    if distance < bestDistance {
                        bestDistance = distance
                        best = c
                    }
                }
                if assignment[index] != best {
                    assignment[index] = best
                    moved = true
                }
            }

            var sums = [SIMD3<Double>](repeating: .zero, count: k)
            var counts = [Int](repeating: 0, count: k)
            for (index, sample) in samples.enumerated() {
                sums[assignment[index]] += sample
                counts[assignment[index]] += 1
            }
            for c in 0..<k where counts[c] > 0 {
                centers[c] = sums[c] / Double(counts[c])
            }
            if !moved { break }
        }

        var counts = [Int](repeating: 0, count: k)
        for index in assignment { counts[index] += 1 }
        return (0..<k).map { Cluster(center: centers[$0], count: counts[$0]) }
    }

    // MARK: - Espacios de color

    static func rgbToLab(_ r: Double, _ g: Double, _ b: Double) -> SIMD3<Double> {
        func linear(_ c: Double) -> Double {
            let c = min(max(c, 0), 1)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let (lr, lg, lb) = (linear(r), linear(g), linear(b))

        // sRGB D65
        let x = (0.4124 * lr + 0.3576 * lg + 0.1805 * lb) / 0.95047
        let y = (0.2126 * lr + 0.7152 * lg + 0.0722 * lb)
        let z = (0.0193 * lr + 0.1192 * lg + 0.9505 * lb) / 1.08883

        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3) : (7.787 * t + 16.0 / 116)
        }
        let (fx, fy, fz) = (f(x), f(y), f(z))
        return SIMD3(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    static func labToRGB(_ lab: SIMD3<Double>) -> (Double, Double, Double) {
        let fy = (lab.x + 16) / 116
        let fx = fy + lab.y / 500
        let fz = fy - lab.z / 200

        func invF(_ t: Double) -> Double {
            let cube = t * t * t
            return cube > 0.008856 ? cube : (t - 16.0 / 116) / 7.787
        }
        let x = invF(fx) * 0.95047
        let y = invF(fy)
        let z = invF(fz) * 1.08883

        let lr =  3.2406 * x - 1.5372 * y - 0.4986 * z
        let lg = -0.9689 * x + 1.8758 * y + 0.0415 * z
        let lb =  0.0557 * x - 0.2040 * y + 1.0570 * z

        func gamma(_ c: Double) -> Double {
            let c = min(max(c, 0), 1)
            return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        return (gamma(lr), gamma(lg), gamma(lb))
    }
}
