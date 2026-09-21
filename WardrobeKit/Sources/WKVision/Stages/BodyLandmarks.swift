import Foundation

/// Alturas de las articulaciones clave, en coordenadas normalizadas de Vision.
///
/// - Important: Vision usa **origen abajo-izquierda**: `y = 1` es la parte
///   superior de la imagen y `y = 0` la inferior. Es al revés que CoreGraphics
///   en un `CGContext` de bitmap, y confundirlos pone los zapatos en la balda
///   de los sombreros. Todo este tipo está en convención Vision.
public struct BodyLandmarks: Sendable, Equatable {
    public let shoulderY: Double
    public let hipY: Double
    public let kneeY: Double?
    public let ankleY: Double?
    /// Confianza media de las articulaciones encontradas, 0-1.
    public let confidence: Double

    public init(shoulderY: Double, hipY: Double, kneeY: Double?, ankleY: Double?, confidence: Double) {
        self.shoulderY = shoulderY
        self.hipY = hipY
        self.kneeY = kneeY
        self.ankleY = ankleY
        self.confidence = confidence
    }

    /// En qué banda cae una región, por la altura de su centro.
    ///
    /// Los umbrales no son los puntos medios entre articulaciones sino que se
    /// desplazan un poco hacia arriba: una camiseta cae claramente por debajo
    /// de los hombros pero su *centro* queda bastante por encima de las
    /// caderas, y un pantalón empieza en la cadera pero su centro está cerca de
    /// las rodillas.
    public func band(forCenterY y: Double) -> BodyBand {
        if y > shoulderY { return .aboveShoulders }

        let ankle = ankleY ?? 0
        if let kneeY {
            // Con rodilla conocida, el calzado es lo que queda por debajo del
            // punto medio entre rodilla y tobillo.
            let footThreshold = ankle + (kneeY - ankle) * 0.25
            if y < footThreshold { return .feet }
        } else if y < ankle + 0.05 {
            return .feet
        }

        return y > hipY ? .torso : .legs
    }

    /// Cuánto fiarse de la banda para una región concreta.
    ///
    /// Cerca de una frontera la asignación es una moneda al aire, así que baja
    /// la confianza y la prenda entra en la pantalla de revisión en vez de
    /// aterrizar en silencio en la balda equivocada.
    public func bandConfidence(forCenterY y: Double) -> Double {
        let boundaries = [shoulderY, hipY, kneeY, ankleY].compactMap { $0 }
        let nearest = boundaries.map { abs($0 - y) }.min() ?? 1
        // A 0,08 de distancia (8% del alto) ya se considera separación clara.
        let margin = min(nearest / 0.08, 1)
        return confidence * (0.5 + 0.5 * margin)
    }
}
