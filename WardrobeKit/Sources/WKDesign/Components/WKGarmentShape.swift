import SwiftUI

/// Siluetas de prenda, dibujadas.
///
/// No son iconos de SF Symbols: un armario lleno de `tshirt.fill` repetido se
/// ve como una lista de ajustes. Son contornos con el cuello, la caída de la
/// manga y el vuelo de la falda, que es lo que hace que un hueco vacío siga
/// pareciendo un armario.
///
/// **Una sola fuente de verdad.** Las usa el estado vacío del armario y las usa
/// el sembrado de desarrollo para generar prendas de prueba. Tenerlas
/// duplicadas fue exactamente cómo el armario acabó lleno de rectángulos.
public enum WKGarmentSilhouette: String, CaseIterable, Sendable {
    case top, outer, dress, pants, shoe, cap, bag

    /// Alto relativo al ancho. Un pantalón no es tan ancho como un abrigo, y
    /// dibujarlos todos en un cuadrado los deja a escalas que no se parecen a
    /// las de la ropa real.
    public var aspectRatio: CGFloat {
        switch self {
        case .top: 1.0
        case .outer: 0.92
        case .dress: 0.86
        case .pants: 0.66
        case .shoe: 1.5
        case .cap: 1.6
        case .bag: 0.92
        }
    }

