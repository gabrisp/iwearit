import SwiftUI
import WKCanvas
import WKCore
import WKDesign

/// Una tarjeta **a medio hacer**, con su brillo pasando por encima.
///
/// ## Por qué esto y no un cartel
///
/// Porque el cartel de "todavía no hay nada que proponer" para la pantalla en
/// seco: es una pared, y encima llega antes que la primera propuesta —que
/// muchas veces está a medio segundo de aparecer—. Una tarjeta con la silueta
/// de un conjunto y un barrido de luz dice lo mismo sin decir nada: aquí va a
/// haber algo, y se está montando.
///
/// Y cuando de verdad no puede haberlo —una maleta con una sola prenda— lo que
/// falta se cuenta en la píldora de arriba, que es una línea, no una pared.
struct InspoPlaceholderCard: View {
    /// El papel, que es el de la pantalla donde esté: el de la inspiración o
    /// el de la maleta.
    var backdrop: Color = WK.Palette.canvas

    var body: some View {
        ZStack {
            backdrop
            DotGridBackground(spacing: CanvasSpace.gridSpacing * 3)
                .opacity(0.5)

            // La silueta de un conjunto: arriba, abajo y calzado. Las mismas
            // tres piezas que tiene cualquier propuesta, en hueco.
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                VStack(spacing: height * 0.03) {
                    block(width: width * 0.52, height: height * 0.3)
                    block(width: width * 0.34, height: height * 0.34)
                    block(width: width * 0.4, height: height * 0.08)
                }
                .frame(width: width, height: height)
            }
            .padding(.vertical, WK.Spacing.xl)
        }
        .aspectRatio(CanvasSpace.width / CanvasSpace.height, contentMode: .fit)
        .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
                .stroke(WK.Palette.ink(0.12), lineWidth: 1)
        }
        // El barrido, sobre la tarjeta entera: es lo que la convierte en "se
        // está montando" en vez de "esto está vacío".
        .wkShimmer(isActive: true)
        .allowsHitTesting(false)
    }

    private func block(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
            .fill(WK.Palette.ink(0.06))
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity)
    }
}
