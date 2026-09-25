import SwiftUI
import WKDesign

/// **Las primeras preguntas, como una conversación.** Snazzy escribe —letra a
/// letra—, pregunta, tú contestas, y lo dicho sube y se apaga bajo el borde de
/// arriba mientras lo nuevo aparece debajo. Sustituye a los pasos sueltos de
/// objetivo, dolores, gasto y tamaño del armario, que siguen en el código.
struct ConversationStep: View {
    let model: OnboardingModel

    /// Una pieza de la conversación.
    private enum Item: Identifiable, Equatable {
        case line(id: Int, text: String)
        case answer(id: Int, text: String)
        case progress(id: Int)
        /// Una cifra que importa, sola en su línea: en color, con brillo.
        case highlight(id: Int, text: String)

        var id: Int {
            switch self {
            case let .line(id, _), let .answer(id, _), let .progress(id), let .highlight(id, _): id
            }
        }
    }

    /// Qué se le está preguntando ahora mismo.
    private enum Question: Equatable { case goal, pains, spend, wardrobe, done }

    @State private var items: [Item] = []
    @State private var question: Question?
    @State private var nextID = 0
    @State private var pains: Set<String> = []
    @State private var spend: Double = 60
    @State private var wardrobe: Double = 80
    @State private var analysis: Double = 0
    @State private var hasStarted = false

