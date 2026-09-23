import CoreGraphics
import Foundation
import VideoToolbox
import Vision
import WKCore

/// Levanta el sujeto de una foto y lo deja con alfa, sin tocar nada más.
///
/// ## Por qué existe habiendo ya recortes
///
/// Porque los que hay son para prendas: encajan la salida en el perfil de una
/// camiseta o de un pantalón, la enderezan y la escalan. Para una persona eso
/// es exactamente lo que no se quiere — aquí el recorte tiene que ser el que
/// hizo Vision y nada más.
///
/// Se usa en el probador: el modelo devuelve una foto con fondo, y el fondo
/// sobra cuando lo que quieres es la imagen recortada para ponerla donde te dé
/// la gana. Es la única forma de tener transparencia **de verdad**: un modelo
/// de imagen no devuelve canal alfa, devuelve píxeles; el alfa lo pone el
/// teléfono.
public enum SubjectCutout {

    /// - Returns: la imagen con el fondo a cero, recortada a lo que quedó, o
    ///   `nil` si Vision no encuentra ningún sujeto.
    public static func lift(_ image: CGImage) async -> CGImage? {
        guard
            let observation = try? await VisionStages.foregroundInstances(in: image),
            !observation.allInstances.isEmpty,
            let buffer = try? observation.generateMaskedImage(
                for: observation.allInstances,
                imageFrom: ImageRequestHandler(image),
                croppedToInstancesExtent: true
            )
        else {
            DiagnosticsLog.record("RECORTE", "no hay sujeto que levantar")
            return nil
        }
        var result: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &result)
        return result
    }
}
