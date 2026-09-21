import CoreGraphics
import Foundation
import WKCore

/// Cómo de bien ha salido un recorte, mirándolo.
///
/// ## Para qué
///
/// Para no pagar una reconstrucción que no hace falta. Reconstruir con IA
/// cuesta dinero y segundos por prenda, y **la mayoría de los recortes salen
/// bien**: una prenda sola sobre una superficie lisa la recorta el dispositivo
/// perfectamente. Generar siempre era cobrar por arreglar lo que no estaba
/// roto.
///
/// Lo que sí falla es reconocible sin verlo: la prenda partida en trozos, la
/// que se sale del encuadre, la que ocupa el rectángulo entero —señal de que no
/// se recortó nada— y la que casi no tiene píxeles.
///
/// ## Qué no hace
///
/// No juzga si la prenda es bonita ni si la foto está bien iluminada. Mide
/// **la forma del recorte**, que es lo único que se puede saber sin un modelo
/// y lo único que distingue un recorte roto de uno correcto.
public enum CutoutQuality {

    /// Un recorte por debajo de esto merece reconstruirse.
    ///
    /// Elegido para equivocarse hacia el lado barato: ante la duda **no** se
    /// genera y el usuario tiene el botón para pedirlo. Que sobre un botón es
    /// mejor que cobrar de más.
    public static let acceptable = 0.55

    /// Y por debajo de esto **tampoco se reconstruye**, pero por lo contrario:
    /// no queda prenda suficiente de la que partir.
    ///
    /// Es la diferencia entre una camiseta a la que le falta una manga y una a
    /// la que le faltan las dos. La primera se arregla: el modelo ve el resto
    /// y completa lo que falta. La segunda no se arregla, **se inventa** — y
    /// lo que devuelve es una prenda que no es la tuya, cobrada igual.
    ///
    /// Ahí lo honesto es no gastar y decirlo: con el recorte a mano se
    /// resuelve en dos segundos.
    public static let reconstructible = 0.25

    public struct Report: Sendable {
        /// 0-1.
        public let score: Double
        /// En una línea, para el registro.
        public let summary: String

        public var isGoodEnough: Bool { score >= CutoutQuality.acceptable }

        /// Roto, pero **con arreglo**: falta algo y queda bastante para que la
        /// reconstrucción sepa qué prenda es.
        public var needsReconstruction: Bool {
            !isGoodEnough && score >= CutoutQuality.reconstructible
        }

        /// Tan roto que reconstruirlo sería inventarlo.
        public var isBeyondRepair: Bool { score < CutoutQuality.reconstructible }
    }

    /// Cuánto de lo que se ha quedado dentro **sigue siendo fondo**.
    ///
    /// ## Por qué hace falta además de la forma
    ///
    /// Porque las tres medidas de abajo —cuánto ocupa, si está de una pieza, si
    /// toca el borde— miran la **silueta**, y una silueta puede ser perfecta y
    /// estar mal: un recorte que se ha llevado media mesa junto con la prenda
    /// es una sola mancha, de buen tamaño y sin tocar el canto. Puntúa alto y
    /// es el peor de todos.
    ///
    /// Esto es lo que distingue esos dos casos: si dentro del recorte hay
    /// muchos píxeles del color del fondo, es que el fondo se coló. No mira la
    /// forma, mira el contenido — y son los dos errores distintos que puede
    /// cometer un recorte.
    ///
    /// - Returns: 0 = todo lo que hay dentro es prenda. 1 = todo es fondo.
    public static func contamination(
        of cutout: CGImage,
        backgroundOf original: CGImage
    ) -> Double {
        guard
            let background = averageBorderColor(of: original),
            let buffer = PixelBuffer(width: cutout.width, height: cutout.height),
            let context = buffer.makeContext()
        else { return 0 }
        context.draw(cutout, in: CGRect(x: 0, y: 0, width: cutout.width, height: cutout.height))

        var opaque = 0
        var looksLikeBackground = 0
        for y in 0..<cutout.height {
            for x in 0..<cutout.width where buffer[x, y, 3] > 200 {
                opaque += 1
                // Premultiplicado y opaco: el color se lee tal cual.
                let dr = Double(buffer[x, y, 0]) / 255 - background.r
                let dg = Double(buffer[x, y, 1]) / 255 - background.g
                let db = Double(buffer[x, y, 2]) / 255 - background.b
                if (dr * dr + dg * dg + db * db).squareRoot() < ColorSplitter.separation {
                    looksLikeBackground += 1
                }
            }
        }
        guard opaque > 0 else { return 0 }
        return Double(looksLikeBackground) / Double(opaque)
    }

