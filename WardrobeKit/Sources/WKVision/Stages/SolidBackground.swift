import CoreGraphics
import Foundation
import WKCore

/// Si la foto está hecha contra un fondo liso.
///
/// ## Por qué importa
///
/// Porque cambia cuál es la mejor herramienta. El segmentador de ropa está
/// entrenado con **gente vestida**: sabe muchísimo de dónde acaba una camiseta
/// y empieza un pantalón, y bastante menos de una camiseta tirada sobre una
/// mesa. En esas fotos encuentra la prenda —dice bien qué es— pero el contorno
/// le sale mordido.
///
/// Y justo ahí, levantar el sujeto de Vision es casi perfecto: un objeto, fondo
/// liso, buena luz es su caso ideal. Lo que no sabe es **qué** ha levantado.
///
/// Reconocer el fondo liso permite usar cada cosa para lo que es buena: el
/// segmentador dice qué prenda es, y la máscara de sujeto dice dónde está.
public enum SolidBackground {

    /// Cuánto puede variar el color del borde y seguir siendo "liso".
    ///
    /// Sobre 0-1 por canal. Generoso: un fondo de pared tiene degradado de luz
    /// y una mesa de madera tiene veta, y los dos cuentan como lisos para lo
    /// que hace falta decidir aquí.
    static let tolerance = 0.12

    /// Mira **el marco** de la imagen, no la imagen entera.
    ///
    /// El borde es fondo casi por definición: la prenda está en el medio. Y
    /// mirar solo el marco cuesta una fracción de lo que costaría recorrerlo
    /// todo — son unos miles de píxeles frente a un millón.
    public static func isLikely(in image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        guard width > 8, height > 8 else { return false }

        guard
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Una banda del 4% por cada lado, muestreada. Más fina se queda corta
        // en una foto con marco oscuro de lente; más gruesa empieza a coger
        // prenda.
        let band = max(2, min(width, height) / 25)
        let step = max(1, min(width, height) / 120)

        var samples: [(r: Double, g: Double, b: Double)] = []
        samples.reserveCapacity(4 * (width + height) / step)

        func sample(_ x: Int, _ y: Int) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            samples.append((
                Double(buffer[x, y, 0]) / 255,
                Double(buffer[x, y, 1]) / 255,
                Double(buffer[x, y, 2]) / 255
            ))
        }

        for x in stride(from: 0, to: width, by: step) {
            for offset in stride(from: 0, to: band, by: max(1, band / 3)) {
                sample(x, offset)
                sample(x, height - 1 - offset)
            }
        }
        for y in stride(from: 0, to: height, by: step) {
            for offset in stride(from: 0, to: band, by: max(1, band / 3)) {
                sample(offset, y)
                sample(width - 1 - offset, y)
            }
        }
        guard samples.count > 16 else { return false }

        let count = Double(samples.count)
        let mean = samples.reduce(into: (r: 0.0, g: 0.0, b: 0.0)) { total, pixel in
            total.r += pixel.r / count
            total.g += pixel.g / count
            total.b += pixel.b / count
        }

        // Desviación típica por canal. Con la media sola no basta: un fondo
        // mitad blanco y mitad negro tiene una media gris perfectamente
        // plausible.
        var variance = (r: 0.0, g: 0.0, b: 0.0)
        for pixel in samples {
            variance.r += (pixel.r - mean.r) * (pixel.r - mean.r) / count
            variance.g += (pixel.g - mean.g) * (pixel.g - mean.g) / count
            variance.b += (pixel.b - mean.b) * (pixel.b - mean.b) / count
        }
        let deviation = max(
            variance.r.squareRoot(),
            max(variance.g.squareRoot(), variance.b.squareRoot())
        )

        let isSolid = deviation <= tolerance
        DiagnosticsLog.record(
            "PIPELINE",
            String(format: "fondo %@ (variación %.3f)", isSolid ? "liso" : "con cosas", deviation)
        )
        return isSolid
    }
}
