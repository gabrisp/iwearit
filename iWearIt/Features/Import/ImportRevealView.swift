import CoreGraphics
import SwiftUI
import WKDesign
import WKVision

/// La foto mientras se analiza, y las prendas saliendo de ella.
///
/// El recorte no aparece de la nada en una lista: arranca **en el sitio exacto
/// de la foto donde estaba la prenda** (`sourceRect`), la foto se apaga
/// detrás, y desde ahí las prendas se recolocan en fila. Esa continuidad es lo
/// que hace entender qué ha pasado sin leer un texto que lo explique.
///
/// Toda la animación es de posición y escala. El tamaño de la caja de cada
/// prenda no cambia nunca: cambiar `frame` a mitad de animación obliga a
/// relayout por frame y se nota; `scaleEffect` lo resuelve el renderizador.
struct ImportRevealView: View {
    let photo: CGImage
    let candidates: [ImportCandidate]
    /// `true` en cuanto el pipeline ha terminado. Hasta entonces solo brilla.
    let isScanning: Bool
    let onFinished: () -> Void

    @State private var stage: Stage = .scanning

    private enum Stage {
        /// Barrido sobre la foto.
        case scanning
        /// Los recortes se encienden donde estaban.
        case emerging
        /// Y se van a su fila.
        case arranged
    }

    /// Caja fija de cada prenda ya recolocada.
    private static let box = CGSize(width: 96, height: 128)

    var body: some View {
        GeometryReader { proxy in
            let frame = photoFrame(in: proxy.size)

            ZStack {
                Image(decorative: photo, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: WK.Radius.card, style: .continuous))
                    .wkShimmer(isActive: stage == .scanning)
                    .opacity(stage == .scanning ? 1 : 0.12)
                    .blur(radius: stage == .scanning ? 0 : 6)
                    .scaleEffect(stage == .arranged ? 0.96 : 1)

                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    RevealedCrop(
                        candidate: candidate,
                        box: Self.box,
                        // En `emerging` ocupa lo mismo que ocupaba en la foto;
                        // en `arranged`, su tamaño natural en la fila.
                        scale: stage == .scanning
                            ? photoScale(for: candidate, in: frame)
                            : (stage == .emerging ? photoScale(for: candidate, in: frame) : 1),
                        position: stage == .arranged
                            ? arrangedPosition(index: index, in: proxy.size)
                            : photoPosition(for: candidate, in: frame),
                        isVisible: stage != .scanning
                    )
                    .animation(
                        WKAnimation.arrival.delay(Double(index) * 0.09),
                        value: stage
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .task(id: isScanning) { await runSequence() }
    }

    // MARK: Secuencia

    private func runSequence() async {
        guard !isScanning else { return }
        // Sin prendas no hay nada que revelar, pero **sí hay que terminar**:
        // si no, la pantalla se queda con la foto y el barrido dando vueltas
        // para siempre en vez de decir que no ha encontrado nada.
        guard !candidates.isEmpty else {
            onFinished()
            return
        }

        withAnimation(WKAnimation.content) { stage = .emerging }
        // Lo suficiente para ver de dónde ha salido cada prenda, y ni un
        // segundo más: esto se ve una vez por foto, no es una animación de
        // bienvenida.
        try? await Task.sleep(for: .milliseconds(620))

        withAnimation(WKAnimation.arrival) { stage = .arranged }
        try? await Task.sleep(for: .milliseconds(780))

        onFinished()
    }

    // MARK: Geometría

    /// Dónde cae la foto dentro del hueco, con `scaledToFit`.
    private func photoFrame(in size: CGSize) -> CGRect {
        let ratio = Double(photo.width) / Double(photo.height)
        var width = size.width
        var height = width / ratio
        if height > size.height {
            height = size.height
            width = height * ratio
        }
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }

    /// Centro de la prenda dentro de la foto. Sin `sourceRect`, el centro.
    private func photoPosition(for candidate: ImportCandidate, in frame: CGRect) -> CGPoint {
        guard let rect = candidate.detected.sourceRect else { return CGPoint(x: frame.midX, y: frame.midY) }
        return CGPoint(
            x: frame.minX + rect.midX * frame.width,
            y: frame.minY + rect.midY * frame.height
        )
    }

    /// Cuánto hay que encoger la caja para que ocupe lo que ocupaba en la foto.
    private func photoScale(for candidate: ImportCandidate, in frame: CGRect) -> CGFloat {
        guard let rect = candidate.detected.sourceRect else { return 0.6 }
        let width = rect.width * frame.width
        let height = rect.height * frame.height
        return max(0.15, min(width / Self.box.width, height / Self.box.height))
    }

    /// Fila centrada, con reparto uniforme.
    private func arrangedPosition(index: Int, in size: CGSize) -> CGPoint {
        let count = max(candidates.count, 1)
        let spacing = min(Self.box.width + WK.Spacing.m, size.width / CGFloat(count))
        let totalWidth = spacing * CGFloat(count - 1)
        return CGPoint(
            x: size.width / 2 - totalWidth / 2 + spacing * CGFloat(index),
            y: size.height / 2
        )
    }
}

/// Un recorte durante la revelación.
///
/// Vista propia: son cuatro a la vez animándose con retardos distintos, y cada
/// una tiene que poder invalidarse sin arrastrar a las demás.
private struct RevealedCrop: View {
    let candidate: ImportCandidate
    let box: CGSize
    let scale: CGFloat
    let position: CGPoint
    let isVisible: Bool

    var body: some View {
        candidate.image
            .resizable()
            .scaledToFit()
            .frame(width: box.width, height: box.height)
            // La sombra crece con la prenda: mientras está dentro de la foto
            // está pegada a ella, y al salir se despega.
            .shadow(color: WK.Palette.ink(0.5), radius: isVisible ? 2 : 0, y: 1)
            .shadow(color: WK.Palette.ink(0.15), radius: isVisible ? 16 : 0, y: 10)
            .scaleEffect(scale)
            .opacity(isVisible ? 1 : 0)
            .position(position)
    }
}