    /// Contorno normalizado al rectángulo que se le dé.
    ///
    /// Cada silueta es una lista de vértices y **todos se redondean**: hombros,
    /// puños y bajos por fuera, sisa y tiro por dentro. La ropa no tiene
    /// esquinas en pico, y un polígono sin redondear se lee como un icono.
    public func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.07
        var path = Path()
        for polygon in polygons {
            path.addPath(Self.rounded(polygon, in: rect, radius: radius))
        }
        return path
    }

    /// Vértices en 0-1 con la **y hacia abajo**, como mide `Path`: 0,1 es el
    /// cuello y 0,9 el bajo.
    ///
    /// Casi todas son un solo contorno. El bolso son dos que **se tocan sin
    /// solaparse**: con un relleno translúcido, dos subrutas superpuestas
    /// dejan ver la costura entre ellas.
    private var polygons: [[CGPoint]] {
        switch self {
        case .top:
            // Manga corta y **cuello redondo**: el escote no es un vértice al
            // que se le pide radio —eso da siempre una uve— sino media
            // circunferencia descrita punto a punto.
            [[
                .init(x: 0.31, y: 0.09)]
                + Self.neckline(centerX: 0.50, topY: 0.09, radiusX: 0.19, depth: 0.12)
                + [.init(x: 0.69, y: 0.09),
                .init(x: 0.76, y: 0.10),
                .init(x: 0.93, y: 0.27), .init(x: 0.85, y: 0.47),
                .init(x: 0.74, y: 0.42), .init(x: 0.75, y: 0.92),
                .init(x: 0.25, y: 0.92), .init(x: 0.26, y: 0.42),
                .init(x: 0.15, y: 0.47), .init(x: 0.07, y: 0.27),
                .init(x: 0.24, y: 0.10),
            ]]

        case .outer:
            // Una chaqueta no es una camiseta más grande. Lo que la distingue
            // a tamaño de silueta son tres cosas: **manga larga** (el puño baja
            // hasta 0,62 y no a 0,47), **cuello recto con solapa en pico** —
            // frente al cuello redondo del top— y más cuerpo.
            [[
                .init(x: 0.30, y: 0.06), .init(x: 0.42, y: 0.07),
                .init(x: 0.50, y: 0.32), .init(x: 0.58, y: 0.07),
                .init(x: 0.70, y: 0.06), .init(x: 0.80, y: 0.10),
                .init(x: 0.96, y: 0.30), .init(x: 0.88, y: 0.62),
                .init(x: 0.76, y: 0.57), .init(x: 0.77, y: 0.95),
                .init(x: 0.23, y: 0.95), .init(x: 0.24, y: 0.57),
                .init(x: 0.12, y: 0.62), .init(x: 0.04, y: 0.30),
                .init(x: 0.20, y: 0.10),
            ]]

        case .dress:
            // Tirantes, cintura marcada y vuelo. El escote, redondo igual que
            // el del top.
            [[
                .init(x: 0.35, y: 0.07)]
                + Self.neckline(centerX: 0.50, topY: 0.07, radiusX: 0.15, depth: 0.10)
                + [.init(x: 0.65, y: 0.07), .init(x: 0.68, y: 0.15),
                .init(x: 0.62, y: 0.32), .init(x: 0.60, y: 0.46),
                .init(x: 0.86, y: 0.92), .init(x: 0.14, y: 0.92),
                .init(x: 0.40, y: 0.46), .init(x: 0.38, y: 0.32),
                .init(x: 0.34, y: 0.14),
            ]]

        case .pants:
            // Cintura, dos perneras y el tiro entre ellas.
            [[
                .init(x: 0.28, y: 0.06), .init(x: 0.72, y: 0.06),
                .init(x: 0.70, y: 0.94), .init(x: 0.56, y: 0.94),
                .init(x: 0.545, y: 0.50), .init(x: 0.455, y: 0.50),
                .init(x: 0.44, y: 0.94), .init(x: 0.30, y: 0.94),
            ]]

        case .shoe:
            // De perfil: talón, caña, empeine, puntera y suela.
            [[
                .init(x: 0.08, y: 0.72), .init(x: 0.08, y: 0.46),
                .init(x: 0.15, y: 0.37), .init(x: 0.31, y: 0.36),
                .init(x: 0.47, y: 0.47), .init(x: 0.62, y: 0.55),
                .init(x: 0.79, y: 0.60), .init(x: 0.92, y: 0.67),
                .init(x: 0.92, y: 0.79), .init(x: 0.54, y: 0.82),
                .init(x: 0.20, y: 0.80),
            ]]

        case .cap:
            // Copa y visera, mirando a la derecha.
            [[
                .init(x: 0.20, y: 0.58), .init(x: 0.25, y: 0.26),
                .init(x: 0.46, y: 0.15), .init(x: 0.67, y: 0.25),
                .init(x: 0.72, y: 0.56), .init(x: 0.92, y: 0.60),
                .init(x: 0.90, y: 0.70), .init(x: 0.50, y: 0.72),
                .init(x: 0.22, y: 0.67),
            ]]

        case .bag:
            // Cuerpo de tote, y el asa como banda cerrada que apoya justo en
            // la boca. Apoyar y no solapar es lo que evita la costura.
            [
                [
                    .init(x: 0.22, y: 0.40), .init(x: 0.78, y: 0.40),
                    .init(x: 0.74, y: 0.92), .init(x: 0.26, y: 0.92),
                ],
                [
                    .init(x: 0.35, y: 0.40), .init(x: 0.36, y: 0.27),
                    .init(x: 0.50, y: 0.20), .init(x: 0.64, y: 0.27),
                    .init(x: 0.65, y: 0.40), .init(x: 0.58, y: 0.40),
                    .init(x: 0.57, y: 0.30), .init(x: 0.50, y: 0.27),
                    .init(x: 0.43, y: 0.30), .init(x: 0.42, y: 0.40),
                ],
            ]
        }
    }

    /// Media circunferencia hacia abajo, punto a punto.
    ///
    /// Un escote redondo no se consigue pidiéndole radio a un vértice: el radio
    /// redondea la punta pero deja las dos paredes rectas, y el resultado es
    /// siempre una uve con la punta limada. Describiendo el arco, el redondeo
    /// de vértices solo tiene que suavizar entre puntos que ya están sobre la
    /// circunferencia.
    private static func neckline(
        centerX: CGFloat,
        topY: CGFloat,
        radiusX: CGFloat,
        depth: CGFloat,
        steps: Int = 6
    ) -> [CGPoint] {
        (1..<steps).map { step in
            let angle = CGFloat(step) / CGFloat(steps) * .pi
            return CGPoint(
                x: centerX - cos(angle) * radiusX,
                y: topY + sin(angle) * depth
            )
        }
    }

    /// El radio que **de verdad cabe** en un vértice.
    ///
    /// `addArc(tangent1End:)` no recorta el radio: si no cabe, se desborda y
    /// deja un pico. Y lo que hace falta no es limitar por longitud de arista
    /// sino por ángulo — la tangente que consume un arco de radio `r` en un
    /// vértice que gira `θ` es `r / tan(θ/2)`, que se dispara cuando el
    /// vértice es casi una inversión. Era exactamente lo que pasaba en el
    /// escote y en los tirantes del vestido, donde dos aristas casi vuelven
    /// sobre sí mismas.
    private static func fittingRadius(
        at corner: CGPoint,
        previous: CGPoint,
        next: CGPoint,
        requested: CGFloat
    ) -> CGFloat {
        func unit(_ from: CGPoint, _ to: CGPoint) -> CGPoint? {
            let dx = to.x - from.x
            let dy = to.y - from.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0.0001 else { return nil }
            return CGPoint(x: dx / length, y: dy / length)
        }
        guard
            let toPrevious = unit(corner, previous),
            let toNext = unit(corner, next)
        else { return 0 }

        let cosine = max(-1, min(1, toPrevious.x * toNext.x + toPrevious.y * toNext.y))
        let angle = acos(cosine)
        // Vértice degenerado: las dos aristas apuntan al mismo sitio.
        guard angle > 0.0001 else { return 0 }

        let halfEdge = min(
            hypot(corner.x - previous.x, corner.y - previous.y),
            hypot(corner.x - next.x, corner.y - next.y)
        ) / 2
        return min(requested, halfEdge * tan(angle / 2))
    }

    /// Polígono cerrado con todos los vértices redondeados.
    ///
    /// `addArc(tangent1End:tangent2End:)` es la forma correcta: produce **un
    /// solo contorno limpio**. Engordar el polígono con su propio trazo de
    /// junta redonda también redondea, pero deja dos subrutas superpuestas, y
    /// con relleno translúcido se ve el borde de una sobre la otra — que es
    /// exactamente el doble filete que tenían estas siluetas.
    ///
    /// Los puntos intermedios son **mitades de arista**: así el arco nunca pide
    /// más radio del que cabe, y un vértice entre dos aristas cortas no deforma
    /// la silueta.
    private static func rounded(_ points: [CGPoint], in rect: CGRect, radius: CGFloat) -> Path {
        guard points.count > 2 else { return Path() }

        func absolute(_ point: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * point.x, y: rect.minY + rect.height * point.y)
        }
        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }


        let vertices = points.map(absolute)
        var path = Path()
        path.move(to: midpoint(vertices[vertices.count - 1], vertices[0]))

        for index in vertices.indices {
            let previous = vertices[(index + vertices.count - 1) % vertices.count]
            let corner = vertices[index]
            let next = vertices[(index + 1) % vertices.count]

            path.addArc(
                tangent1End: corner,
                tangent2End: midpoint(corner, next),
                radius: fittingRadius(
                    at: corner, previous: previous, next: next, requested: radius
                )
            )
        }
        path.closeSubpath()
        return path
    }
}

/// La silueta como `Shape`, para rellenar, recortar o animar.
public struct WKGarmentShape: Shape {
    public let silhouette: WKGarmentSilhouette

    public init(_ silhouette: WKGarmentSilhouette) {
        self.silhouette = silhouette
    }

    public func path(in rect: CGRect) -> Path { silhouette.path(in: rect) }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: [.init(.adaptive(minimum: 90))], spacing: WK.Spacing.l) {
            ForEach(WKGarmentSilhouette.allCases, id: \.self) { silhouette in
                WKGarmentShape(silhouette)
                    .fill(WK.Palette.ink(0.22))
                    .frame(width: 90, height: 90 / silhouette.aspectRatio)
            }
        }
        .padding()
    }
    .background(WK.Palette.canvas)
}
