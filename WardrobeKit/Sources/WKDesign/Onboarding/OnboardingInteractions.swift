import SwiftUI

// MARK: - Tarjetas de identificación

public struct SwipeStatement: Identifiable, Hashable, Sendable {
    public let id: String
    public let text: String
    /// SF Symbol que acompaña a la frase en su tarjeta.
    public let symbol: String?
    public init(id: String, text: String, symbol: String? = nil) {
        self.id = id
        self.text = text
        self.symbol = symbol
    }
}

/// Baraja tipo Tinder para afirmaciones con las que el usuario se identifica.
///
/// Es una encuesta disfrazada, y disfrazarla importa: las mismas frases en una
/// lista de casillas se responden a la ligera, y aquí cada una exige un gesto
/// deliberado. Las frases van en primera persona —"Compro ropa parecida a la
/// que ya tengo"— para que asentir sea admitir algo propio.
public struct SwipeStatementDeck: View {
    private let statements: [SwipeStatement]
    private let onFinish: (Set<String>) -> Void

    @State private var index = 0
    @State private var agreed: Set<String> = []
    @State private var drag: CGSize = .zero
    @State private var isAdvancing = false

    public init(statements: [SwipeStatement], onFinish: @escaping (Set<String>) -> Void) {
        self.statements = statements
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: WK.Spacing.l) {
            ZStack {
                // Solo dos tarjetas vivas: la de debajo existe para que se
                // intuya que hay más, no para poder tocarla.
                ForEach(visibleIndices.reversed(), id: \.self) { position in
                    StatementCard(text: statements[position].text, tone: .at(position))
                        .scaleEffect(position == index ? 1 : 0.94)
                        .offset(y: position == index ? 0 : 14)
                        .offset(position == index ? drag : .zero)
                        .rotationEffect(.degrees(position == index ? drag.width / 22 : 0))
                        .opacity(position == index ? 1 : 0.55)
                        .allowsHitTesting(position == index)
                        .gesture(position == index ? dragGesture : nil)
                }
            }
            .frame(height: 220)
            .animation(.snappy(duration: 0.28), value: index)

            HStack(spacing: WK.Spacing.xl) {
                DeckButton(symbol: "xmark", tint: WK.Palette.secondaryText) { advance(agreeing: false) }
                DeckButton(symbol: "checkmark", tint: OnboardingTone.oliva.color) { advance(agreeing: true) }
            }

            Text(String(localized: "common.of", defaultValue: "\(String(describing: min(index + 1, statements.count))) of \(String(describing: statements.count))", bundle: .module))
                .font(.caption)
                .foregroundStyle(WK.Palette.secondaryText)
                .monospacedDigit()
        }
    }

    /// Las dos tarjetas vivas.
    ///
    /// La guarda no es defensiva por si acaso: `index` **llega** a valer
    /// `statements.count` —es el estado "ya has contestado a todas", que dura
    /// los milisegundos entre la última tarjeta y el cambio de paso— y sin
    /// ella el rango queda `count..<count` con `index + 2` por debajo del
    /// límite inferior en cuanto se pasa de largo, que es un `fatalError`.
    private var visibleIndices: [Int] {
        guard index < statements.count else { return [] }
        return Array(index..<min(index + 2, statements.count))
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                // 110 pt: por debajo se lee como un titubeo, no como una
                // respuesta, y se devuelve la tarjeta a su sitio.
                if abs(value.translation.width) > 110 {
                    advance(agreeing: value.translation.width > 0)
                } else {
                    withAnimation(.snappy(duration: 0.25)) { drag = .zero }
                }
            }
    }

    /// Pasa de tarjeta.
    ///
    /// `isAdvancing` es lo que impide el desbordamiento de verdad. El índice no
    /// sube hasta 180 ms después —lo que dura la tarjeta saliendo—, así que un
    /// deslizamiento y un toque en el botón en el mismo frame **pasaban los dos
    /// la guarda** con el mismo índice y luego incrementaban dos veces. Con la
    /// última tarjeta eso dejaba `index` por encima del número de frases y la
    /// app se caía al construir el rango.
    private func advance(agreeing: Bool) {
        guard !isAdvancing, index < statements.count else { return }
        isAdvancing = true
        if agreeing { agreed.insert(statements[index].id) }

        withAnimation(.snappy(duration: 0.22)) {
            drag = CGSize(width: agreeing ? 520 : -520, height: 0)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            drag = .zero
            index += 1
            isAdvancing = false
            if index >= statements.count { onFinish(agreed) }
        }
    }
}