    /// El color del marco, que sobre fondo liso **es** el color del fondo.
    private static func averageBorderColor(
        of image: CGImage
    ) -> (r: Double, g: Double, b: Double)? {
        let width = image.width
        let height = image.height
        guard
            width > 8, height > 8,
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var sum = (r: 0.0, g: 0.0, b: 0.0)
        var count = 0.0
        let band = max(2, min(width, height) / 25)
        for x in stride(from: 0, to: width, by: 2) {
            for offset in 0..<band {
                for y in [offset, height - 1 - offset] {
                    sum.r += Double(buffer[x, y, 0]) / 255
                    sum.g += Double(buffer[x, y, 1]) / 255
                    sum.b += Double(buffer[x, y, 2]) / 255
                    count += 1
                }
            }
        }
        guard count > 16 else { return nil }
        return (sum.r / count, sum.g / count, sum.b / count)
    }

    /// Mide el recorte.
    ///
    /// Tres cosas, todas sobre el canal alfa:
    ///
    /// 1. **Cuánto ocupa.** Un recorte con el 2% de píxeles opacos no es una
    ///    prenda; uno con el 98% es el rectángulo entero, o sea, no se recortó.
    /// 2. **Si está de una pieza.** La mancha mayor tiene que ser casi todo lo
    ///    opaco. Cuando el segmentador parte un pantalón por el cinturón, salen
    ///    dos manchas del mismo tamaño y eso se ve aquí.
    /// 3. **Si toca el borde.** Una prenda cortada por el encuadre está
    ///    incompleta, y eso la reconstrucción sí lo arregla.
    public static func assess(_ image: CGImage) -> Report {
        let width = image.width
        let height = image.height
        guard
            width > 0, height > 0,
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else {
            return Report(score: 0, summary: "no se pudo leer el recorte")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var mask = [UInt8](repeating: 0, count: width * height)
        var opaque = 0
        var touchesEdge = false
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where buffer[x, y, 3] > 40 {
                mask[row + x] = 1
                opaque += 1
                if x == 0 || y == 0 || x == width - 1 || y == height - 1 { touchesEdge = true }
            }
        }

        let total = Double(width * height)
        let coverage = Double(opaque) / total
        guard opaque > 0 else {
            return Report(score: 0, summary: "el recorte salió vacío")
        }

        let labelled = ConnectedComponents.label(mask: mask, width: width, height: height)
        let largest = labelled.components.map(\.pixelCount).max() ?? 0
        let wholeness = Double(largest) / Double(opaque)

        // La cobertura buena está en la banda ancha del medio. Fuera de ella
        // —casi nada, o casi todo— el recorte no hizo su trabajo.
        let coverageScore: Double = switch coverage {
        case ..<0.04: 0
        case ..<0.12: 0.5
        case ...0.85: 1
        case ...0.95: 0.4
        default: 0
        }

        // **La unidad pesa y además es una rampa empinada.**
        //
        // Lineal no servía: una prenda partida limpiamente en dos da 0,5 de
        // unidad, que con un peso lineal todavía aprobaba. Y 0,5 es justo el
        // caso que hay que reconstruir —el pantalón cortado por el cinturón—.
        // Una prenda de verdad llega a 0,95; por debajo de 0,6 no es una
        // prenda, son trozos.
        let wholenessScore = min(1, max(0, (wholeness - 0.6) / 0.35))

        var score = coverageScore * 0.3 + wholenessScore * 0.6
        if !touchesEdge { score += 0.1 }

        let summary = String(
            format: "ocupa %.0f%%, entera %.0f%%%@",
            coverage * 100,
            wholeness * 100,
            touchesEdge ? ", toca el borde" : ""
        )
        return Report(score: min(1, score), summary: summary)
    }
}
