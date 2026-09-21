import SwiftUI

public extension View {
    /// Seguir tirando al final del scroll dispara una acción.
    ///
    /// Va sobre un `ScrollView` —es lo único que tiene "final"—, pero se
    /// declara sobre `View` porque para cuando se encadena detrás de
    /// `scrollTargetBehavior` y compañía ya no es un `ScrollView` sino un
    /// `some View`, y acotarlo al tipo obligaba a ponerlo el primero de la
    /// cadena.
    ///
    /// ## Por qué esto y no un botón
    ///
    /// Porque el gesto ya lo estás haciendo. Llegas al último lienzo del día,
    /// sigues arrastrando hacia arriba porque quieres ver si hay más, y la
    /// respuesta es "no, pero puedes añadir otro". Un botón obliga a parar,
    /// buscar dónde está y apuntar; esto contesta en el mismo movimiento con
    /// el que has preguntado.
    ///
    /// Es el gesto que Threads usa para cerrar un hilo. La idea —y el cálculo
    /// del desbordamiento— vienen de la muestra de Balaji Venkatesh que me
    /// pasaste; aquí dispara una acción en vez de cerrar, y el indicador usa
    /// los tokens de la app.
    ///
    /// ## Lo que hace que no se dispare sin querer
    ///
    /// Tres cosas, y las tres importan:
    ///
    /// 1. **Solo si el gesto empezó cerca del final.** Un impulso fuerte desde
    ///    arriba llega al fondo con inercia y desbordaría sin que nadie haya
    ///    tirado de nada. Al empezar a arrastrar se decide si ese arrastre
    ///    puede disparar, y si no, no dispara por mucho que rebote.
    /// 2. **Al soltar, no al llegar.** Mientras el dedo está puesto se puede
    ///    volver atrás; el compromiso es soltar pasado el umbral.
    /// 3. **Una vez por gesto.** Hasta que el scroll no vuelve al final, no se
    ///    vuelve a armar.
    ///
    /// - Parameters:
    ///   - threshold: cuánto hay que desbordar, en puntos.
    ///   - symbol: el símbolo del indicador.
    ///   - action: se ejecuta al soltar pasado el umbral.
    @ViewBuilder
    func overscrollAction(
        threshold: CGFloat = 120,
        symbol: String = "plus",
        action: @MainActor @escaping () -> Void
    ) -> some View {
        modifier(OverscrollAction(threshold: threshold, symbol: symbol, action: action))
    }
}

private struct OverscrollAction: ViewModifier {
    let threshold: CGFloat
    let symbol: String
    let action: @MainActor () -> Void

    /// Cuánto se ha pasado del final. Negativo = desbordando.
    @State private var offset: CGFloat = 0
    @GestureState private var isDragging = false
    /// Si **este** arrastre puede disparar. Ver el punto 1 de la nota.
    @State private var isEligible = false
    /// Ya disparado: no se repite hasta volver al final.
    @State private var hasFired = false

    /// Cuánto sube el indicador desde debajo del borde antes de empezar a
    /// llenarse. Separa "estás desbordando" de "estás pidiendo algo".
    private static let revealDistance: CGFloat = 50

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            // `simultaneousGesture` sobre un `ScrollView` funciona desde iOS
            // 18. Antes había que envolverlo en UIKit para saber si el dedo
            // seguía puesto.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).updating($isDragging) { _, state, _ in
                    state = true
                }
            )
            .overlay(alignment: .bottom) { indicator }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let scrolled = geometry.contentOffset.y + geometry.contentInsets.top
                let scrollable = max(geometry.contentSize.height - geometry.containerSize.height, 0)
                // Distancia al final: 0 justo en el fondo, negativa al
                // desbordar.
                return scrollable - scrolled
            } action: { _, new in
                offset = new
                fireIfDue()
            }
            .onChange(of: isDragging) { _, dragging in
                if dragging { isEligible = offset < threshold * 1.2 }
                fireIfDue()
            }
    }

    /// El progreso del indicador, 0-1. Cero mientras este arrastre no pueda
    /// disparar: sin eso, un rebote por inercia dibujaría un aro llenándose
    /// que no va a hacer nada.
    private var progress: CGFloat {
        let overscroll = offset < 0 ? -offset : 0
        guard isEligible, threshold > Self.revealDistance else { return 0 }
        let raw = (overscroll - Self.revealDistance) / (threshold - Self.revealDistance)
        return hasFired ? 1 : min(max(raw, 0), 1)
    }

    /// Cuánto asoma el indicador. Sube antes de empezar a llenarse.
    private var reveal: CGFloat {
        let overscroll = offset < 0 ? -offset : 0
        return min(max(overscroll / Self.revealDistance, 0), 1)
    }

    private var indicator: some View {
        let isFull = progress == 1

        return ZStack {
            Circle()
                .fill(WK.Palette.primaryText)
                .opacity(isFull ? 1 : 0)

            // Se llena por los dos lados a la vez y no como un reloj: así no
            // hay un punto de inicio que mirar, y el gesto se lee como algo
            // que se cierra.
            ZStack {
                ArcHalf(progress: progress)
                ArcHalf(progress: progress).scaleEffect(x: -1)
            }
            .padding(3)

            Image(systemName: symbol)
                .font(WK.Font.headline)
                .foregroundStyle(isFull ? WK.Palette.canvas : WK.Palette.primaryText)
        }
        .frame(width: 55, height: 55)
        // Un rebote corto al completarse: dice "ya está" antes de que sueltes,
        // que es lo que evita soltar a medias y no entender por qué no pasó
        // nada.
        .keyframeAnimator(initialValue: 1.0, trigger: isFull) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            CubicKeyframe(1.1, duration: 0.15)
            CubicKeyframe(1, duration: 0.15)
        }
        .allowsHitTesting(false)
        .offset(y: Self.revealDistance - (Self.revealDistance * reveal))
        .opacity(reveal)
        .sensoryFeedback(.selection, trigger: isFull) { _, new in new }
    }

    private func fireIfDue() {
        if !isDragging, isEligible, -offset >= threshold, !hasFired {
            action()
            hasFired = true
        }
        // Se rearma al volver al final. Con margen: pedir exactamente 0 no
        // ocurre casi nunca porque el rebote deja décimas.
        if hasFired, !isDragging, offset.rounded() > -10 {
            hasFired = false
        }
    }
}

/// Media circunferencia que se dibuja según el progreso.
private struct ArcHalf: View {
    let progress: CGFloat

    var body: some View {
        Circle()
            .trim(from: 0, to: progress / 2)
            .stroke(WK.Palette.primaryText, lineWidth: 3)
            .rotationEffect(.degrees(90))
    }
}
