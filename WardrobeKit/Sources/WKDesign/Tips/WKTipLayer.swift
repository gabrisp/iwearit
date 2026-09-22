import SwiftUI

public extension View {

    /// La capa de avisos, **por encima de todo**.
    ///
    /// Se pone una sola vez en la raíz y no por pantalla: un aviso que
    /// apareciera dentro de una pila de navegación se iría al empujar la
    /// siguiente pantalla, y el que se enseña al abrir una hoja quedaría por
    /// debajo de ella. Arriba del todo, la tarjeta sobrevive a lo que pase por
    /// debajo — que es lo que se espera de algo que está explicando algo.
    func wkTipLayer(_ center: WKTipCenter) -> some View {
        overlay(alignment: .bottom) {
            if let tip = center.current {
                WKTipCard(tip: tip) { center.dismiss() }
                    .padding(.horizontal, WK.Spacing.screenInset)
                    // Por encima de la barra de pestañas, no encima de ella:
                    // la tarjeta explica algo y tapar los dos botones con los
                    // que se sale de la pantalla es la forma de que estorbe.
                    .padding(.bottom, WKTabBarMetrics.reservedHeight + WK.Spacing.m)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(WKAnimation.arrival, value: center.current)
    }

    /// Pide un aviso al entrar en la pantalla.
    ///
    /// Con un respiro: soltado en el mismo instante en que aparece la
    /// pantalla, la tarjeta compite con la animación de entrada y con lo que
    /// el usuario venía a hacer. Un segundo después ya está mirando.
    func wkTip(_ tip: WKTip, in center: WKTipCenter, after delay: Duration = .seconds(1)) -> some View {
        task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            center.offer(tip)
        }
    }
}

/// La tarjeta: qué se puede hacer, y el gesto dibujado haciéndolo.
struct WKTipCard: View {
    let tip: WKTip
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: WK.Spacing.m) {
            WKTipDemoView(demo: tip.demo)
                .frame(width: 52, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title)
                    .font(WK.Font.headline)
                    .foregroundStyle(WK.Palette.primaryText)
                Text(tip.message)
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .frame(width: 30, height: 30)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
        }
        .padding(WK.Spacing.m)
        .adaptiveGlass(in: .rect(cornerRadius: WK.Radius.card, style: .continuous))
        .shadow(color: WK.Palette.ink(0.18), radius: 18, y: 10)
    }
}

/// El gesto, dibujado.
///
/// Un dedo —un círculo— haciendo el movimiento de verdad, en bucle. No hay
/// vídeo ni imágenes: son dos formas y una animación, así que pesa cero y se
/// adapta al tema como el resto de la app.
struct WKTipDemoView: View {
    let demo: WKTipDemo

    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                .fill(WK.Palette.ink(0.05))

            switch demo {
            case .pull:
                piece
                    .offset(y: -14 + phase * 26)
                finger
                    .offset(y: -6 + phase * 26)
            case .drag:
                piece
                    .offset(x: -12 + phase * 24)
                finger
                    .offset(x: -12 + phase * 24, y: 8)
            case .stack:
                ForEach(0..<3, id: \.self) { index in
                    piece
                        .offset(x: CGFloat(index) * 9 - 9, y: CGFloat(index) * -4)
                        .opacity(phase > CGFloat(index) / 3 ? 1 : 0.25)
                }
            case .tap:
                piece
                    .scaleEffect(1 - phase * 0.12)
                finger
                    .offset(y: 10)
                    .opacity(0.4 + Double(phase) * 0.6)
            }
        }
        .task(id: demo) {
            // En bucle y con vuelta: el gesto se entiende viéndolo dos veces,
            // no una.
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.9)) { phase = 1 }
                try? await Task.sleep(for: .milliseconds(1000))
                withAnimation(.easeInOut(duration: 0.5)) { phase = 0 }
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }

    private var piece: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(WK.Palette.accent.opacity(0.75))
            .frame(width: 18, height: 22)
    }

    private var finger: some View {
        Circle()
            .fill(WK.Palette.primaryText.opacity(0.35))
            .frame(width: 14, height: 14)
    }
}
