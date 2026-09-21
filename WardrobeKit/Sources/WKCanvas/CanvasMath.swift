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

    // MARK: - Los límites del papel

    /// Lo que puede medir de lado como mínimo una prenda, en puntos de canvas.
    ///
    /// Por debajo de esto deja de ser una prenda y pasa a ser una mota: no se
    /// distingue qué es, no se puede volver a coger con el dedo —el área de
    /// toque se queda por debajo de lo que el sistema considera tocable— y la
    /// única salida es deshacer. Un tope evita ese callejón.
    public static let minimumSide: Double = 60

    /// A cuántos puntos del centro engancha el imán, y por tanto a cuántos
    /// aparece la guía.
    ///
    /// Generoso en puntos de canvas —el papel mide 1000 de ancho— pero en
    /// pantalla son unos pocos: lo justo para que centrar a ojo acabe centrado
    /// de verdad, sin que se note un tirón al pasar por el medio.
    public static let centeringTolerance: Double = 12

    /// Si esto está centrado, y en qué eje.
    public struct Centering: Equatable, Sendable {
        public var horizontally = false
        public var vertically = false
        public var isCentered: Bool { horizontally || vertically }
    }

    /// Mete la prenda dentro del papel, la mantiene por encima del mínimo y,
    /// si pasa cerca del centro, la centra.
    ///
    /// ## Por qué se aplica al soltar y también al previsualizar
    ///
    /// Al previsualizar, porque si el tope solo actuara al guardar, la prenda
    /// se iría fuera bajo el dedo y volvería de un salto al soltar — y un
    /// salto al final de un gesto se lee como que la app ha hecho otra cosa.
    /// Al guardar, porque es lo que de verdad se escribe.
    ///
    /// ## El imán del centro
    ///
    /// Es la única excepción a "aquí no se cuantiza nada". Y lo es porque
    /// centrar es una intención, no una posición: nadie quiere la prenda a
    /// 498,3 sino en el medio, y acertar el medio a pulso sobre un papel
    /// escalado es imposible. Fuera de la tolerancia no toca nada, así que los
    /// 32,56° de rotación y cualquier posición que no sea el centro se
    /// guardan exactos.
    public static func constrained(_ transform: ItemTransform) -> (ItemTransform, Centering) {
        var result = transform
        var centering = Centering()

        // --- 1. El mínimo ---
        let base = min(abs(transform.baseWidth), abs(transform.baseHeight))
        if base > 0 {
            let floorScale = minimumSide / base
            if result.scale < floorScale { result.scale = floorScale }
        }

        // --- 2. El imán del centro ---
        let middle = CGPoint(x: CanvasSpace.width / 2, y: CanvasSpace.height / 2)
        if abs(result.x - middle.x) <= centeringTolerance {
            result.x = middle.x
            centering.horizontally = true
        }
        if abs(result.y - middle.y) <= centeringTolerance {
            result.y = middle.y
            centering.vertically = true
        }

        // --- 3. Dentro del papel ---
        //
        // Con la caja **girada**, no con el ancho y el alto sin más: una
        // camiseta a 45° ocupa mucho más de lado que de pie, y usar la caja sin
        // girar la dejaba salirse por las esquinas.
        let size = result.renderedSize
        let cosine = abs(cos(result.rotation))
        let sine = abs(sin(result.rotation))
        let halfWidth = (size.width * cosine + size.height * sine) / 2
        let halfHeight = (size.width * sine + size.height * cosine) / 2

        result.x = clamp(
            result.x, half: halfWidth, limit: CanvasSpace.width,
            before: sideOverhang, after: sideOverhang
        )
        result.y = clamp(
            result.y, half: halfHeight, limit: CanvasSpace.height,
            before: topOverhang, after: bottomOverhang
        )
        return (result, centering)
    }

    /// Cuánto más puede asomar por cada borde, en puntos de canvas.
    ///
    /// Solo por arriba: es donde se coloca lo que enmarca —un gorro, la
    /// fecha, un título— y ahí sale bien que sobresalga un poco del papel. Por
    /// los lados, lo que asoma se lee como descuadrado.
    static let topOverhang: Double = 28
    static let sideOverhang: Double = 0
    static let bottomOverhang: Double = 0

    /// Cuánto de la prenda tiene que quedar dentro del papel.
    ///
    /// Exigir la prenda **entera** dentro dejaba el sitio demasiado corto: una
    /// camiseta grande no llegaba ni a rozar el borde, y colocar algo
    /// asomando por el canto —que es una decisión de composición como
    /// cualquier otra— era imposible. Con 0,65 puede salirse poco más de un
    /// tercio de su radio, o sea, asomar sin llegar a perderse.
    static let keptInside = 0.65

    /// Deja el centro donde la prenda siga estando **mayormente** dentro.
    ///
    /// Si no cabe —una prenda más ancha que el papel— se centra en ese eje: es
    /// lo único que no deja un borde sin cubrir, y sobre todo evita que el
    /// tope la empuje a una esquina de la que no se puede sacar.
    private static func clamp(
        _ value: Double,
        half: Double,
        limit: Double,
        before: Double,
        after: Double
    ) -> Double {
        let margin = half * keptInside
        guard margin * 2 < limit else { return limit / 2 }
        return min(max(value, margin - before), limit - margin + after)
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
