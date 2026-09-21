import CoreGraphics
import Foundation

/// Un bitmap RGBA con su memoria bien gestionada.
///
/// ## Por qué existe
///
/// El atajo habitual es `CGContext(data: &pixels, …)` sobre un `[UInt8]`. Es
/// **incorrecto**: `&array` produce un puntero válido *solo durante esa
/// llamada*, y seguir usándolo después para dibujar y crear la imagen es
/// comportamiento indefinido. Funciona casi siempre, y revienta cuando el
/// array se ha movido — típicamente bajo presión de memoria, que es
/// exactamente lo que pasa al escanear una galería entera.
///
/// Aquí la memoria se reserva explícitamente, vive lo que tiene que vivir y se
/// libera al final.
public final class PixelBuffer {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    private let storage: UnsafeMutablePointer<UInt8>

    public init?(width: Int, height: Int) {
        guard width > 0, height > 0 else { return nil }
        self.width = width
        self.height = height
        self.bytesPerRow = width * 4
        self.storage = .allocate(capacity: bytesPerRow * height)
        storage.initialize(repeating: 0, count: bytesPerRow * height)
    }

    deinit {
        storage.deallocate()
    }

    /// Contexto RGBA premultiplicado sobre esta memoria.
    ///
    /// `premultipliedLast` no es un detalle: las prendas son recortes con fondo
    /// transparente, y un contexto sin alfa las dejaría sobre negro.
    public func makeContext() -> CGContext? {
        CGContext(
            data: storage,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// Lectura de un componente. La primera fila del buffer es la de **arriba**
    /// de la imagen, que es como guarda las filas un `CGBitmapContext`.
    public subscript(x: Int, y: Int, component: Int) -> UInt8 {
        get { storage[y * bytesPerRow + x * 4 + component] }
        set { storage[y * bytesPerRow + x * 4 + component] = newValue }
    }

    public var alphaThresholdComponent: Int { 3 }
}
