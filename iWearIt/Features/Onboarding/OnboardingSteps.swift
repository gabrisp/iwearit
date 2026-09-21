import SwiftUI
import WKDesign

// Los pasos de pregunta. Cada uno es cuatro líneas porque toda la forma está
// en `OnboardingStepScaffold` y todo el texto en `OnboardingContent`.

struct WelcomeStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            Spacer()
            Text("Ya tienes el armario lleno.\nFalta poder verlo.")
                .font(WK.Font.largeTitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(WK.Palette.primaryText)
            Text("iWearIt encuentra tu ropa en tus propias fotos y te enseña todo lo que puedes ponerte sin comprar nada.")
                .font(WK.Font.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(WK.Palette.secondaryText)
            Spacer()
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .adaptiveSafeAreaBar(edge: .bottom) {
            AdaptiveGlassContainer(spacing: WK.Spacing.s) {
                WKPrimaryButton("Empezar", surface: .glass) { model.advance() }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.s)
        }
    }
}

struct GoalStep: View {
    let model: OnboardingModel
    @State private var selection: String?

    var body: some View {
        OnboardingStepScaffold(
            title: "¿Qué quieres conseguir?",
            subtitle: "Para empezar por donde más te sirva.",
            isEnabled: selection != nil,
            onPrimary: {
                model.goal = selection
                model.advance()
            }
        ) {
            SingleSelectList(options: OnboardingContent.goals, selection: $selection)
        }
        .onAppear { selection = model.goal }
    }
}

struct PainStep: View {
    let model: OnboardingModel
    @State private var selection: Set<String> = []

    var body: some View {
        OnboardingStepScaffold(
            title: "¿Qué te lo impide?",
            subtitle: "Marca todo lo que te suene.",
            isEnabled: !selection.isEmpty,
            onPrimary: {
                model.pains = selection
                model.advance()
            }
        ) {
            MultiSelectList(options: OnboardingContent.pains, selection: $selection)
        }
        .onAppear { selection = model.pains }
    }
}

struct StatementsStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: WK.Spacing.l) {
            VStack(spacing: WK.Spacing.s) {
                Text("¿Te suena alguna?")
                    .font(.system(.title, weight: .bold))
                Text("Desliza a la derecha si te pasa.")
                    .font(.subheadline)
                    .foregroundStyle(WK.Palette.secondaryText)
            }
            .padding(.top, WK.Spacing.m)

            SwipeStatementDeck(statements: OnboardingContent.statements) { agreed in
                model.agreedStatements = agreed
                model.advance()
            }
            Spacer()
        }
        .padding(.horizontal, WK.Spacing.screenInset)
    }
}

struct SpendStep: View {
    let model: OnboardingModel
    @State private var value: Double = 60

    var body: some View {
        OnboardingStepScaffold(
            title: "¿Cuánto gastas en ropa al mes?",
            subtitle: "Aproximado. Es para calcular lo que te puedes ahorrar.",
            onPrimary: {
                model.monthlySpend = value
                model.advance()
            }
        ) {
            ValueStepperSlider(value: $value, range: 10...400, step: 5) { amount in
                "\(Int(amount)) €"
            }
            .padding(.top, WK.Spacing.xl)
        }
        .onAppear { value = model.monthlySpend }
    }
}

struct WardrobeSizeStep: View {
    let model: OnboardingModel
    @State private var value: Double = 80

    var body: some View {
        OnboardingStepScaffold(
            title: "¿Cuántas prendas dirías que tienes?",
            subtitle: "A ojo. Nadie las cuenta.",
            onPrimary: {
                model.wardrobeSize = value
                model.advance()
            }
        ) {
            ValueStepperSlider(value: $value, range: 20...400, step: 10) { count in
                "\(Int(count))"
            }
            .padding(.top, WK.Spacing.xl)
        }
        .onAppear { value = model.wardrobeSize }
    }
}

struct SocialProofStep: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingStepScaffold(
            title: "No eres la única persona\na la que le pasa",
            onPrimary: { model.advance() }
        ) {
            VStack(spacing: WK.Spacing.m) {
                ForEach(OnboardingContent.testimonials) { TestimonialCard($0) }
            }
        }
    }
}

struct CalculatingStep: View {
    let model: OnboardingModel

    var body: some View {
        ProcessingView(
            title: "Echando cuentas…",
            steps: [
                "Lo que gastas al año",
                "Cuánto de tu armario se queda sin usar",
                "Lo que puedes dejar de comprar",
            ]
        )
        .padding(.horizontal, WK.Spacing.screenInset)
        .task {
            // Lo justo para que las tres líneas se lean. Más que eso se percibe
            // como que la app va lenta, no como que está pensando.
            try? await Task.sleep(for: .milliseconds(2400))
            model.advance()
        }
    }
}

struct SavingsStep: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingStepScaffold(
            title: "Esto es lo que tienes parado",
            primaryTitle: "Quiero aprovecharlo",
            onPrimary: { model.advance() }
        ) {
            VStack(spacing: WK.Spacing.xl) {
                StatReveal(
                    value: model.money(model.idleValue),
                    caption: "en ropa que casi no te pones",
                    detail: "Estimado a partir de las \(Int(model.wardrobeSize)) prendas que nos has dicho."
                )
                .padding(.top, WK.Spacing.l)

                Divider()

                StatReveal(
                    value: model.money(model.yearlySaving),
                    caption: "al año que podrías no gastar",
                    detail: "Si combinas lo que ya tienes en vez de comprar parecido."
                )

                Text("Son estimaciones a partir de lo que nos has contado, no una promesa.")
                    .font(.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct ComparisonStep: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingStepScaffold(
            title: "Con iWearIt y sin él",
            onPrimary: { model.advance() }
        ) {
            ComparisonTable(
                rows: OnboardingContent.comparison,
                withTitle: "iWearIt",
                withoutTitle: "Sin él"
            )
            .padding(.top, WK.Spacing.m)
        }
    }
}
