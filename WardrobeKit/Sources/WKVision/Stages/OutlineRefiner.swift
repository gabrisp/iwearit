import CoreGraphics
import Foundation
import WKCore

/// Lleva el borde del recorte hasta donde de verdad acaba la prenda.
///
/// ## El problema, dicho en corto
///
/// El segmentador decide clase por clase: cada píxel es "pantalón", "camiseta"
/// o "fondo". Y una **doblez** cambia el color lo suficiente como para que esa
/// franja salga con otra clase — o con ninguna. El resultado es un pantalón con
/// una grieta en medio, o con un pico mordido en el bajo.
///
/// Pero mirándolo como lo mirarías tú, no hay ninguna duda: **la doblez sigue
/// estando dentro del contorno del pantalón**. Lo que separa la prenda del
/// mundo no es el cambio de clase, es el cambio de color contra el fondo.
///
/// ## Cómo se aprovecha eso
///
/// En tres pasos, y ninguno necesita un modelo:
///
/// 1. **Qué color tiene el fondo.** Se mide en el marco de la imagen, lejos de
///    la prenda. Sobre fondo liso —una mesa, una cama, una pared— es un color
///    con muy poca variación.
/// 2. **Qué píxeles no son fondo.** Todo lo que se aleje de ese color.
/// 3. **Cuáles de esos tocan a la prenda.** Se crece desde la máscara que ya
///    había, pasando solo por píxeles que no son fondo. Una doblez está pegada
///    a la tela y no es fondo, así que entra. La mesa que se ve entre las dos
///    perneras es fondo, así que no.
///
/// Es la idea de GrabCut sin el coste de GrabCut: un modelo de color del fondo
/// y conectividad, que es lo único que hace falta cuando el fondo es liso.
///
/// ## Cuándo **no** usarlo
///
/// Con el fondo lleno de cosas. Ahí "no ser del color del fondo" no significa
/// nada —el sofá tampoco lo es— y crecer por conectividad se comería media
/// habitación. Ver `SolidBackground`.
public enum OutlineRefiner {

    /// Cuánto se tiene que alejar un píxel del color del fondo para contarlo
    /// como prenda. Distancia euclídea en RGB 0-1.
    ///
    /// Bajo a propósito: lo que se persigue son dobleces y sombras de la propia
    /// tela, que se parecen **al fondo** mucho menos de lo que se parecen entre
    /// sí. Subirlo empieza a dejar fuera prendas blancas sobre mesa blanca.
    static let separation = 0.14

    /// Hasta dónde puede crecer, en píxeles.
    ///
    /// Un tope, no una expectativa. Sin él, una prenda que toca una sombra
    /// larga se lleva la sombra entera; con él, lo peor que puede pasar es un
    /// reborde de este grosor.
    public static let maximumGrowth = 40

    /// Crece la máscara hasta el contorno real de la prenda.
    ///
    /// - Parameters:
    ///   - mask: 1 = prenda. Se modifica.
    ///   - image: la foto, del mismo tamaño que la máscara.
    /// - Returns: cuántos píxeles se añadieron. Cero si no había nada que
    ///   hacer o si el fondo no es utilizable.
    @discardableResult
    public static func refine(
        _ mask: inout [UInt8],
        in image: CGImage,
        width: Int,
        height: Int,
        maximumGrowth: Int = OutlineRefiner.maximumGrowth
    ) -> Int {
        guard
            width > 8, height > 8,
            mask.count == width * height,
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // --- 1. El color del fondo, medido en el marco y fuera de la prenda ---
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        var count = 0.0
        let band = max(2, min(width, height) / 25)

        func consider(_ x: Int, _ y: Int) {
            guard mask[y * width + x] == 0 else { return }
            sum.r += Double(buffer[x, y, 0]) / 255
            sum.g += Double(buffer[x, y, 1]) / 255
            sum.b += Double(buffer[x, y, 2]) / 255
            count += 1
        }

        for x in stride(from: 0, to: width, by: 2) {
            for offset in 0..<band {
                consider(x, offset)
                consider(x, height - 1 - offset)
            }
        }
        for y in stride(from: 0, to: height, by: 2) {
            for offset in 0..<band {
                consider(offset, y)
                consider(width - 1 - offset, y)
            }
        }
        guard count > 32 else { return 0 }
        let background = (r: sum.r / count, g: sum.g / count, b: sum.b / count)

        // --- 2 y 3. Crecer desde la prenda, solo por lo que no es fondo ---
        func isGarmentColoured(_ x: Int, _ y: Int) -> Bool {
            let dr = Double(buffer[x, y, 0]) / 255 - background.r
            let dg = Double(buffer[x, y, 1]) / 255 - background.g
            let db = Double(buffer[x, y, 2]) / 255 - background.b
            return (dr * dr + dg * dg + db * db).squareRoot() > separation
        }

        var distance = [Int16](repeating: -1, count: width * height)
        var frontier: [Int] = []
        for index in 0..<(width * height) where mask[index] == 1 {
            distance[index] = 0
            frontier.append(index)
        }
        guard !frontier.isEmpty else { return 0 }

        var added = 0
        var next: [Int] = []
        var step = 0
        while !frontier.isEmpty, step < maximumGrowth {
            step += 1
            next.removeAll(keepingCapacity: true)

            for index in frontier {
                let x = index % width
                let y = index / width

                func visit(_ nx: Int, _ ny: Int) {
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { return }
                    let neighbour = ny * width + nx
                    guard distance[neighbour] < 0, isGarmentColoured(nx, ny) else { return }
                    distance[neighbour] = Int16(step)
                    mask[neighbour] = 1
                    added += 1
                    next.append(neighbour)
                }

                visit(x - 1, y)
                visit(x + 1, y)
                visit(x, y - 1)
                visit(x, y + 1)
            }
            swap(&frontier, &next)
        }

        if added > 0 {
            DiagnosticsLog.record(
                "RECORTE",
                "contorno ampliado por contraste: \(added) píxeles"
            )
        }
        return added
    }
}
