import CoreGraphics
import Foundation
import WKCore

/// Separa prenda y fondo **por color**, sin modelos.
///
/// ## Qué aporta que no aporten los otros
///
/// El segmentador sabe de ropa y no de esta foto. La máscara de sujeto sabe de
/// objetos y no de ropa. Esto no sabe de nada: mira los colores que hay, dice
/// cuál es el del fondo —el que ocupa el marco— y llama prenda a todo lo demás.
///
/// Suena tosco y es justo lo que hace falta en el caso que peor llevan los
/// otros dos: una prenda sola sobre una superficie lisa. Ahí el fondo es un
/// color y la prenda es otro, y el borde entre los dos es exacto al píxel — sin
/// picos, sin mordiscos y **sin que una doblez cuente como fondo**, porque una
/// doblez sigue sin parecerse a la mesa.
///
/// También contesta una pregunta que los otros contestan mal: **cuántas prendas
/// hay**. Dos manchas separadas de color distinto son dos prendas; dos manchas
/// del mismo color pegadas son una con una sombra en medio.
///
/// ## Dónde encaja
///
/// Como **una técnica más**, no como sustituta. El pipeline genera el recorte
/// por las tres vías y se queda con el que mejor puntúa: ver
/// `CutoutQuality`. Ninguna gana siempre, y elegir midiendo es más barato que
/// acertar adivinando.
public enum ColorSplitter {

    /// Lo que se ha encontrado mirando los colores.
    public struct Split: Sendable {
        /// 1 = prenda.
        public let mask: [UInt8]
        public let width: Int
        public let height: Int
        /// Cuántas manchas grandes hay. Es la respuesta a "¿cuántas prendas?".
        public let pieceCount: Int
        /// Qué fracción de la imagen ocupa lo que no es fondo.
        public let coverage: Double
    }

    /// Cuánto se aleja del fondo un píxel para contar como prenda.
    static let separation = 0.16

    /// Una mancha por debajo de esto es ruido —una migaja, una sombra suelta—
    /// y no cuenta como prenda.
    static let minimumPieceFraction = 0.01

    /// Mira la imagen y la parte en fondo y prenda.
    ///
    /// - Returns: `nil` si el fondo no es un color —una habitación, una calle—
    ///   porque entonces "no ser del color del fondo" no significa nada.
    public static func split(_ image: CGImage) -> Split? {
        let width = image.width
        let height = image.height
        guard
            width > 16, height > 16,
            SolidBackground.isLikely(in: image),
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // El color del fondo: la media del marco. Con fondo liso —que es lo
        // único que llega hasta aquí— la media **es** el color.
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        var samples = 0.0
        let band = max(2, min(width, height) / 25)
        for x in stride(from: 0, to: width, by: 2) {
            for offset in 0..<band {
                for y in [offset, height - 1 - offset] {
                    sum.r += Double(buffer[x, y, 0]) / 255
                    sum.g += Double(buffer[x, y, 1]) / 255
                    sum.b += Double(buffer[x, y, 2]) / 255
                    samples += 1
                }
            }
        }
        guard samples > 32 else { return nil }
        let background = (r: sum.r / samples, g: sum.g / samples, b: sum.b / samples)

        // Todo lo que no es ese color, es prenda.
        var mask = [UInt8](repeating: 0, count: width * height)
        var opaque = 0
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                let dr = Double(buffer[x, y, 0]) / 255 - background.r
                let dg = Double(buffer[x, y, 1]) / 255 - background.g
                let db = Double(buffer[x, y, 2]) / 255 - background.b
                guard (dr * dr + dg * dg + db * db).squareRoot() > separation else { continue }
                mask[row + x] = 1
                opaque += 1
            }
        }

        let total = Double(width * height)
        let coverage = Double(opaque) / total
        // Ni nada ni todo: sin prenda, o con el "fondo" mal elegido.
        guard coverage > 0.02, coverage < 0.92 else { return nil }

        // Se limpia como cualquier otra máscara: las grietas finas se cierran
        // y los agujeros de dentro se rellenan. Ver `Morphology`.
        Morphology.close(&mask, width: width, height: height, radius: 2)
        Morphology.fillHoles(&mask, width: width, height: height)

        let labelled = ConnectedComponents.label(mask: mask, width: width, height: height)
        let floor = Int(total * minimumPieceFraction)
        let pieces = labelled.components.count { $0.pixelCount >= floor }

        DiagnosticsLog.record(
            "RECORTE",
            String(
                format: "por color: %.0f%% de la foto es prenda, en %d pieza(s)",
                coverage * 100, pieces
            )
        )
        return Split(mask: mask, width: width, height: height, pieceCount: pieces, coverage: coverage)
    }

    /// Aplica la máscara a la foto y devuelve la prenda con alfa.
    public static func cutout(_ image: CGImage, using split: Split) -> CGImage? {
        let width = split.width
        let height = split.height
        guard
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        for y in 0..<height {
            let row = y * width
            for x in 0..<width where split.mask[row + x] == 0 {
                for component in 0..<4 { buffer[x, y, component] = 0 }
            }
        }
        return context.makeImage()
    }
}