    /// Tamaño de conversación, no de titular.
    private static let lineFont = Font.custom("PlusJakartaSans-SemiBold", size: 19, relativeTo: .headline)

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .center, spacing: WK.Spacing.l) {
                    // Aire arriba y abajo: lo de ahora puede quedar en el centro
                    // aunque sea lo primero o lo último.
                    Color.clear.containerRelativeFrame(.vertical) { height, _ in height * 0.5 }
                    // **Todo en un solo `ForEach`**, y la pregunta abierta
                    // lleva sus opciones debajo dentro de su misma fila. Antes
                    // la última línea se sacaba del `ForEach` al abrirse la
                    // pregunta: era otra vista, y la máquina de escribir
                    // volvía a empezar — la pregunta se escribía dos veces.
                    // ForEach(items.dropLast(question == nil ? 0 : 1)) { item in … }
                    // if let question, let last = items.last { VStack { row(last); controls(for: question) }.id("current") }
                    ForEach(items) { item in
                        VStack(alignment: .center, spacing: WK.Spacing.l) {
                            row(item)
                            if let question, item.id == items.last?.id {
                                controls(for: question)
                                    .transition(.opacity.combined(with: .offset(y: 16)))
                            }
                        }
                        .opacity(opacity(of: item))
                        // Y cuanto más arriba, más desenfocado.
                        .blur(radius: blur(of: item))
                        .id(item.id)
                        .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                    Color.clear.containerRelativeFrame(.vertical) { height, _ in height * 0.5 }
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.bottom, WK.Spacing.m)
            }
            // El hueco del botón global, que va por encima.
            .safeAreaPadding(.bottom, 96)
            .scrollIndicators(.hidden)
            // **Lo lleva la conversación, no el dedo**: nunca se desplaza a
            // mano, y lo de ahora siempre queda centrado en la pantalla.
            .scrollDisabled(true)
            // .defaultScrollAnchor(.bottom)
            // Lo de arriba se apaga, como en una conversación que sigue.
            .mask {
                LinearGradient(
                    // Corto: una pregunta con muchas opciones —"marca todo lo
                    // que te suene"— es tan alta que, centrada, su pregunta
                    // caía en el degradado y se leía apagada antes de
                    // contestarla. Lo de antes ya se apaga solo, por su
                    // opacidad.
                    // stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.28)],
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            // Abajo del todo cuando llega algo —con un respiro, para que las
            // opciones ya estén puestas y se vean enteras encima del botón—.
            .onChange(of: items.count) { _, _ in scrollDown(reader) }
            .onChange(of: question) { _, _ in scrollDown(reader) }
        }
        .onboardingButton(button)
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await start()
        }
    }

    /// **Lo de ahora, al centro**: las opciones si hay pregunta abierta; si
    /// no, la última línea.
    private func scrollDown(_ reader: ScrollViewProxy) {
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.smooth(duration: 0.6)) {
                // La última fila ya lleva dentro sus opciones.
                if let last = items.last {
                    reader.scrollTo(last.id, anchor: .center)
                }
            }
        }
    }

    // MARK: Guion

    private func start() async {
        await say(String(localized: "chat.hello", defaultValue: "Hi, I'm Snazzy. I'll help you get the most out of your closet."))
        await say(String(localized: "chat.intro", defaultValue: "I'll ask you a few quick questions. Don't overthink them."))
        await say(String(localized: "chat.goal", defaultValue: "What do you want to achieve?"))
        ask(.goal)
    }

    private func answerGoal(_ option: OnboardingOption) async {
        model.goal = option.id
        answer(option.label)
        await say(String(localized: "chat.goal.reply", defaultValue: "Perfect, we'll start there."))
        await say(String(localized: "chat.pains", defaultValue: "What gets in the way? Pick everything that sounds familiar."))
        ask(.pains)
    }

    private func answerPains() async {
        model.pains = pains
        let labels = OnboardingContent.pains.filter { pains.contains($0.id) }.map(\.label)
        // Lo que ha marcado, con sus palabras: "3 cosas" no dice nada.
        // answer(labels.count <= 2 ? labels.joined(separator: " · ") : String(localized: "chat.pains.count", defaultValue: "\(String(describing: labels.count)) things"))
        answer(labels.joined(separator: " · "))
        await say(String(localized: "chat.pains.reply", defaultValue: "You're not the only one. It happens to almost everyone."))
        await say(String(localized: "chat.spend", defaultValue: "Roughly, how much do you spend on clothes a month?"))
        ask(.spend)
    }

    private func answerSpend() async {
        model.monthlySpend = spend
        answer(model.money(spend) + String(localized: "chat.perMonth", defaultValue: " a month"))
        // La cifra, aparte y destacada: ver `Item.highlight`.
        // await say(String(localized: "chat.spend.reply", defaultValue: "That's \(String(describing: model.money(spend * 12))) a year on clothes."))
        await say(String(localized: "chat.spend.reply.lead", defaultValue: "That's"))
        append(.highlight(id: takeID(), text: String(localized: "chat.spend.reply.value", defaultValue: "\(String(describing: model.money(spend * 12))) a year")))
        try? await Task.sleep(for: .seconds(0.9))
        await say(String(localized: "chat.spend.reply.tail", defaultValue: "on clothes."))
        await say(String(localized: "chat.wardrobe", defaultValue: "And how many pieces would you say you have?"))
        await say(String(localized: "chat.estimate", defaultValue: "Just an estimate."))
        ask(.wardrobe)
    }

    private func answerWardrobe() async {
        model.wardrobeSize = wardrobe
        answer(String(localized: "chat.pieces", defaultValue: "\(String(describing: Int(wardrobe))) pieces"))
        await say(String(localized: "chat.analyzing", defaultValue: "Analysing your answers…"))
        append(.progress(id: takeID()))
        withAnimation(.easeInOut(duration: 2.2)) { analysis = 1 }
        try? await Task.sleep(for: .seconds(2.4))
        await say(String(localized: "chat.done", defaultValue: "You have more closet than you can see. Let me show you."))
        // Sigue sola, sin botón: ya lo ha dicho.
        // ask(.done)
        try? await Task.sleep(for: .seconds(0.9))
        model.advance()
    }

    private func say(_ text: String) async {
        append(.line(id: takeID(), text: text))
        // Lo que tarda en escribirse, y un respiro.
        try? await Task.sleep(for: .seconds(Double(text.count) * TypewriterText.perCharacter + 0.45))
    }

    private func answer(_ text: String) {
        withAnimation(.smooth(duration: 0.35)) { question = nil }
        append(.answer(id: takeID(), text: text))
    }

    private func ask(_ next: Question) {
        withAnimation(.smooth(duration: 0.45)) { question = next }
    }

    private func append(_ item: Item) {
        withAnimation(.smooth(duration: 0.4)) { items.append(item) }
    }

    private func takeID() -> Int {
        nextID += 1
        return nextID
    }

    // MARK: Piezas

    @ViewBuilder
    private func row(_ item: Item) -> some View {
        switch item {
        // **Todo centrado**: las líneas, las respuestas y las cifras. Antes,
        // a la izquierda, como un chat.
        case let .line(_, text):
            TypewriterText(text: text)
                .font(Self.lineFont)
                .foregroundStyle(WK.Palette.primaryText)
                .multilineTextAlignment(.center)
                // .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        case let .answer(_, text):
            Text(text)
                .font(Self.lineFont)
                .foregroundStyle(OnboardingTone.denim.color)
                .multilineTextAlignment(.center)
                // .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        case let .highlight(_, text):
            GlowingText(text: text, tone: .oliva)
                .multilineTextAlignment(.center)
                // .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        case .progress:
            Capsule()
                .fill(WK.Palette.ink(0.08))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(OnboardingTone.denim.color)
                            .frame(width: proxy.size.width * analysis)
                    }
                }
        }
    }

    private func blur(of item: Item) -> CGFloat {
        guard let index = items.firstIndex(of: item) else { return 0 }
        let fromEnd = items.count - 1 - index
        return fromEnd <= 1 ? 0 : min(4, CGFloat(fromEnd - 1) * 1.2)
    }

    /// Lo último, entero; lo de antes, apagado.
    private func opacity(of item: Item) -> Double {
        guard let index = items.firstIndex(of: item) else { return 1 }
        let fromEnd = items.count - 1 - index
        return fromEnd <= 1 ? 1 : max(0.28, 1 - Double(fromEnd - 1) * 0.3)
    }

    @ViewBuilder
    private func controls(for question: Question) -> some View {
        switch question {
        case .goal:
            VStack(spacing: WK.Spacing.s) {
                ForEach(OnboardingContent.goals) { option in
                    ChatOptionRow(option: option, isSelected: false) {
                        Task { await answerGoal(option) }
                    }
                }
            }
        case .pains:
            VStack(spacing: WK.Spacing.s) {
                ForEach(OnboardingContent.pains) { option in
                    ChatOptionRow(option: option, isSelected: pains.contains(option.id), isCheckbox: true) {
                        withAnimation(WKAnimation.selection) {
                            if pains.contains(option.id) { pains.remove(option.id) } else { pains.insert(option.id) }
                        }
                    }
                }
            }
        case .spend:
            // De euro en euro: a saltos de cinco se notaba a tirones.
            ValueStepperSlider(value: $spend, range: 10...400, step: 1) { model.money($0) }
                .padding(.top, WK.Spacing.m)
        case .wardrobe:
            ValueStepperSlider(value: $wardrobe, range: 20...400, step: 10) {
                String(localized: "chat.pieces", defaultValue: "\(String(describing: Int($0))) pieces")
            }
            .padding(.top, WK.Spacing.m)
        case .done:
            EmptyView()
        }
    }

    /// El botón global según lo que toque: nada mientras se escribe o en una
    /// pregunta de un toque; "Listo" o "Esto" cuando hay que confirmar.
    private var button: OnboardingButtonConfig {
        switch question {
        case .pains:
            OnboardingButtonConfig(
                title: String(localized: "chat.button.done", defaultValue: "Done"),
                isEnabled: !pains.isEmpty,
                action: { Task { await answerPains() } }
            )
        case .spend:
            OnboardingButtonConfig(
                title: String(localized: "chat.button.thatsIt", defaultValue: "That's about it"),
                action: { Task { await answerSpend() } }
            )
        case .wardrobe:
            OnboardingButtonConfig(
                title: String(localized: "chat.button.thatsIt", defaultValue: "That's about it"),
                action: { Task { await answerWardrobe() } }
            )
        case .done:
            OnboardingButtonConfig(
                title: String(localized: "common.continue", defaultValue: "Continue"),
                action: { model.advance() }
            )
        // **El botón no se va nunca**: mientras se escribe o en una pregunta
        // de un toque está, pero apagado. Si aparecía y desaparecía, la
        // pantalla saltaba.
        // case .goal, nil:
        //     nil
        case .goal, nil:
            OnboardingButtonConfig(
                title: String(localized: "common.continue", defaultValue: "Continue"),
                isEnabled: false,
                action: {}
            )
        }
    }
}

