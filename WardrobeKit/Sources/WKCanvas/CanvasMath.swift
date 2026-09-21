import CoreGraphics
import SwiftUI
import WKCore

/// Matemática de la manipulación directa.
///
/// Funciones puras y aparte de la vista porque esto es lo que falla en
/// silencio: si el ancla está mal, la prenda "se escapa" de los dedos al
/// escalar y nadie sabe por qué.
///
/// ## El ancla
///
/// Escalar y rotar se anclan en **el punto medio entre los dedos**, no en el
/// centro de la prenda. Es lo que hace que parezca que la prenda está *bajo*
/// los dedos en lugar de reaccionar a ellos. El precio es que escalar alrededor
/// de un punto que no es el centro **también desplaza el centro**, y ese
/// desplazamiento hay que calcularlo para que lo que se guarda coincida
/// exactamente con lo que se veía.
public enum CanvasMath {

    /// El ancla, de espacio unitario de la prenda a coordenadas de canvas.
    public static func anchorInCanvas(of transform: ItemTransform, anchor: UnitPoint) -> CGPoint {
        let size = transform.renderedSize
        // Desplazamiento desde el centro, en el espacio sin rotar de la prenda.
        let local = CGPoint(
            x: (anchor.x - 0.5) * size.width,
            y: (anchor.y - 0.5) * size.height
        )
        let rotated = rotate(local, by: transform.rotation)
        return CGPoint(x: transform.x + rotated.x, y: transform.y + rotated.y)
    }

    /// Aplica el gesto completo y devuelve la transformada final.
    ///
    /// El orden importa y es el mismo que usa el render: primero escala,
    /// después rotación —ambas alrededor del ancla— y por último la traslación
    /// del arrastre. Invertirlo daría una posición distinta.
    ///
    /// - Parameter drag: ya convertido a puntos de canvas (dividido por `k`).
    public static func applying(
        scale: Double,
        rotation: Double,
        drag: CGSize,
        about anchor: UnitPoint,
        to transform: ItemTransform
    ) -> ItemTransform {
        var result = transform
        let pivot = anchorInCanvas(of: transform, anchor: anchor)

        // Escalar alrededor del ancla arrastra el centro hacia o desde ella.
        result.x = pivot.x + (result.x - pivot.x) * scale
        result.y = pivot.y + (result.y - pivot.y) * scale
        result.scale *= scale

        // Rotar alrededor del ancla gira el centro a su alrededor.
        let offset = CGPoint(x: result.x - pivot.x, y: result.y - pivot.y)
        let turned = rotate(offset, by: rotation)
        result.x = pivot.x + turned.x
        result.y = pivot.y + turned.y
        result.rotation += rotation

        result.x += drag.width
        result.y += drag.height
        return result
    }

    /// Punto tocado, de coordenadas de canvas al espacio unitario de la prenda.
    ///
    /// Deshace traslación, rotación y escala en ese orden. Es lo que permite
    /// consultar la máscara alfa y dejar que el toque atraviese lo transparente.
    public static func unitPoint(
        ofCanvasPoint point: CGPoint,
        in transform: ItemTransform
    ) -> CGPoint {
        let offset = CGPoint(x: point.x - transform.x, y: point.y - transform.y)
        let unrotated = rotate(offset, by: -transform.rotation)
        let size = transform.renderedSize
        guard size.width > 0, size.height > 0 else { return CGPoint(x: -1, y: -1) }
        return CGPoint(
            x: unrotated.x / size.width + 0.5,
            y: unrotated.y / size.height + 0.5
        )
    }

    static func rotate(_ point: CGPoint, by radians: Double) -> CGPoint {
        guard radians != 0 else { return point }
        let cosine = cos(radians)
        let sine = sin(radians)
        return CGPoint(
            x: point.x * cosine - point.y * sine,
            y: point.x * sine + point.y * cosine
        )
    }
}
