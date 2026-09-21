import SwiftUI
import WKDesign

/// El armario cuando todavía no hay nada dentro.
///
/// No es un `ContentUnavailableView`: un armario vacío es el primer minuto de
/// la app para todo el mundo, y ese minuto decide si alguien vuelve. Así que
/// hay ropa — en silueta, colgada y meciéndose — y una sola cosa que hacer.
struct ClosetEmptyState: View {
    let onAdd: () -> Void

    /// Tres perchas. Cuatro llenan la pantalla y dejan de leerse como un hueco
    /// que hay que llenar, que es justo lo que tiene que transmitir.
    private static let hanging: [WKGarmentSilhouette] = [.outer, .top, .dress]

    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: WK.Spacing.xl) {
            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: WK.Spacing.l) {
                ForEach(Array(Self.hanging.enumerated()), id: \.offset) { index, silhouette in
                    SwayingSilhouette(silhouette: silhouette, index: index)
                }
            }
            .frame(height: 190)

            VStack(spacing: WK.Spacing.s) {
                Text("Tu armario está vacío")
                    .font(WK.Font.title)
                    .foregroundStyle(WK.Palette.primaryText)

                Text("Sube una foto y se recortan las prendas solas. Nada sale de tu iPhone.")
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)

            WKPrimaryButton("Añadir prendas", systemImage: "plus", action: onAdd)
                .frame(maxWidth: 260)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 12)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // El texto entra después de la ropa: primero se ve de qué va esto,
            // y luego se lee. Al revés, la animación tapa la frase.
            withAnimation(WKAnimation.content.delay(0.45)) { hasAppeared = true }
        }
    }
}

/// Una prenda colgada que se mece.
///
/// Vista propia con su propio estado: cada percha lleva su desfase, y si el
/// balanceo viviera en el padre las tres se moverían a la vez, que es
/// exactamente lo que delata que es una animación y no ropa.
///
/// **Un solo cambio de estado en toda la vida de la vista.** El vaivén lo hace
/// `repeatForever` en el renderizador, no una reevaluación de `body` por frame
/// — que es lo que pasaría con un `TimelineView` y se notaría al hacer scroll.
private struct SwayingSilhouette: View {
    let silhouette: WKGarmentSilhouette
    let index: Int

    @State private var isSwaying = false
    @State private var hasDropped = false

    private var width: CGFloat { index == 1 ? 104 : 88 }

    var body: some View {
        WKGarmentShape(silhouette)
            .fill(WK.Palette.ink(0.13))
            .frame(width: width, height: width / silhouette.aspectRatio)
            // Ancla arriba: una prenda colgada pivota desde la percha, no desde
            // su centro. Con el ancla por defecto parece que levita.
            .rotationEffect(.degrees(isSwaying ? 3.2 : -3.2), anchor: .top)
            .opacity(hasDropped ? 1 : 0)
            .offset(y: hasDropped ? 0 : -28)
            .task {
                withAnimation(WKAnimation.arrival.delay(Double(index) * 0.12)) {
                    hasDropped = true
                }
                withAnimation(
                    .easeInOut(duration: 2.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.35)
                ) {
                    isSwaying = true
                }
            }
    }
}

#Preview {
    ClosetEmptyState {}
        .background(WK.Palette.canvas)
}
