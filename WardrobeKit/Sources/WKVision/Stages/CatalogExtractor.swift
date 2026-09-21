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
        // **Primero el croma.** Se le pide al modelo que devuelva la prenda
        // sobre magenta puro, y entonces el recorte no es una estimación: es
        // una comparación de color. Funciona con una camiseta blanca, que es
        // justo donde levantar el sujeto sobre blanco no tiene nada que
        // separar.
        var cut = ChromaKey.cutout(image)
        // Y si el croma no estaba —el modelo lo ignoró y la devolvió sobre
        // blanco— se cae a levantar el sujeto, que sigue siendo mejor que
        // entregar un rectángulo de fondo.
        if cut == nil { cut = await subject(of: image) }

        guard let cut else {
            DiagnosticsLog.record(
                "CATÁLOGO", "no se pudo separar la prenda del fondo", isProblem: true
            )
            return nil
        }
        return CropNormalizer.normalize(cut, for: kind) ?? cut
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
