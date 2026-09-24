import SwiftUI
import WKCanvas
import WKCore
import WKDesign

/// "¿Te suena alguna?", **con el mismo gesto que la inspiración**.
///
/// Antes era una baraja propia: tarjetas grises, dos botones abajo y un
/// arrastre que no se parecía a nada de la app. Ahora cada frase es una
/// tarjeta como las de Inspo —papel de color, retícula de puntos, borde— y se
/// decide igual que un conjunto: de lado, con la píldora del centro diciendo
/// qué va a pasar y el golpecito al cruzar el umbral. Quien aprende aquí el
/// gesto ya sabe usar la inspiración.
///
/// La diferencia con Inspo: aquí **las dos direcciones pasan de tarjeta**. En
/// Inspo, el me gusta devuelve la tarjeta a su sitio porque el conjunto sigue
/// en la lista; aquí cada frase se contesta una vez y se va.
struct StatementSwipeDeck: View {
    let statements: [SwipeStatement]
    let onFinish: (Set<String>) -> Void

    @State private var index = 0
    @State private var agreed: Set<String> = []
    @State private var drag: CGFloat = 0
    @State private var isCommitted = false
    @State private var isLeaving = false
    /// La tarjeta que acaba de contestarse, saliendo volando. Aparte del
    /// montón para que la siguiente se adelante **mientras** esta se va, y no
    /// después: esperar a que saliera dejaba la siguiente apagada un rato.
    @State private var leaving: (position: Int, offset: CGFloat)?
    /// Lo que lee la píldora del centro. Ver `InspoSwipe`.
    @State private var swipe = InspoSwipe()
    @State private var hasDemonstrated = false

    /// Lo mismo que en Inspo. Ver `InspoLookCard.threshold`.
    private static let threshold: CGFloat = 120

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            ZStack {
                if let leaving {
                    StatementPaper(
                        statement: statements[leaving.position],
                        tone: .at(leaving.position),
                        progress: leaving.offset > 0 ? 1 : 0
                    )
                    .offset(x: leaving.offset)
                    .rotationEffect(.degrees(Double(leaving.offset / 60)))
                    .allowsHitTesting(false)
                    .zIndex(2)
                }
                ForEach(visibleIndices.reversed(), id: \.self) { position in
                    let isTop = position == index
                    StatementPaper(
                        statement: statements[position],
                        tone: .at(position),
                        progress: isTop ? agreeProgress : 0
                    )
                    .overlay(alignment: .topTrailing) {
                        if isTop { actions }
                    }
                    // La de detrás asoma un poco más abajo y más pequeña:
                    // que se intuya que hay más.
                    .scaleEffect(isTop ? 1 - min(0.03, abs(drag) / 3000) : 0.94)
                    .offset(y: isTop ? 0 : 16)
                    .offset(x: isTop ? drag : 0)
                    .rotationEffect(.degrees(isTop ? Double(drag / 60) : 0))
                    .opacity(isTop ? 1 : 0.7)
                    .allowsHitTesting(isTop)
                    .modifier(
                        SideSwipeArbitration(isOn: isTop && !isLeaving) { phase in
                            switch phase {
                            case let .change(amount): track(amount)
                            case let .end(distance, velocity): finish(distance, velocity: velocity)
                            }
                        }
                    )
                    .zIndex(isTop ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // **La misma píldora que Inspo**, con "me pasa" en vez de corazón.
            .overlay {
                InspoVerdictPill(
                    swipe: swipe,
                    agree: (empty: "checkmark", full: "checkmark", fill: OnboardingTone.oliva.color),
                    disagreeSymbol: "xmark"
                )
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: isCommitted) { _, new in new }
            .animation(.spring(duration: 0.4, bounce: 0.2), value: index)

            // Cuántas quedan, en puntos.
            HStack(spacing: 6) {
                ForEach(statements.indices, id: \.self) { position in
                    Capsule()
                        .fill(position <= index ? WK.Palette.primaryText : WK.Palette.ink(0.15))
                        .frame(width: position == index ? 18 : 6, height: 6)
                }
            }
            .animation(WKAnimation.selection, value: index)
        }
        .task {
            // **El gesto, enseñado una vez**, como en Inspo: la tarjeta se
            // asoma sola a un lado y al otro, sin llegar a decidir.
            guard !hasDemonstrated else { return }
            hasDemonstrated = true
            await demonstrate()
        }
    }

    /// Las dos tarjetas vivas. Ver la nota de `SwipeStatementDeck`: `index`
    /// llega a valer `statements.count` justo al acabar.
    private var visibleIndices: [Int] {
        guard index < statements.count else { return [] }
        return Array(index..<min(index + 2, statements.count))
    }

    /// Cuánto le falta al arrastre para contar como "me pasa", de 0 a 1.
    private var agreeProgress: CGFloat {
        guard drag > 0 else { return 0 }
        return min(1, drag / Self.threshold)
    }

    /// Los dos botones, en columna, como los de las tarjetas de Inspo.
    private var actions: some View {
        VStack(spacing: WK.Spacing.s) {
            WKCircleButton(size: .compact, action: { decide(agreeing: true) }) {
                FillingSymbol(
                    empty: "checkmark",
                    full: "checkmark",
                    progress: agreeProgress,
                    fill: OnboardingTone.oliva.color
                )
            }
            WKCircleButton("xmark", size: .compact) { decide(agreeing: false) }
                .tint(WK.Palette.primaryText)
        }
        .padding(WK.Spacing.m)
    }

    // MARK: - El gesto

    @MainActor
    private func demonstrate() async {
        try? await Task.sleep(for: .milliseconds(900))
        for step in [Self.threshold * 0.7, 0, -Self.threshold * 0.7, 0] {
            guard !isLeaving, index == 0 else { break }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                drag = step
                swipe.amount = step
            }
            try? await Task.sleep(for: .milliseconds(600))
        }
        swipe.amount = 0
    }

