import CoreGraphics
import Foundation

/// Etiquetado de componentes conexas con 4-conectividad.
///
/// Estaba escondido dentro de `CropNormalizer`, donde servía para una sola cosa:
/// decidir qué manchas de una máscara eran basura. Sacarlo aquí resuelve además
/// el problema que impedía separar dos prendas de la misma clase.
///
/// **Por qué hace falta.** SegFormer devuelve un mapa *semántico*: dice de cada
/// píxel "esto es upper-clothes", no "esta es la primera camiseta y esta la
/// segunda". Dos camisetas dobladas sobre la cama comparten clase, así que la
/// caja que las contiene a las dos es una sola y el armario se queda con una
/// prenda donde había dos. Lo único que las distingue es que sus píxeles **no
/// se tocan**, y eso es exactamente lo que mide esto.
///
/// 4-conectividad y no 8: en diagonal, dos prendas que apenas se rozan por una
/// esquina se fusionan, y en una máscara con el borde dentado eso pasa a
/// menudo.
struct ConnectedComponents {

    /// Una mancha conexa, con todo lo que hace falta saber de ella sin volver a
    /// recorrer la retícula.
    struct Component {
        /// Empieza en 1. El 0 está reservado para "fuera de la máscara".
        let label: Int32
        let pixelCount: Int
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int
        /// Momentos de primer orden, acumulados durante el etiquetado. Medirlos
        /// después sería recorrer los mismos píxeles una segunda vez para saber
        /// algo que ya estaba delante.
        let sumX: Double
        let sumY: Double

        var bounds: CGRect {
            CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
    }

    /// Etiqueta por píxel. 0 = fuera de la máscara.
    let labels: [Int32]
    let width: Int
    let height: Int
    /// En orden de etiqueta: `components[i].label == Int32(i + 1)`.
    let components: [Component]

    /// - Parameter mask: 1 donde el píxel pertenece a la máscara, 0 fuera.
    ///   Un array de bytes y no un cierre por píxel a propósito: llamar a un
    ///   cierre un millón de veces cuesta más que la comprobación que hace.
    static func label(mask: [UInt8], width: Int, height: Int) -> ConnectedComponents {
        guard width > 0, height > 0, mask.count >= width * height else {
            return ConnectedComponents(labels: [], width: 0, height: 0, components: [])
        }

        var labels = [Int32](repeating: 0, count: width * height)
        var components: [Component] = []
        var stack: [Int] = []
        stack.reserveCapacity(width * height / 4)
        var current: Int32 = 0

        for start in 0..<(width * height) {
            guard labels[start] == 0, mask[start] != 0 else { continue }

            current += 1
            labels[start] = current
            stack.append(start)

            var pixelCount = 0
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            var sumX = 0.0, sumY = 0.0

            while let index = stack.popLast() {
                let x = index % width
                let y = index / width
                pixelCount += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
                sumX += Double(x)
                sumY += Double(y)

                // Vecinos escritos a mano y no recorriendo una lista de pares:
                // un literal de array dentro del bucle es **una reserva de
                // memoria por píxel**, que con un millón de píxeles es el coste
                // dominante de toda la etapa.
                if x + 1 < width, labels[index + 1] == 0, mask[index + 1] != 0 {
                    labels[index + 1] = current
                    stack.append(index + 1)
                }
                if x > 0, labels[index - 1] == 0, mask[index - 1] != 0 {
                    labels[index - 1] = current
                    stack.append(index - 1)
                }
                if y + 1 < height, labels[index + width] == 0, mask[index + width] != 0 {
                    labels[index + width] = current
                    stack.append(index + width)
                }
                if y > 0, labels[index - width] == 0, mask[index - width] != 0 {
                    labels[index - width] = current
                    stack.append(index - width)
                }
            }

            components.append(
                Component(
                    label: current,
                    pixelCount: pixelCount,
                    minX: minX, minY: minY, maxX: maxX, maxY: maxY,
                    sumX: sumX, sumY: sumY
                )
            )
        }

        return ConnectedComponents(
            labels: labels, width: width, height: height, components: components
        )
    }
}
