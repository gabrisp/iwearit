import SwiftUI
import WKDesign

/// La barra del armario con ropa colgada: la portada del onboarding.
///
/// La primera pantalla era solo texto sobre gris, y lo primero que se ve de
/// una app de ropa tiene que ser ropa. Son las mismas siluetas que el armario
/// vacío —ver `WKGarmentSilhouette`—, pero **en color**: los tonos de tela del
/// onboarding, que son los que luego colgarán en las baldas.
struct OnboardingHangingRail: View {
    private struct Hanging {
        let silhouette: WKGarmentSilhouette
        let tone: OnboardingTone
        let width: CGFloat
    }

    /// Cuatro prendas: con cinco no caben en un iPhone pequeño sin encogerlas
    /// hasta que dejan de leerse.
    private static let items: [Hanging] = [
        .init(silhouette: .outer, tone: .granate, width: 84),
        .init(silhouette: .dress, tone: .denim, width: 74),
        .init(silhouette: .top, tone: .camel, width: 80),
        .init(silhouette: .pants, tone: .oliva, width: 58),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // La barra.
            Capsule()
                .fill(WK.Palette.ink(0.28))
                .frame(height: 4)
                .padding(.horizontal, WK.Spacing.s)

            HStack(alignment: .top, spacing: WK.Spacing.m) {
                ForEach(Array(Self.items.enumerated()), id: \.offset) { index, item in
                    HangingGarment(
                        silhouette: item.silhouette,
                        tone: item.tone,
                        width: item.width,
                        index: index
                    )
                }
            }
            // Las perchas cuelgan de la barra, no debajo de ella.
            .padding(.top, -3)
        }
        .accessibilityHidden(true)
    }
}

/// Una prenda en su percha, que cae y luego se mece.
///
/// Vista propia con su propio estado para que cada una lleve su desfase: si
/// el vaivén viviera en el padre, se moverían todas a la vez, que es lo que
/// delata que es una animación y no ropa.
private struct HangingGarment: View {
    let silhouette: WKGarmentSilhouette
    let tone: OnboardingTone
    let width: CGFloat
    let index: Int

    @State private var isSwaying = false
    @State private var hasDropped = false

    var body: some View {
        VStack(spacing: -6) {
            HangerShape()
                .stroke(WK.Palette.ink(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: width * 0.78, height: 26)
            WKGarmentShape(silhouette)
                .fill(tone.color.gradient)
                .frame(width: width, height: width / silhouette.aspectRatio)
                .shadow(color: tone.color.opacity(0.25), radius: 10, y: 6)
        }
        // Ancla arriba: una prenda colgada pivota desde la percha.
        .rotationEffect(.degrees(isSwaying ? 2.8 : -2.8), anchor: .top)
        .opacity(hasDropped ? 1 : 0)
        .offset(y: hasDropped ? 0 : -36)
        .task {
            withAnimation(WKAnimation.arrival.delay(0.1 + Double(index) * 0.1)) {
                hasDropped = true
            }
            withAnimation(
                .easeInOut(duration: 2.4 + Double(index) * 0.2)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.3)
            ) {
                isSwaying = true
            }
        }
    }
}

/// Una percha: el gancho arriba y los hombros abajo.
private struct HangerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let hookRadius: CGFloat = 4.5
        let hookCenter = CGPoint(x: rect.midX, y: rect.minY + hookRadius)
        let neck = CGPoint(x: rect.midX, y: rect.minY + hookRadius * 2 + 5)

        // El gancho: tres cuartos de vuelta, de la izquierda por arriba hasta
        // abajo, y de ahí baja al cuello.
        path.addArc(
            center: hookCenter,
            radius: hookRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(450),
            clockwise: false
        )
        path.addLine(to: neck)

        // Los hombros, en su propio trazo: cerrado desde el gancho, el cierre
        // volvía hasta el principio del arco y cruzaba la percha.
        path.move(to: neck)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    OnboardingHangingRail()
        .padding()
        .background(WK.Palette.canvas)
}
