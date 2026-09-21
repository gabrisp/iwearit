import SwiftUI
import WKCore
import WKDesign

/// La "hoja de puntitos" del canvas.
///
/// Se dibuja con `Canvas`, en una sola pasada: 3.500 vistas `Circle` serían
/// 3.500 nodos que SwiftUI tiene que diferenciar en cada cambio, y esto es puro
/// decorado.
///
/// - Important: la retícula es **solo visual**. No hay imán salvo que el outfit
///   active `snapToGrid`, que viene apagado: el requisito es conservar 32,56°
///   exactos, y un snap silencioso los destruiría.
public struct DotGridBackground: View {
    private let spacing: CGFloat

    public init(spacing: CGFloat = CanvasSpace.gridSpacing * 1.6) {
        self.spacing = spacing
    }

    public var body: some View {
        Canvas { context, size in
            // Gordos. A 6 pt la retícula se leía como suciedad; a 11 se lee
            // como papel de puntos, que es lo que es.
            let diameter: CGFloat = 11
            // Sobre cuántos puntos se apaga al acercarse al borde. Cortar la
            // retícula a hueso deja un canto duro que compite con el borde de
            // la pantalla; apagarla hace que el papel parezca seguir.
            let fade = spacing * 5

            var y = spacing
            while y < size.height {
                var x = spacing
                while x < size.width {
                    let edge = min(x, y, size.width - x, size.height - y)
                    let alpha = min(1, edge / fade)
                    // Por debajo de esto no se ve y sí cuesta: un `fill` por
                    // punto en una retícula de miles no es gratis.
                    if alpha > 0.02 {
                        context.fill(
                            Path(ellipseIn: CGRect(
                                origin: CGPoint(x: x, y: y),
                                size: CGSize(width: diameter, height: diameter)
                            )),
                            with: .color(WK.Palette.grid.opacity(0.75 * alpha))
                        )
                    }
                    x += spacing
                }
                y += spacing
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}