/// Texto que se escribe solo, letra a letra.
struct TypewriterText: View {
    let text: String
    /// Cuánto tarda cada letra.
    static let perCharacter = 0.022
    @State private var shown = 0

    var body: some View {
        // El texto entero ocupa su sitio desde el principio —invisible lo que
        // falta—, así las líneas no saltan al crecer.
        (Text(visible) + Text(hidden).foregroundColor(.clear))
            .task(id: text) {
                shown = 0
                for index in 0...text.count {
                    shown = index
                    try? await Task.sleep(for: .seconds(Self.perCharacter))
                }
            }
    }

    private var visible: AttributedString { AttributedString(String(text.prefix(shown))) }
    private var hidden: AttributedString { AttributedString(String(text.dropFirst(shown))) }
}

/// Una opción de la conversación: una fila de cristal.
private struct ChatOptionRow: View {
    let option: OnboardingOption
    let isSelected: Bool
    var isCheckbox = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WK.Spacing.m) {
                // Sin color: los tonos por opción, y el contorno al marcar,
                // sobraban. Lo único que cambia al marcar es el check.
                Image(systemName: option.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    // .foregroundStyle(option.tone.color)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .frame(width: 22)
                // El texto, centrado en la fila: el icono a un lado y el
                // check —o su hueco— al otro, para que quede en medio.
                Spacer(minLength: 0)
                Text(option.label)
                    .font(WK.Font.body)
                    .foregroundStyle(WK.Palette.primaryText)
                    // .multilineTextAlignment(.leading)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                if !isCheckbox {
                    Color.clear.frame(width: 22, height: 1)
                }
                if isCheckbox {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        // .foregroundStyle(isSelected ? option.tone.color : WK.Palette.tertiaryText)
                        // .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 20))
                        .frame(width: 22)
                        .foregroundStyle(isSelected ? WK.Palette.primaryText : WK.Palette.tertiaryText)
                        // El círculo se convierte en el check.
                        .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating))
                }
            }
            .padding(.horizontal, WK.Spacing.m)
            .padding(.vertical, WK.Spacing.m - 2)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .adaptiveGlassInteractive(in: .capsule)
        // .overlay {
        //     Capsule().stroke(isSelected ? option.tone.color : .clear, lineWidth: 1.5)
        // }
    }
}

/// **Una cifra que importa**: grande, en color, con un brillo que la recorre y
/// un halo detrás. La usan la conversación y el paso del dinero.
struct GlowingText: View {
    let text: String
    let tone: OnboardingTone
    var size: CGFloat = 30

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(tone.color)
            .wkShimmer(isActive: true)
            .shadow(color: tone.color.opacity(0.45), radius: 18)
            .shadow(color: tone.color.opacity(0.25), radius: 40)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}
