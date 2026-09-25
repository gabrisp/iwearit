import SwiftUI
import WKDesign

/// **El dinero, dicho como en una conversación** (onboarding v2): una frase, y
/// la cifra girando como una rueda hasta pararse en la tuya, con las vecinas
/// desenfocadas por arriba y por abajo. Primero lo parado en el armario; luego
/// lo que Snazzy te ahorra. Los pasos de antes —`CalculatingStep`,
/// `SavingsStep`— siguen siendo los de la v1.
struct RevealStep: View {
    let model: OnboardingModel

    private enum Phase { case bad, good }
    @State private var phase: Phase = .bad
    @State private var showsNumber = false
    @State private var showsCaption = false
    @State private var showsCoda = false
    @State private var showsButton = false

    var body: some View {
        VStack(spacing: WK.Spacing.xl) {
            Spacer(minLength: 0)
            Group {
                switch phase {
                case .bad:
                    block(
                        title: String(localized: "reveal.bad.title", defaultValue: "The bad news:"),
                        lead: String(localized: "reveal.bad.lead2", defaultValue: "in your closet you have"),
                        value: model.idleValue,
                        caption: String(localized: "reveal.bad.caption2", defaultValue: "in clothes you barely wear."),
                        coda: String(localized: "reveal.bad.coda", defaultValue: "Yes, you read that right."),
                        tone: .granate
                    )
                case .good:
                    block(
                        title: String(localized: "reveal.good.title", defaultValue: "The good news:"),
                        lead: String(localized: "reveal.good.lead2", defaultValue: "Snazzy can save you"),
                        value: model.yearlySaving,
                        caption: String(localized: "reveal.good.caption2", defaultValue: "a year,"),
                        coda: String(localized: "reveal.good.coda", defaultValue: "wearing what you already have instead of buying more of the same."),
                        tone: .oliva
                    )
                }
            }
            .id(phase)
            .transition(.asymmetric(
                insertion: .opacity,
                removal: .opacity.combined(with: .offset(y: -30)).combined(with: AnyTransition(.blurReplace))
            ))
            Spacer(minLength: 0)
            // La nota va con el botón, debajo: aquí la tapaba. Ver
            // `onboardingButton(footnote:)`.
            // if showsButton { Text(… "reveal.footnote" …) }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.top, WK.Spacing.xxl)
        .onboardingButton(showsButton ? OnboardingButtonConfig(
            title: phase == .bad
                ? String(localized: "reveal.bad.button", defaultValue: "Change this")
                : String(localized: "reveal.good.button", defaultValue: "I want that"),
            footnote: String(localized: "reveal.footnote", defaultValue: "An estimate based on what you told us."),
            action: { next() }
        ) : nil)
        .task(id: phase) { await play() }
    }

    private func block(title: String, lead: String, value: Double, caption: String, coda: String, tone: OnboardingTone) -> some View {
        VStack(spacing: WK.Spacing.l) {
            // "La mala noticia:" en rojo, "La buena:" en verde, con brillo.
            GlowingText(text: title, tone: tone, size: 26)
            TypewriterText(text: lead)
                .font(WK.Font.title)
                .foregroundStyle(WK.Palette.primaryText)
                .multilineTextAlignment(.center)
            if showsNumber {
                NumberWheel(target: value, format: { model.money($0) }, tone: tone)
                    .transition(.opacity)
            }
            if showsCaption {
                TypewriterText(text: caption)
                    .font(WK.Font.title)
                    .foregroundStyle(WK.Palette.primaryText)
                    .multilineTextAlignment(.center)
            }
            // Y la coletilla, aparte y un poco después.
            if showsCoda {
                TypewriterText(text: coda)
                    .font(WK.Font.title)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func play() async {
        showsNumber = false
        showsCaption = false
        showsCoda = false
        withAnimation(.smooth) { showsButton = false }
        try? await Task.sleep(for: .seconds(1.2))
        withAnimation(.smooth) { showsNumber = true }
        try? await Task.sleep(for: .seconds(NumberWheel.duration + 0.3))
        withAnimation(.smooth) { showsCaption = true }
        try? await Task.sleep(for: .seconds(1.3))
        withAnimation(.smooth) { showsCoda = true }
        try? await Task.sleep(for: .seconds(1.6))
        withAnimation(.smooth(duration: 0.5)) { showsButton = true }
    }

    private func next() {
        switch phase {
        case .bad: withAnimation(.smooth(duration: 0.6)) { phase = .good }
        case .good: model.advance()
        }
    }
}

/// **La cifra como una rueda**: pasa por valores más pequeños, cada vez más
/// despacio, y se para en la tuya. Las de arriba y abajo se ven desenfocadas.
struct NumberWheel: View {
    let target: Double
    let format: (Double) -> String
    let tone: OnboardingTone

    /// Cuánto tarda en pararse.
    static let duration = 2.4
    private static let rowHeight: CGFloat = 64

    @State private var index = 0
    @State private var values: [Double] = []

    var body: some View {
        ZStack {
            ForEach(Array(values.enumerated()), id: \.offset) { offset, value in
                let distance = CGFloat(offset - index)
                Text(format(value))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tone.color)
                    .scaleEffect(1 - min(abs(distance), 2) * 0.22)
                    .opacity(abs(distance) > 2 ? 0 : 1 - abs(distance) * 0.45)
                    .blur(radius: abs(distance) * 3)
                    .offset(y: distance * Self.rowHeight * 0.8)
            }
        }
        .frame(height: Self.rowHeight * 2.6)
        .mask {
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3),
                        .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .sensoryFeedback(.selection, trigger: index)
        .task {
            // Doce pasos hasta la cifra, redondeados para que se lean.
            let steps = 12
            values = (0...steps).map { step in
                let fraction = 0.3 + 0.7 * Double(step) / Double(steps)
                return step == steps ? target : (target * fraction / 10).rounded() * 10
            }
            values.append(target * 1.08)
            index = 0
            // Cada vez más despacio: como una rueda que se frena.
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                try? await Task.sleep(for: .seconds(0.05 + 0.3 * t * t))
                withAnimation(.spring(duration: 0.35, bounce: step == steps ? 0.35 : 0.1)) { index = step }
            }
        }
    }
}
