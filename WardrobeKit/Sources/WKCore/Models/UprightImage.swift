import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// Pone la imagen **derecha** antes de que la vea nadie.
///
/// ## Por qué existe
///
/// Una foto hecha con el iPhone en vertical se guarda con los píxeles **en
/// horizontal** y una etiqueta EXIF que dice "gírala 90°". `UIImage` respeta
/// esa etiqueta al dibujar, así que en pantalla se ve bien; pero
/// `UIImage.cgImage` devuelve los píxeles **en crudo**, sin girar.
///
/// Todo lo que recibe ese `CGImage` ve unos zapatos tumbados y a una persona
/// acostada:
///
/// - `DetectHumanBodyPoseRequest` no encuentra a nadie, porque nadie está de
///   lado.
/// - SegFormer está entrenado con gente **de pie** y no reconoce clases.
/// - Hasta cuando la máscara de sujeto acierta, el recorte sale girado.
///
/// El resultado es "no detecta nada" en absolutamente todo: prenda suelta,
/// persona vestida y escaneo de galería. Y no da ningún error, porque
/// técnicamente todo ha funcionado.
public enum UprightImage {

    /// Los píxeles ya girados según la orientación de la `UIImage`.
    ///
    /// Se redibuja solo si hace falta: para una foto que ya está derecha
    /// —`.up`— se devuelve el `CGImage` tal cual, sin copiar nada.
    public static func cgImage(from image: UIImage) -> CGImage? {
        guard let cgImage = image.cgImage else { return nil }
        guard image.imageOrientation != .up else { return cgImage }

        // `UIGraphicsImageRenderer` aplica la orientación al dibujar, así que
        // redibujar la imagen en su propio tamaño **en puntos** deja los
        // píxeles ya derechos. La escala a 1 porque aquí se trabaja en píxeles,
        // no en puntos de pantalla.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let size = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let redrawn = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return redrawn.cgImage ?? cgImage
    }

    /// Lo mismo desde los bytes de una foto.
    public static func cgImage(from data: Data) -> CGImage? {
        guard let image = UIImage(data: data) else { return nil }
        return cgImage(from: image)
    }

    /// Y desde una captura de la cámara.
    ///
    /// `AVCapturePhoto.cgImageRepresentation()` tiene el mismo problema: son
    /// los píxeles del sensor, y la orientación viaja aparte en los metadatos.
    public static func cgImage(fromPhotoData data: Data) -> CGImage? {
        cgImage(from: data)
    }
}
