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
        // Si vino opaca, el croma: hubo una época en que se pedía magenta puro
        // y todavía puede llegar alguna así —o un fondo plano que el croma
        // reconoce—. Se queda porque no estorba y salva el caso de la camiseta
        // blanca, donde levantar el sujeto sobre blanco no tiene nada que
        // separar.
        if cut == nil { cut = ChromaKey.cutout(image) }
        // Y si tampoco —fondo blanco de estudio, que es lo que devuelven los
        // modelos que no saben hacer alfa— se cae a levantar el sujeto, que
        // sigue siendo mejor que entregar un rectángulo de fondo.
        if cut == nil { cut = await subject(of: image) }

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
