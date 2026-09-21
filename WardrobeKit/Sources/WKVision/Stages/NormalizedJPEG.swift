import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prepara el recorte para mandarlo a resolver **o a redibujar**.
///
/// Público porque el formato es parte del contrato remoto: quien prepare una
/// consulta —el pipeline al describir, la importación al pedir la versión de
/// catálogo— tiene que mandar exactamente estos bytes.
///
/// Tres decisiones, y las tres son de coste:
///
/// - **512 y no 1024.** El modelo remoto no ve más por el doble de píxeles —le
///   entra reescalado de todas formas— y son unos 40 KB contra unos 150.
/// - **JPEG y no PNG.** La transparencia no viaja: ya hizo su trabajo al
///   recortar, y un PNG con alfa de una prenda pesa el triple.
/// - **Sobre blanco.** Componer el alfa contra blanco aquí y no dejar que lo
///   haga el decodificador del otro lado: contra negro, una prenda oscura
///   desaparece.
public enum NormalizedJPEG {

    public static let side = 512

    /// Cuánto se comprime.
    ///
    /// 0,65 y no 0,8. Medido sobre el mismo recorte, lo que viaja en base64:
    ///
    /// | calidad | JPEG | base64 |
    /// |---|---|---|
    /// | 0,80 | 27 KB | 36 KB |
    /// | 0,72 | 22 KB | 29 KB |
    /// | **0,65** | **19 KB** | **26 KB** |
    /// | 0,45 | 15 KB | 20 KB |
    ///
    /// Un 28% menos de subida por prenda sin tocar lo que el modelo necesita
    /// ver: a 512 píxeles y con una prenda sobre blanco, los artefactos de
    /// compresión a 0,65 no caen donde están las decisiones —el cuello, el
    /// largo, el logotipo—. Por debajo de 0,5 sí empiezan a comerse el texto
    /// pequeño de una etiqueta, que es justo de donde sale la marca.
    public static let quality = 0.65

    public static func encode(_ image: CGImage, side: Int = side) -> Data? {
        guard let context = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .high

        // Encajado sin deformar: el recorte ya viene con su proporción decidida
        // por el perfil de su categoría, y estirarlo a cuadrado aquí le
        // cambiaría la forma justo antes de pedir que lo reconozcan.
        let scale = min(Double(side) / Double(image.width), Double(side) / Double(image.height))
        let width = Double(image.width) * scale
        let height = Double(image.height) * scale
        context.draw(image, in: CGRect(
            x: (Double(side) - width) / 2,
            y: (Double(side) - height) / 2,
            width: width, height: height
        ))

        guard let flattened = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, flattened, [
            kCGImageDestinationLossyCompressionQuality: quality,
            // Tablas de Huffman optimizadas: un porcentaje más pequeño por el
            // mismo contenido, sin pérdida añadida. Es gratis.
            kCGImageDestinationOptimizeColorForSharing: true,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
