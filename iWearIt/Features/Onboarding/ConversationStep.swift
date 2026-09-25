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

        var id: Int {
            switch self {
            case let .line(id, _), let .answer(id, _), let .progress(id): id
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
                VStack(alignment: .leading, spacing: WK.Spacing.l) {
                    Spacer(minLength: 220)
                    ForEach(items) { item in
                        row(item)
                            .opacity(opacity(of: item))
                            .id(item.id)
                            .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                    if let question {
                        controls(for: question)
                            .id("controls")
                            .transition(.opacity.combined(with: .offset(y: 16)))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.bottom, WK.Spacing.m)
            }
            // El hueco del botón global, que va por encima.
            .safeAreaPadding(.bottom, 96)
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.bottom)
            // Lo de arriba se apaga, como en una conversación que sigue.
            .mask {
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.28)],
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

    private func scrollDown(_ reader: ScrollViewProxy) {
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.smooth(duration: 0.55)) { reader.scrollTo("bottom", anchor: .bottom) }
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
        answer(labels.count <= 2 ? labels.joined(separator: " · ") : String(localized: "chat.pains.count", defaultValue: "\(String(describing: labels.count)) things"))
        await say(String(localized: "chat.pains.reply", defaultValue: "You're not the only one. It happens to almost everyone."))
        await say(String(localized: "chat.spend", defaultValue: "Roughly, how much do you spend on clothes a month?"))
        ask(.spend)
    }

    private func answerSpend() async {
        model.monthlySpend = spend
        answer(model.money(spend) + String(localized: "chat.perMonth", defaultValue: " a month"))
        await say(String(localized: "chat.spend.reply", defaultValue: "That's \(String(describing: model.money(spend * 12))) a year on clothes."))
        await say(String(localized: "chat.wardrobe", defaultValue: "And how many pieces would you say you have? A guess is fine."))
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
        ask(.done)
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
        case let .line(_, text):
            TypewriterText(text: text)
                .font(Self.lineFont)
                .foregroundStyle(WK.Palette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .answer(_, text):
            Text(text)
                .font(Self.lineFont)
                .foregroundStyle(OnboardingTone.denim.color)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            ValueStepperSlider(value: $spend, range: 10...400, step: 5) { model.money($0) }
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
    private var button: OnboardingButtonConfig? {
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
        case .goal, nil:
            nil
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
                Image(systemName: option.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(option.tone.color)
                    .frame(width: 22)
                Text(option.label)
                    .font(WK.Font.body)
                    .foregroundStyle(WK.Palette.primaryText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isCheckbox {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? option.tone.color : WK.Palette.tertiaryText)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(.horizontal, WK.Spacing.m)
            .padding(.vertical, WK.Spacing.m - 2)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .adaptiveGlassInteractive(in: .capsule)
        .overlay {
            Capsule().stroke(isSelected ? option.tone.color : .clear, lineWidth: 1.5)
        }
    }
}
