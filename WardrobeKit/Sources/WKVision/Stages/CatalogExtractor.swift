import CoreGraphics
import Foundation
import VideoToolbox
import Vision
import WKCore

/// Deja sola a la prenda en la imagen que devuelve el modelo.
///
/// ## Qué llega y qué hace falta
///
/// El modelo devuelve una foto **de estudio**: la prenda centrada sobre blanco,
/// con su sombra. Eso vale para mirarla, pero no para el armario: en una balda
/// o en un lienzo de color, un cuadrado blanco alrededor de cada prenda se ve
/// como lo que es — un recorte a medias. Lo que hace falta es alfa.
///
/// ## Por qué no se quita el blanco por umbral
///
/// Sería lo primero que se le ocurre a uno, y falla en el caso que más importa:
/// **una camiseta blanca sobre fondo blanco**. Un umbral de luminancia se come
/// la prenda, y la sombra de estudio —que es gris, no blanca— se queda.
///
/// Aquí se usa `GenerateForegroundInstanceMaskRequest`, el mismo "levantar
/// sujeto" de Fotos que ya usa el pipeline. Es justo su caso ideal: un objeto,
/// fondo liso, buena luz. Sale gratis, corre en el dispositivo y distingue la
/// prenda de su propia sombra, que es lo que un umbral no sabe hacer.
public enum CatalogExtractor {

    /// Recorta la prenda y la encaja con el perfil de su categoría.
    ///
    /// - Parameters:
    ///   - image: lo que devolvió el modelo, sobre blanco.
    ///   - kind: para elegir el encaje — un pantalón no se encaja como un top.
    /// - Returns: la prenda sola, con alfa, ya normalizada. `nil` si no se pudo
    ///   separar, y entonces quien llama se queda con el recorte de siempre.
    public static func extract(_ image: CGImage, kind: GarmentKind) async -> CGImage? {
        // **Primero, lo que ya viene recortado.** Al modelo se le pide la
        // prenda sobre fondo transparente; cuando hace caso, el mejor recorte
        // posible es el suyo y cualquier cosa que hagamos aquí solo puede
        // estropearlo.
        var cut = alphaCutout(image)
        // **Y si no, levantar el sujeto.**
        //
        // Ya no se pide magenta. La idea era buena —un color que no existe en
        // la ropa se quita por comparación y no por adivinar— y en la práctica
        // dejaba un filete rosado que había que ir puliendo, y una prenda
        // teñida de rosa cuando el modelo se pasaba de intenso. Ahora se pide
        // un gris liso de estudio y lo recorta Vision, que es semántico: sabe
        // qué es la prenda en vez de comparar colores, así que una camiseta
        // blanca sobre gris claro no le da ningún problema.
        if cut == nil { cut = await subject(of: image) }
        // El croma se queda **el último**, por si llega alguna imagen vieja de
        // las de fondo magenta —o si algún día el modelo decide pintar uno—.
        if cut == nil { cut = ChromaKey.cutout(image) }

        guard let cut else {
            DiagnosticsLog.record(
                "CATÁLOGO", "no se pudo separar la prenda del fondo", isProblem: true
            )
            return nil
        }
        return CropNormalizer.normalize(cut, for: kind) ?? cut
    }

    /// La imagen **si ya trae su propio recorte**.
    ///
    /// ## Por qué hay que comprobarlo y no fiarse del formato
    ///
    /// Un PNG casi siempre declara canal alfa aunque esté entero a 255: el
    /// formato dice "puede haber transparencia", no "la hay". Así que se mira
    /// el borde de la imagen, que es donde tiene que haber fondo: si la mayor
    /// parte del marco es transparente, el modelo hizo lo que se le pidió.
    ///
    /// - Returns: la misma imagen, o `nil` si viene opaca.
    private static func alphaCutout(_ image: CGImage) -> CGImage? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return nil
        default: break
        }

        let width = image.width
        let height = image.height
        guard width > 2, height > 2 else { return nil }
        guard
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // El marco de fuera, una fila y una columna de cada lado.
        var clear = 0
        var total = 0
        for x in 0..<width {
            for y in [0, height - 1] {
                total += 1
                if buffer[x, y, 3] < 16 { clear += 1 }
            }
        }
        for y in 0..<height {
            for x in [0, width - 1] {
                total += 1
                if buffer[x, y, 3] < 16 { clear += 1 }
            }
        }
        guard total > 0, Double(clear) / Double(total) > 0.9 else { return nil }
        DiagnosticsLog.record("CATÁLOGO", "la imagen ya venía recortada")
        return image
    }

    /// La prenda sin fondo, tal cual la levanta Vision.
    private static func subject(of image: CGImage) async -> CGImage? {
        guard
            let observation = try? await VisionStages.foregroundInstances(in: image),
            let buffer = try? observation.generateMaskedImage(
                for: observation.allInstances,
                imageFrom: ImageRequestHandler(image),
                // Recortado a la extensión de lo que encuentre: la imagen
                // generada trae márgenes blancos anchos, y conservarlos haría
                // que el encaje midiera el margen del modelo y no la prenda.
                croppedToInstancesExtent: true
            )
        else { return nil }
        // El mismo puente que usa el pipeline: un `CVPixelBuffer` con alfa
        // no se dibuja, se convierte.
        var result: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &result)
        return result
    }
}
