import SwiftUI

/// Barrido de brillo en diagonal, recortado a la forma del contenido.
///
/// La clave es que va **enmascarado por el propio contenido**: el brillo
/// recorre la silueta de la prenda en vez de un rectángulo encima. Un shimmer
/// rectangular sobre un recorte delata que debajo hay una caja, que es
/// justamente lo que el recorte intenta que no se note.
///
/// En diagonal y desde arriba porque así se lee como luz que pasa por encima;
/// horizontal parece una barra de carga. Y muy desenfocado: el borde duro de
/// un degradado delata que es un rectángulo moviéndose.
public struct WKShimmer: ViewModifier {
    private let isActive: Bool
    @State private var phase: CGFloat = -1

    public init(isActive: Bool) {
        self.isActive = isActive
    }

    public func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    GeometryReader { proxy in
                        // La diagonal, no la suma de lados: con la suma la
                        // banda arrancaba y acababa dentro del contenido y
                        // dejaba esquinas sin barrer.
                        let span = (proxy.size.width * proxy.size.width
                            + proxy.size.height * proxy.size.height).squareRoot()

                        // Banda **estrecha y muy desenfocada**, no una cuña
                        // ancha. Un degradado ancho se ve como una mancha
                        // blanca cruzando; una franja fina con mucho blur se
                        // lee como luz. El desenfoque es horizontal al eje de
                        // la banda, así que se aplica antes de girarla.
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        .white.opacity(0.55),
                                        .clear,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: span * 0.22, height: span * 1.8)
                            .blur(radius: span * 0.06)
                            .rotationEffect(.degrees(24))
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                            .offset(x: phase * span * 1.1, y: phase * span * 0.45)
                            // Suma luz en vez de pintar encima: sobre una foto
                            // oscura se nota y sobre una clara no la quema.
                            .blendMode(.plusLighter)
                    }
                    // Recortado al contenido: el brillo sigue la prenda.
                    .mask { content }
                    .allowsHitTesting(false)
                }
            }
            .task(id: isActive) {
                guard isActive else { return }
                phase = -1.2
                // **Un turno de margen antes de animar.**
                //
                // Poner la fase inicial y animar en la misma pasada deja a
                // SwiftUI sin un estado "antes" que dibujar: toma los dos
                // valores como uno solo y no anima nada. El resultado era una
                // banda quieta fuera de cuadro, o sea, ningún brillo.
                await Task.yield()
                guard !Task.isCancelled else { return }

                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}

public extension View {
    /// Barrido de brillo mientras algo se está procesando.
    func wkShimmer(isActive: Bool) -> some View {
        modifier(WKShimmer(isActive: isActive))
    }
}
