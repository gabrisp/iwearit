import CoreGraphics
import Foundation

/// **La forma de un recorte**: si parece una prenda o un trozo de foto.
///
/// Las fotos del escaneo son de cámara, imperfectas: una prenda de verdad sale
/// siempre de la silueta de la persona, con bordes irregulares —mangas,
/// cuellos, perneras—. Un recorte que es un rectángulo o un cuadrado perfecto
/// no es una prenda: es un pedazo de foto que la segmentación no supo
/// separar, con fondo, cara o piel dentro. Ninguno de esos debe llegar al
/// armario.
public enum CutoutShape {

    /// Lo que mide la forma de un recorte.
    public struct Measure: Sendable {
        /// Lo opaco sobre el área de su caja, 0-1. Una camiseta ronda 0,7; un
        /// rectángulo, 1.
        public let fill: Double
        /// Cuántos lados de la caja son una línea recta opaca de punta a
        /// punta. Una prenda tiene como mucho uno —la cintura de un pantalón—;
        /// un trozo de foto, tres o cuatro.
        public let straightEdges: Int
    }

    /// Mide un recorte con alfa, reducido a 64 px para que sea barato.
    public static func measure(_ image: CGImage) -> Measure? {
        let side = 64
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Con su proporción, centrado: la caja se calcula sobre lo opaco.
        let scale = Double(side) / Double(max(image.width, image.height))
        let width = Double(image.width) * scale
        let height = Double(image.height) * scale
        context.draw(image, in: CGRect(x: (Double(side) - width) / 2, y: (Double(side) - height) / 2, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        func isOpaque(_ x: Int, _ y: Int) -> Bool { data[(y * side + x) * 4 + 3] > 40 }

        var minX = side, minY = side, maxX = -1, maxY = -1, opaque = 0
        for y in 0..<side {
            for x in 0..<side where isOpaque(x, y) {
                opaque += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let boxWidth = maxX - minX + 1
        let boxHeight = maxY - minY + 1
        let fill = Double(opaque) / Double(boxWidth * boxHeight)

        // Un lado es recto si casi todo él es opaco: la prenda llega al borde
        // de su caja de punta a punta, como un corte de tijera.
        func share(_ points: [(Int, Int)]) -> Double {
            Double(points.filter { isOpaque($0.0, $0.1) }.count) / Double(max(1, points.count))
        }
        let edges = [
            share((minX...maxX).map { ($0, minY) }),
            share((minX...maxX).map { ($0, maxY) }),
            share((minY...maxY).map { (minX, $0) }),
            share((minY...maxY).map { (maxX, $0) }),
        ]
        return Measure(fill: fill, straightEdges: edges.filter { $0 > 0.85 }.count)
    }

    /// **Si es un rectángulo** —y por tanto no una prenda—: casi toda la caja
    /// llena, o dos o más lados rectos con la caja bastante llena.
    public static func isRectangular(_ image: CGImage) -> Bool {
        guard let measure = measure(image) else { return true }
        return measure.fill > 0.95 || (measure.straightEdges >= 2 && measure.fill > 0.72)
    }
}