private struct StatementCard: View {
    let text: String
    /// Cada tarjeta en un tono: al pasar se nota que cambia de frase, y la de
    /// debajo asoma en otro color.
    let tone: OnboardingTone

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.m) {
            Image(systemName: "quote.opening")
                .font(.title2.weight(.bold))
                .foregroundStyle(tone.color)
            Text(text)
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(WK.Palette.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(WK.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Opaca por debajo: el tono suave es transparente, y la tarjeta de
        // detrás se veía a través.
        .background {
            RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
                .fill(WK.Palette.shelf)
            RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
                .fill(tone.soft)
        }
        .overlay(
            RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
                .strokeBorder(tone.color.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct DeckButton: View {
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 60, height: 60)
                // .background(WK.Palette.shelf, in: .circle)
                // .overlay(Circle().stroke(WK.Palette.ink(0.10), lineWidth: 1))
                .contentShape(.circle)
        }
        // Cristal interactivo: ver `OptionRow`.
        .buttonStyle(.plain)
        .adaptiveGlassInteractive(in: .circle)
        .sensoryFeedback(.impact(weight: .light), trigger: symbol)
    }
}

// MARK: - Cantidades

/// Selector de una cantidad con unidades.
///
/// Un `Slider` suelto no dice nada; el número grande encima es lo que convierte
/// el gesto en un dato que el usuario reconoce como suyo — y en lo que luego
/// sostiene el cálculo del ahorro.
public struct ValueStepperSlider: View {
    private let range: ClosedRange<Double>
    private let step: Double
    private let format: (Double) -> String
    @Binding private var value: Double

    public init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1,
        format: @escaping (Double) -> String
    ) {
        _value = value
        self.range = range
        self.step = step
        self.format = format
    }

    public var body: some View {
        VStack(spacing: WK.Spacing.l) {
            Text(format(value))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(WK.Palette.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: value)

            Slider(value: $value, in: range, step: step)
                .tint(WK.Palette.accent)

            HStack {
                Text(format(range.lowerBound))
                Spacer()
                Text(format(range.upperBound))
            }
            .font(.caption)
            .foregroundStyle(WK.Palette.secondaryText)
        }
        .sensoryFeedback(.selection, trigger: value)
    }
}

// MARK: - Momentos

/// Pantalla de procesado.
///
/// Existe por efecto psicológico: hace que lo siguiente parezca calculado para
/// el usuario en vez de servido de golpe. Cuando además hay trabajo real
/// detrás —el escaneo de la galería— la misma vista informa del progreso.
public struct ProcessingView: View {
    private let title: String
    private let steps: [String]
    @State private var visibleSteps = 0

    public init(title: String, steps: [String]) {
        self.title = title
        self.steps = steps
    }

    public var body: some View {
        VStack(spacing: WK.Spacing.xl) {
            // ProgressView().controlSize(.large)
            // Un anillo con los tonos de tela girando, en vez de la ruedecita
            // de sistema: es el mismo "estoy pensando", pero suena a la app.
            ToneSpinner()
                .frame(width: 64, height: 64)

            Text(title)
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(WK.Palette.primaryText)

            VStack(alignment: .leading, spacing: WK.Spacing.m) {
                ForEach(Array(steps.prefix(visibleSteps).enumerated()), id: \.offset) { index, step in
                    HStack(spacing: WK.Spacing.m) {
                        ToneIcon("checkmark", tone: .at(index), isFilled: true, size: 28)
                        Text(step)
                            .font(.subheadline)
                            .foregroundStyle(WK.Palette.primaryText)
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            for index in steps.indices {
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(.snappy) { visibleSteps = index + 1 }
            }
        }
    }
}

/// Un anillo que gira con los tonos de tela.
///
/// Un solo cambio de estado: el giro lo hace `repeatForever` en el
/// renderizador, no un `TimelineView` reevaluando la vista cada frame.
private struct ToneSpinner: View {
    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.92)
            .stroke(
                AngularGradient(
                    colors: OnboardingTone.allCases.map(\.color),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 7, lineCap: .round)
            )
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    isSpinning = true
                }
            }
            .accessibilityLabel(String(localized: "wkdesign.onboardinginteractions.calculating", defaultValue: "Calculating", bundle: .module))
    }
}

/// Un número grande con su explicación: el momento de "esto va de ti".
public struct StatReveal: View {
    private let value: String
    private let caption: String
    private let detail: String?
    /// El tono del número. Sin tono, el color del texto.
    private let tone: OnboardingTone?
    @State private var hasAppeared = false

    public init(value: String, caption: String, detail: String? = nil, tone: OnboardingTone? = nil) {
        self.value = value
        self.caption = caption
        self.detail = detail
        self.tone = tone
    }

    public var body: some View {
        VStack(spacing: WK.Spacing.s) {
            Text(value)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(tone?.color ?? WK.Palette.primaryText)
                .monospacedDigit()
                .scaleEffect(hasAppeared ? 1 : 0.7)
                .opacity(hasAppeared ? 1 : 0)

            Text(caption)
                .font(.headline)
                .foregroundStyle(WK.Palette.primaryText)
                .multilineTextAlignment(.center)

            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .task {
            withAnimation(.spring(duration: 0.5, bounce: 0.35)) { hasAppeared = true }
        }
    }
}
