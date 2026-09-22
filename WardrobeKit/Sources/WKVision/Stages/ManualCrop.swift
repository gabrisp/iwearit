import CoreGraphics
import Foundation
import WKCore

/// Recortar a dedo: lo que quede dentro del trazo se queda, lo demás se va.
///
/// ## Por qué existe habiendo un segmentador
///
/// Porque el segmentador se equivoca, y cuando se equivoca no hay nada que
/// hacer. Parte un pantalón por el cinturón, se deja media manga, se lleva un
/// trozo de sofá con la camiseta o directamente no ve la prenda. Hasta ahora la
/// única salida era descartar la prenda y volver a intentarlo con otra foto,
/// con el mismo modelo, esperando otro resultado.
///
/// Rodear la prenda con el dedo tarda dos segundos y **siempre funciona**. No
/// sustituye a la detección: la corrige cuando hace falta.
///
/// ## Cómo se aplica
///
/// El trazo llega en coordenadas **unitarias** (0-1 sobre la imagen), no en
/// puntos de pantalla: quien dibuja sabe de qué tamaño se está viendo la imagen
/// y aquí no hay por qué saberlo. Se cierra solo —un lazo a mano nunca acaba
/// justo donde empezó— y se rellena en una máscara que multiplica el alfa.
public enum ManualCrop {

    /// Mínimo de puntos para que el trazo sea un lazo y no un resbalón.
    public static let minimumPoints = 8

    /// Recorta la imagen dejando solo lo que hay dentro del trazo.
    ///
    /// - Parameters:
    ///   - image: la imagen completa.
    ///   - path: puntos en coordenadas unitarias, con el origen **arriba a la
    ///     izquierda** — que es como los da SwiftUI.
    ///   - feather: cuántos píxeles de difuminado en el canto. Un recorte a
    ///     dedo con el borde duro se ve troquelado.
    /// - Returns: la prenda recortada y ajustada a su caja, o `nil` si el
    ///   trazo no encierra nada.
    public static func apply(
        to image: CGImage,
        path points: [CGPoint],
        feather: Int = 2
    ) -> CGImage? {
        guard points.count >= minimumPoints else { return nil }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        guard
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // La máscara, en su propio contexto de un canal. Rellenar el lazo con
        // Core Graphics sale gratis y trae el antialias del sistema, que es
        // justo el difuminado que hace falta en el canto.
        guard
            let maskContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else { return nil }

        maskContext.setFillColor(gray: 0, alpha: 1)
        maskContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        maskContext.setFillColor(gray: 1, alpha: 1)

        let shape = CGMutablePath()
        // La y se invierte: los puntos vienen con el origen arriba y
        // `CGContext` lo tiene abajo. Sin esto el recorte sale del revés, que
        // es el fallo clásico y encima parece que la máscara no funciona.
        let first = points[0]
        shape.move(to: CGPoint(x: first.x * Double(width), y: (1 - first.y) * Double(height)))
        for point in points.dropFirst() {
            shape.addLine(to: CGPoint(x: point.x * Double(width), y: (1 - point.y) * Double(height)))
        }
        shape.closeSubpath()

        maskContext.addPath(shape)
        maskContext.fillPath(using: .evenOdd)

        guard let maskImage = maskContext.makeImage() else { return nil }
        var mask = [UInt8](repeating: 0, count: width * height)
        mask.withUnsafeMutableBytes { raw in
            guard
                let readback = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else { return }
            readback.draw(maskImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        // Y se aplica sobre el alfa, premultiplicando el color: el resto del
        // pipeline —la caja opaca, la máscara de toque, el encaje— da por hecho
        // que el color viene multiplicado por su alfa.
        // **El lazo es una pista, no unas tijeras.**
        //
        // Nadie rodea una prenda al píxel con el dedo, y no hace falta: lo que
        // el trazo dice es *por aquí anda el contorno*. Tomándolo al pie de la
        // letra, lo que quedó fuera —media manga, el bajo de un pantalón— se
        // perdía, y encima el borde salía con la forma temblorosa del dedo.
        //
        // Así que se usa como semilla y se crece desde ahí por todo lo que no
        // sea del color del fondo, exactamente igual que sobre fondo liso:
        // ver `OutlineRefiner`. Lo que se recupera es la prenda; la mesa no,
        // porque la mesa **sí** es del color del fondo.
        //
        // Con presupuesto largo —tres veces el normal— porque aquí el error
        // de partida es humano y puede ser de bastantes píxeles, no de los
        // pocos que deja un mapa de clases.
        var seed = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) where mask[index] >= 128 { seed[index] = 1 }

        let grown = OutlineRefiner.refine(
            &seed, in: image, width: width, height: height, maximumGrowth: 120
        )
        if grown > 0 {
            // Y se limpia como cualquier otra máscara: grietas cerradas,
            // agujeros de dentro rellenos y el canto alisado, que es lo que
            // quita el temblor del trazo.
            Morphology.close(&seed, width: width, height: height, radius: 3)
            Morphology.fillHoles(&seed, width: width, height: height)
            // Radio 2 y no 3: alisar de más redondea lo que sí es la prenda
            // —el pico de un cuello, la muesca de una manga— y el recorte sale
            // con forma de pastilla. Lo justo para quitar el temblor del dedo.
            Morphology.smooth(&seed, width: width, height: height, radius: 2)
            for index in 0..<(width * height) {
                mask[index] = seed[index] == 1 ? 255 : 0
            }
            DiagnosticsLog.record(
                "RECORTE",
                "lazo a mano ampliado por contraste: \(grown) píxeles recuperados"
            )
        }

        var kept = 0
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                let coverage = Double(mask[row + x]) / 255
                if coverage > 0.5 { kept += 1 }
                let alpha = Double(buffer[x, y, 3]) * coverage
                for component in 0..<3 {
                    buffer[x, y, component] = UInt8(Double(buffer[x, y, component]) * coverage)
                }
                buffer[x, y, 3] = UInt8(alpha)
            }
        }
        _ = feather   // el antialias del relleno ya hace de difuminado

        guard kept > 0, let cut = context.makeImage() else { return nil }
        // Ajustado a lo que quedó: un lazo pequeño en una foto grande dejaría
        // la prenda diminuta en una esquina de un lienzo casi vacío.
        return CropNormalizer.normalize(cut, for: .other) ?? cut
    }
}
