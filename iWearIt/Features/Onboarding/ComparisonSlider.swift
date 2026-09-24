import SwiftUI
import WKDesign

/// Una fila de la comparativa: lo mismo con la app y sin ella.
struct ComparisonPair: Identifiable, Hashable, Sendable {
    let id: String
    let symbol: String
    let tone: OnboardingTone
    let with: String
    let without: String
}

/// **Antes y después, con un deslizador.**
///
/// La tabla de dos columnas con ✓ y ✕ se leía como la letra pequeña de un
/// contrato. Aquí son dos capas con las mismas filas en el mismo sitio —la de
/// hoy, gris; la de con la app, en color— y la barra del medio descubre una
/// sobre la otra: arrastrarla es ver cómo cada problema se convierte en su
/// solución, fila a fila.
struct ComparisonSlider: View {
    let pairs: [ComparisonPair]

    /// Dónde está la barra, de 0 (todo "sin") a 1 (todo "con").
    @State private var position: CGFloat = 0.5
    @State private var isDragging = false
    @State private var hasDemonstrated = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                // Debajo, lo de hoy.
                ComparisonPanel(pairs: pairs, isWith: false)
                // Encima, lo de con la app, descubierto hasta la barra.
                ComparisonPanel(pairs: pairs, isWith: true)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(0, width * position))
                    }

                handle(height: proxy.size.height)
                    .offset(x: width * position - 22)
            }
            .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
                    .stroke(WK.Palette.ink(0.10), lineWidth: 1)
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        position = min(0.97, max(0.03, value.location.x / max(1, width)))
                    }
                    .onEnded { _ in
                        isDragging = false
                        // Suelta cerca de un lado y se va a ese lado.
                        withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                            if position > 0.85 { position = 1 } else if position < 0.15 { position = 0 }
                        }
                    }
            )
        }
        .frame(height: 380)
        .sensoryFeedback(.selection, trigger: Int(position * 5))
        .task {
            // **El gesto, enseñado una vez**: la barra se pasea sola de un
            // lado a otro y vuelve al centro.
            guard !hasDemonstrated else { return }
            hasDemonstrated = true
            try? await Task.sleep(for: .milliseconds(700))
            for target in [0.18, 0.82, 0.5] as [CGFloat] {
                guard !isDragging else { return }
                withAnimation(.smooth(duration: 0.9)) { position = target }
                try? await Task.sleep(for: .milliseconds(950))
            }
        }
    }

    /// La barra y su tirador de cristal.
    private func handle(height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(.white)
                .frame(width: 3, height: height)
                .shadow(color: .black.opacity(0.15), radius: 3)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WK.Palette.primaryText)
                .frame(width: 44, height: 44)
                .adaptiveGlass(in: .circle)
                .scaleEffect(isDragging ? 1.12 : 1)
                .animation(WKAnimation.selection, value: isDragging)
        }
        .frame(width: 44)
        .allowsHitTesting(false)
    }
}

/// Una de las dos capas. Las filas van **en el mismo sitio** en las dos, para
/// que al pasar la barra cada una se transforme en su pareja.
private struct ComparisonPanel: View {
    let pairs: [ComparisonPair]
    let isWith: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cada etiqueta en el lado que enseña su capa: "con" a la
            // izquierda, que es lo que descubre la barra al ir a la derecha, y
            // "sin" a la derecha. Las dos a la izquierda, la de "sin" no se
            // veía nunca.
            HStack {
                if !isWith { Spacer() }
                Text(isWith ? String(localized: "onboarding.comparisonslider.withSnazzy", defaultValue: "With Snazzy") : String(localized: "onboarding.comparisonslider.withoutSnazzy", defaultValue: "Without Snazzy"))
                    .font(WK.Font.captionMedium)
                    .foregroundStyle(isWith ? OnboardingTone.oliva.color : WK.Palette.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        isWith ? OnboardingTone.oliva.soft : WK.Palette.ink(0.06),
                        in: .capsule
                    )
                if isWith { Spacer() }
            }
            .padding(.bottom, WK.Spacing.m)

            ForEach(pairs) { pair in
                HStack(spacing: WK.Spacing.m) {
                    if isWith {
                        ToneIcon(pair.symbol, tone: pair.tone, isFilled: true, size: 34)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(WK.Palette.tertiaryText)
                            .frame(width: 34, height: 34)
                            .background(WK.Palette.ink(0.06), in: .rect(cornerRadius: 10, style: .continuous))
                    }
                    Text(isWith ? pair.with : pair.without)
                        .font(isWith ? WK.Font.headline : WK.Font.callout)
                        .foregroundStyle(isWith ? WK.Palette.primaryText : WK.Palette.secondaryText)
                        .strikethrough(!isWith, color: WK.Palette.ink(0.25))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(WK.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                WK.Palette.shelf
                if isWith {
                    OnboardingTone.oliva.color.opacity(0.10)
                } else {
                    WK.Palette.ink(0.05)
                }
            }
        }
    }
}
