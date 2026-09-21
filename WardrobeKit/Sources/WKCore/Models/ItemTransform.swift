import CoreGraphics
import Foundation

/// La colocación exacta de una prenda dentro de `CanvasSpace`.
///
/// Tipo POD, `Sendable` y `Equatable`: se puede pasar entre actores y comparar
/// con `memcmp`, que es lo que permite que arrastrar una prenda invalide una
/// sola vista.
///
/// - Important: `Double` de 64 bits en todos los campos. **Nada aquí se
///   redondea, se cuantiza ni se hace snap** — ni al guardar, ni al cargar, ni
///   al renderizar. Si giras una camiseta 32,56°, al volver está a 32,56°.
public struct ItemTransform: Sendable, Equatable, Codable, Hashable {
    /// Centro de la prenda, en puntos de canvas.
    public var x: Double
    public var y: Double
    /// Tamaño intrínseco al soltarla, en puntos de canvas. `scale` multiplica sobre esto.
    public var baseWidth: Double
    public var baseHeight: Double
    public var scale: Double
    /// Radianes. Precisión completa, jamás redondeado.
    public var rotation: Double
    /// Orden de apilado. Traer al frente es `maxZ + 1`; **nunca** se reindexa el array.
    public var zIndex: Double

    public init(
        x: Double,
        y: Double,
        baseWidth: Double,
        baseHeight: Double,
        scale: Double = 1,
        rotation: Double = 0,
        zIndex: Double = 0
    ) {
        self.x = x
        self.y = y
        self.baseWidth = baseWidth
        self.baseHeight = baseHeight
        self.scale = scale
        self.rotation = rotation
        self.zIndex = zIndex
    }

    public var center: CGPoint { CGPoint(x: x, y: y) }
    public var renderedSize: CGSize {
        CGSize(width: baseWidth * scale, height: baseHeight * scale)
    }
    /// Grados, **solo para mostrar**. El valor canónico son los radianes.
    ///
    /// - Warning: no escribir nunca de vuelta un valor derivado de este.
    ///   `grados → radianes → grados` no round-trippea en IEEE 754 (32,56
    ///   vuelve como 32,56000000000001), así que hacerlo iría desplazando
    ///   la rotación un poco cada vez que se abre el outfit. Al editar,
    ///   escribir los radianes calculados a partir de lo que teclee el
    ///   usuario, no a partir de lo que se estuviera mostrando.
    public var rotationDegrees: Double { rotation * 180 / .pi }
}
