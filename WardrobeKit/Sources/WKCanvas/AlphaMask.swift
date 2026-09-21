import CoreGraphics
import Foundation
import SwiftUI
import WKCore

/// Máscara de opacidad reducida, para acertar el toque en prendas recortadas.
///
/// ## Por qué hace falta
///
/// Una chaqueta recortada ocupa quizá el 60% de su rectángulo: el resto es
/// transparente. Si el hit testing va por bounding box, tocar la esquina vacía
/// de la chaqueta la selecciona a ella en vez de a lo que hay debajo — y apilar
/// prendas se siente roto. Con la máscara, el toque atraviesa lo transparente.
///
/// 64×64 booleanos son 4 KB por prenda. Se genera una vez al cargar la imagen y
/// se cachea; consultarla es un acceso a array.
public struct AlphaMask: Sendable {
    public static let resolution = 64

    private let bits: [Bool]

    public init(_ image: CGImage, resolution: Int = AlphaMask.resolution) {
        guard
            let buffer = PixelBuffer(width: resolution, height: resolution),
            let context = buffer.makeContext()
        else {
            bits = [Bool](repeating: true, count: resolution * resolution)
            return
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: resolution, height: resolution))

        var bits = [Bool](repeating: false, count: resolution * resolution)
        for y in 0..<resolution {
            for x in 0..<resolution {
                bits[y * resolution + x] = buffer[x, y, 3] > 24
            }
        }
        self.bits = bits
    }

    /// - Parameter point: en coordenadas unitarias del rectángulo de la prenda,
    ///   con origen arriba-izquierda.
    /// - Parameter tolerance: celdas de margen. Uno por defecto para que un
    ///   tirante o una correa finos sigan siendo tocables.
    public func isOpaque(atUnitPoint point: CGPoint, tolerance: Int = 1) -> Bool {
        let side = AlphaMask.resolution
        let column = Int(point.x * CGFloat(side))
        // El buffer de un CGBitmapContext guarda la primera fila arriba, que es
        // la misma convención que el punto que llega. No hay que invertir nada.
        let row = Int(point.y * CGFloat(side))

        for dy in -tolerance...tolerance {
            for dx in -tolerance...tolerance {
                let x = column + dx
                let y = row + dy
                guard x >= 0, x < side, y >= 0, y < side else { continue }
                if bits[y * side + x] { return true }
            }
        }
        return false
    }
}

extension AlphaMask {
    /// La silueta opaca como `Path`, en tramos horizontales.
    ///
    /// Con esto el hit testing por alfa sale **gratis**: se pasa a
    /// `contentShape` y SwiftUI hace el resto, así que cada prenda conserva sus
    /// propios gestos y el canvas no necesita estado de gesto — que es lo que
    /// mantiene el invariante de "arrastrar invalida una sola vista".
    ///
    /// Se emiten tramos y no una celda por píxel: una prenda típica da unas
    /// pocas decenas de rectángulos en lugar de 4.096.
    /// - Parameter dilation: celdas que engorda la silueta.
    ///
    ///   Cero para el toque normal: lo transparente deja pasar el dedo, que es
    ///   lo que hace que apilar prendas funcione. Y un par de celdas cuando la
    ///   prenda está cogida, para tener margen donde pellizcar en un tirante.
    func path(in rect: CGRect, dilation: Int = 0) -> Path {
        let side = AlphaMask.resolution
        let cellWidth = rect.width / CGFloat(side)
        let cellHeight = rect.height / CGFloat(side)

        var path = Path()
        for row in 0..<side {
            var runStart: Int?
            for column in 0...side {
                let filled = column < side && isOpaque(
                    atUnitPoint: CGPoint(
                        x: (CGFloat(column) + 0.5) / CGFloat(side),
                        y: (CGFloat(row) + 0.5) / CGFloat(side)
                    ),
                    tolerance: dilation
                )
                switch (filled, runStart) {
                case (true, nil):
                    runStart = column
                case (false, let start?):
                    path.addRect(CGRect(
                        x: rect.minX + CGFloat(start) * cellWidth,
                        y: rect.minY + CGFloat(row) * cellHeight,
                        width: CGFloat(column - start) * cellWidth,
                        height: cellHeight
                    ))
                    runStart = nil
                default:
                    break
                }
            }
        }
        return path
    }
}

/// `Shape` que sigue la silueta de la prenda.
///
/// Si el hit testing fuera por rectángulo, tocar la esquina transparente de una
/// chaqueta la seleccionaría a ella en vez de a lo que hay debajo, y apilar
/// prendas se sentiría roto.
public struct AlphaShape: Shape {
    private let mask: AlphaMask?
    private let dilation: Int

    public init(mask: AlphaMask?, dilation: Int = 0) {
        self.mask = mask
        self.dilation = dilation
    }

    public func path(in rect: CGRect) -> Path {
        // Sin máscara todavía cargada, el rectángulo completo: más vale
        // responder al toque que parecer que la prenda está muerta.
        guard let mask else { return Path(rect) }
        return mask.path(in: rect, dilation: dilation)
    }
}
