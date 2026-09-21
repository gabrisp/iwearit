import CoreGraphics
import Foundation

/// Una franja del cuerpo que se recorta como si fuera una prenda.
///
/// ## Por qué existe
///
/// `GenerateForegroundInstanceMaskRequest` es "levantar sujeto": separa objeto
/// de fondo y **devuelve la persona entera como un solo sujeto**. No sabe qué
/// es una camiseta. Apoyarse en él para separar prendas devuelve exactamente
/// una "prenda" que es una persona — medido en dispositivo.
///
/// Así que en modo degradado el corte lo hacemos nosotros: se toma la silueta
/// de la persona y se parte por las articulaciones. Es tosco y tiene límites
/// conocidos (un vestido se parte en dos, una chaqueta abierta se mezcla con la
/// camiseta de debajo), pero produce recortes **con forma de prenda** en vez de
/// una foto tuya, y funciona sin red y sin modelos.
///
/// En F7, SegFormer sustituye todo esto por segmentación real por clase.
struct GarmentRegion {
    let kind: BodyBand
    /// En píxeles con origen arriba-izquierda, como `CGImage`.
    let rect: CGRect
    /// Cuánto fiarse, antes de aplicar el techo del modo degradado.
    let confidence: Double

    /// Los solapes no son arbitrarios: una prenda no empieza y acaba justo en
    /// la articulación. El cuello sube por encima de los hombros, el bajo de
    /// una camiseta cae por debajo de la cadera, y un pantalón arranca en la
    /// cintura, que está por encima de la articulación de la cadera.
    private static let collarRise = 0.05
    private static let hemDrop = 0.10
    private static let waistRise = 0.04

    /// Parte el cuerpo en franjas, en píxeles de la imagen.
    ///
    /// - Parameter height: alto en píxeles de la imagen completa.
    static func regions(
        for landmarks: BodyLandmarks,
        imageSize: CGSize,
        personBounds: CGRect
    ) -> [GarmentRegion] {
        // Vision normaliza con origen abajo; `CGImage` cuenta filas desde
        // arriba. De ahí el `1 -` en cada conversión.
        func pixelY(_ visionY: Double) -> CGFloat {
            CGFloat(1 - visionY) * imageSize.height
        }

        let bodyHeight = abs(pixelY(landmarks.shoulderY) - pixelY(landmarks.ankleY ?? 0))
        guard bodyHeight > 0 else { return [] }

        let shoulder = pixelY(landmarks.shoulderY)
        let hip = pixelY(landmarks.hipY)
        let ankle = landmarks.ankleY.map(pixelY) ?? personBounds.maxY
        let top = personBounds.minY
        let bottom = personBounds.maxY

        let x = personBounds.minX
        let width = personBounds.width

        var regions: [GarmentRegion] = []

        // Accesorios de cabeza: por encima de los hombros. Casi siempre es cara
        // y pelo, y el filtro de piel lo descarta — pero una gorra sobrevive.
        if shoulder - top > bodyHeight * 0.08 {
            regions.append(GarmentRegion(
                kind: .aboveShoulders,
                rect: CGRect(x: x, y: top, width: width, height: shoulder - top),
                confidence: landmarks.confidence * 0.6
            ))
        }

        // Torso: del cuello al bajo de la camiseta.
        let torsoTop = max(top, shoulder - bodyHeight * collarRise)
        let torsoBottom = min(bottom, hip + bodyHeight * hemDrop)
        if torsoBottom > torsoTop {
            regions.append(GarmentRegion(
                kind: .torso,
                rect: CGRect(x: x, y: torsoTop, width: width, height: torsoBottom - torsoTop),
                confidence: landmarks.confidence
            ))
        }

        // Piernas: de la cintura al tobillo.
        let legsTop = max(top, hip - bodyHeight * waistRise)
        let legsBottom = min(bottom, ankle)
        if legsBottom > legsTop {
            regions.append(GarmentRegion(
                kind: .legs,
                rect: CGRect(x: x, y: legsTop, width: width, height: legsBottom - legsTop),
                confidence: landmarks.confidence
            ))
        }

        // Calzado: del tobillo abajo. Solo si la foto llega a los pies.
        if bottom - ankle > bodyHeight * 0.04 {
            regions.append(GarmentRegion(
                kind: .feet,
                rect: CGRect(x: x, y: ankle, width: width, height: bottom - ankle),
                confidence: landmarks.confidence * 0.8
            ))
        }

        return regions
    }
}
