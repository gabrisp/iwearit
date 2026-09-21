import CoreGraphics
import SwiftUI
import WKDesign

/// Lo detectado, **dibujado encima de la foto**.
///
/// ## Por qué encima y no solo abajo
///
/// Una rejilla de recortes contesta "qué ha salido", pero no "de dónde". Y lo
/// que se quiere corregir es justo eso: que el recuadro se comió medio
/// pantalón, que ese de ahí era el sofá, que la camisa sigue un palmo más
/// abajo. Señalarlo sobre la foto es inmediato —se arrastra la esquina y ya—
/// mientras que rodear la prenda a mano es un trazo entero por cada arreglo.
///
/// El recuadro **no es el recorte**: es dónde mirar. Al soltarlo se rehace el
/// recorte ahí dentro con el detector de contornos del propio teléfono, así
/// que mover una esquina no da un rectángulo de foto, da la prenda.
struct ImportDetectionBoxes: View {
    let photo: CGImage
    let candidates: [ImportCandidate]
    /// El recuadro nuevo, normalizado 0-1 con el origen arriba-izquierda.
    let onChange: (ImportCandidate, CGRect) -> Void
    let onDiscard: (ImportCandidate) -> Void

    var body: some View {
        GeometryReader { proxy in
            let fit = fitted(in: proxy.size)

            ForEach(candidates) { candidate in
                if let rect = candidate.rect {
                    ImportDetectionBox(
                        normalized: rect,
                        fit: fit,
                        isKept: candidate.isKept,
                        isBusy: candidate.isRecropping,
                        onCommit: { onChange(candidate, $0) },
                        onDiscard: { onDiscard(candidate) }
                    )
                }
            }
        }
    }

    /// Dónde cae la foto de verdad dentro de la vista.
    ///
    /// `scaledToFit` deja franjas a los lados o arriba y abajo, y un recuadro
    /// colocado sobre la vista entera en vez de sobre la foto aparece
    /// desplazado justo en las fotos verticales, que son todas.
    private func fitted(in size: CGSize) -> CGRect {
        let ratio = CGFloat(photo.width) / CGFloat(max(photo.height, 1))
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
}

/// Un recuadro: se mueve, se estira por la esquina y se quita con la X.
private struct ImportDetectionBox: View {
    let normalized: CGRect
    let fit: CGRect
    let isKept: Bool
    /// Mientras se rehace el recorte de ese sitio.
    let isBusy: Bool
    let onCommit: (CGRect) -> Void
    let onDiscard: () -> Void

    /// Lo que dura el gesto. Se escribe al soltar y no por frame: cada cambio
    /// rehace un recorte, y rehacerlo sesenta veces por segundo es colgar la
    /// pantalla a cambio de nada.
    @State private var move: CGSize = .zero
    @State private var grow: CGSize = .zero

    /// El lado más pequeño que se puede dejar, en fracción de foto. Por debajo
    /// de esto no hay prenda que recortar, solo una mota.
    private static let minimumSide: CGFloat = 0.06
    private static let handle: CGFloat = 28

    private var box: CGRect {
        CGRect(
            x: fit.minX + normalized.minX * fit.width + move.width,
            y: fit.minY + normalized.minY * fit.height + move.height,
            width: max(normalized.width * fit.width + grow.width, Self.minimumSide * fit.width),
            height: max(normalized.height * fit.height + grow.height, Self.minimumSide * fit.height)
        )
    }

    var body: some View {
        let box = box

        RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
            .stroke(WK.Palette.accent.opacity(isKept ? 1 : 0.35), lineWidth: 2)
            .background {
                RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                    .fill(WK.Palette.accent.opacity(isKept ? 0.10 : 0.03))
            }
            .overlay(alignment: .topLeading) { close }
            .overlay(alignment: .bottomTrailing) { corner }
            .overlay {
                if isBusy {
                    ProgressView().controlSize(.small).tint(WK.Palette.accent)
                }
            }
            .frame(width: box.width, height: box.height)
            .position(x: box.midX, y: box.midY)
            .contentShape(.rect)
            .gesture(
                DragGesture()
                    .onChanged { move = $0.translation }
                    .onEnded { _ in commit() }
            )
            .animation(WKAnimation.selection, value: isKept)
    }

    /// La X: quita el recuadro y con él la prenda.
    private var close: some View {
        Button(action: onDiscard) {
            Image(systemName: "xmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WK.Palette.onAccent)
                .padding(5)
                .background(Circle().fill(WK.Palette.accent))
                // Mucho más grande que el dibujo: en una foto de 300 puntos el
                // aspa mide diez, y diez puntos no se aciertan con el pulgar.
                .frame(width: Self.handle, height: Self.handle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .offset(x: -Self.handle / 3, y: -Self.handle / 3)
    }

    /// La esquina de estirar.
    private var corner: some View {
        Circle()
            .fill(WK.Palette.accent)
            .frame(width: 14, height: 14)
            .frame(width: Self.handle, height: Self.handle)
            .contentShape(.circle)
            .offset(x: Self.handle / 3, y: Self.handle / 3)
            .gesture(
                DragGesture()
                    .onChanged { grow = $0.translation }
                    .onEnded { _ in commit() }
            )
    }

    /// De vuelta a coordenadas de foto, y dentro de la foto.
    private func commit() {
        let box = box
        var rect = CGRect(
            x: (box.minX - fit.minX) / fit.width,
            y: (box.minY - fit.minY) / fit.height,
            width: box.width / fit.width,
            height: box.height / fit.height
        )
        // Recortado a la foto: un recuadro que se sale no se puede recortar, y
        // dejarlo salir es prometer píxeles que no existen.
        rect.origin.x = min(max(rect.minX, 0), 1 - Self.minimumSide)
        rect.origin.y = min(max(rect.minY, 0), 1 - Self.minimumSide)
        rect.size.width = min(max(rect.width, Self.minimumSide), 1 - rect.minX)
        rect.size.height = min(max(rect.height, Self.minimumSide), 1 - rect.minY)

        move = .zero
        grow = .zero
        onCommit(rect)
    }
}