    private func track(_ amount: CGFloat) {
        drag = InspoLookCard.tracked(amount)
        swipe.amount = drag
        let crossed = abs(drag) >= Self.threshold
        if crossed != isCommitted { isCommitted = crossed }
    }

    private func finish(_ distance: CGFloat, velocity: CGFloat) {
        isCommitted = false
        swipe.amount = 0
        // La velocidad cuenta, como en Inspo.
        let projected = distance + velocity * 0.12
        guard abs(projected) >= Self.threshold else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { drag = 0 }
            return
        }
        decide(agreeing: projected > 0)
    }

    /// Contesta la frase de arriba: sale volando hacia su lado y entra la
    /// siguiente.
    private func decide(agreeing: Bool) {
        guard !isLeaving, index < statements.count else { return }
        isLeaving = true
        if agreeing { agreed.insert(statements[index].id) }
        swipe.amount = 0

        // La contestada pasa a volar por su cuenta, desde donde la dejó el
        // dedo; el montón se queda sin arrastre y la siguiente sube ya.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            leaving = (index, drag)
            drag = 0
        }
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) { index += 1 }
        withAnimation(.easeOut(duration: 0.3)) { leaving?.offset = agreeing ? 900 : -900 }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            leaving = nil
            isLeaving = false
            if index >= statements.count { onFinish(agreed) }
        }
    }
}

/// Una frase en su papel, como un conjunto de Inspo.
private struct StatementPaper: View {
    let statement: SwipeStatement
    let tone: OnboardingTone
    /// Cuánto se ha arrastrado hacia "me pasa": el papel se tiñe un poco.
    let progress: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.l) {
            if let symbol = statement.symbol {
                ToneIcon(symbol, tone: tone, isFilled: true, size: 56)
            }
            Spacer(minLength: 0)
            Image(systemName: "quote.opening")
                .font(.title.weight(.bold))
                .foregroundStyle(tone.color)
            Text(statement.text)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(WK.Palette.primaryText)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(WK.Spacing.l)
        .padding(.bottom, WK.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            // El papel: opaco, del tono de la tela, con la retícula de puntos
            // de los lienzos.
            ZStack {
                WK.Palette.shelf
                tone.color.opacity(0.16 + 0.1 * progress)
                // **A escala de lienzo**, como en las tarjetas de Inspo: la
                // retícula está pensada para dibujarse en el espacio del
                // canvas y reducirse. Dibujada a tamaño de pantalla, los
                // puntos salían gordos como lunares.
                GeometryReader { proxy in
                    let scale: CGFloat = 0.35
                    DotGridBackground(spacing: CanvasSpace.gridSpacing * 3)
                        .frame(width: proxy.size.width / scale, height: proxy.size.height / scale)
                        .scaleEffect(scale, anchor: .topLeading)
                }
                .opacity(0.5)
            }
        }
        .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
                .stroke(WK.Palette.ink(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
    }
}
