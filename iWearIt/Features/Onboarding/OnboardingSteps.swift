import SwiftUI
import WKDesign

// Los pasos de pregunta. Cada uno es cuatro líneas porque toda la forma está
// en `OnboardingStepScaffold` y todo el texto en `OnboardingContent`.

struct WelcomeStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            Spacer()
            // Ropa antes que palabras: ver `OnboardingHangingRail`.
            OnboardingHangingRail()
                .padding(.bottom, WK.Spacing.xl)
            Text(String(localized: "onboarding.onboardingsteps.yourClosetIsAlreadyFull", defaultValue: "Your closet is already full.\nYou just can't see it yet."))
                .font(WK.Font.largeTitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(WK.Palette.primaryText)
            Text(String(localized: "onboarding.onboardingsteps.snazzyFindsYourClothesIn", defaultValue: "Snazzy finds your clothes in your own photos and shows you everything you can wear without buying anything."))
                .font(WK.Font.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(WK.Palette.secondaryText)
            Spacer()
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .adaptiveSafeAreaBar(edge: .bottom) {
            AdaptiveGlassContainer(spacing: WK.Spacing.s) {
                WKPrimaryButton(String(localized: "onboarding.onboardingsteps.getStarted", defaultValue: "Get started"), surface: .glass) { model.advance() }
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
            title: String(localized: "onboarding.onboardingsteps.whatDoYouWantTo", defaultValue: "What do you want to achieve?"),
            subtitle: String(localized: "onboarding.onboardingsteps.soWeStartWhereIt", defaultValue: "So we start where it helps you most."),
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
            title: String(localized: "onboarding.onboardingsteps.whatSStoppingYou", defaultValue: "What's stopping you?"),
            subtitle: String(localized: "onboarding.onboardingsteps.pickEverythingThatSoundsFamiliar", defaultValue: "Pick everything that sounds familiar."),
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
                Text(String(localized: "onboarding.onboardingsteps.soundFamiliar", defaultValue: "Sound familiar?"))
                    .font(WK.Font.largeTitle)
                    .multilineTextAlignment(.center)
                Text(String(localized: "onboarding.onboardingsteps.rightIfItHappensTo", defaultValue: "Right if it happens to you, left if not."))
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.secondaryText)
            }
            .padding(.top, WK.Spacing.l)

            // La baraja de antes, propia del onboarding:
            // SwipeStatementDeck(statements: OnboardingContent.statements) { agreed in
            //     model.agreedStatements = agreed
            //     model.advance()
            // }
            // Spacer()

            // La de ahora: el gesto y las piezas de la inspiración. Ver
            // `StatementSwipeDeck`.
            StatementSwipeDeck(statements: OnboardingContent.statements) { agreed in
                model.agreedStatements = agreed
                model.advance()
            }
            .padding(.bottom, WK.Spacing.m)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
    }
}

struct SpendStep: View {
    let model: OnboardingModel
    @State private var value: Double = 60

    var body: some View {
        OnboardingStepScaffold(
            title: String(localized: "onboarding.onboardingsteps.howMuchDoYouSpend", defaultValue: "How much do you spend on clothes a month?"),
            subtitle: String(localized: "onboarding.onboardingsteps.roughlyItSToWork", defaultValue: "Roughly. It's to work out what you could save."),
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
            title: String(localized: "onboarding.onboardingsteps.howManyPiecesWouldYou", defaultValue: "How many pieces would you say you have?"),
            subtitle: String(localized: "onboarding.onboardingsteps.justAGuessNobodyCounts", defaultValue: "Just a guess. Nobody counts them."),
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
            title: String(localized: "onboarding.onboardingsteps.youReNotTheOnly", defaultValue: "You're not the only one\nit happens to"),
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
            title: String(localized: "onboarding.onboardingsteps.doingTheMaths", defaultValue: "Doing the maths…"),
            steps: [
                String(localized: "onboarding.onboardingsteps.whatYouSpendAYear", defaultValue: "What you spend a year"),
                String(localized: "onboarding.onboardingsteps.howMuchOfYourCloset", defaultValue: "How much of your closet goes unworn"),
                String(localized: "onboarding.onboardingsteps.whatYouCouldStopBuying", defaultValue: "What you could stop buying"),
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
            title: String(localized: "onboarding.onboardingsteps.thisIsWhatSSitting", defaultValue: "This is what's sitting idle"),
            primaryTitle: String(localized: "onboarding.onboardingsteps.iWantToMakeThe", defaultValue: "I want to make the most of it"),
            onPrimary: { model.advance() }
        ) {
            VStack(spacing: WK.Spacing.xl) {
                StatReveal(
                    value: model.money(model.idleValue),
                    caption: String(localized: "onboarding.onboardingsteps.inClothesYouBarelyWear", defaultValue: "in clothes you barely wear"),
                    detail: String(localized: "onboarding.onboardingsteps.estimatedFromThePiecesYou", defaultValue: "Estimated from the \(String(describing: Int(model.wardrobeSize))) pieces you told us about."),
                    // Granate lo parado, oliva lo que se ahorra.
                    tone: .granate
                )
                .padding(.top, WK.Spacing.l)

                Divider()

                StatReveal(
                    value: model.money(model.yearlySaving),
                    caption: String(localized: "onboarding.onboardingsteps.aYearYouCouldAvoid", defaultValue: "a year you could avoid spending"),
                    detail: String(localized: "onboarding.onboardingsteps.ifYouCombineWhatYou", defaultValue: "If you combine what you have instead of buying similar things."),
                    tone: .oliva
                )

                Text(String(localized: "onboarding.onboardingsteps.theseAreEstimatesBasedOn", defaultValue: "These are estimates based on what you told us, not a promise."))
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
            title: String(localized: "onboarding.onboardingsteps.swipeAndCompare", defaultValue: "Swipe and compare"),
            onPrimary: { model.advance() }
        ) {
            // La tabla de dos columnas con ✓ y ✕, antes:
            // ComparisonTable(
            //     rows: OnboardingContent.comparison,
            //     withTitle: "iWearIt",
            //     withoutTitle: "Sin él"
            // )
            // .padding(.top, WK.Spacing.m)
            ComparisonSlider(pairs: OnboardingContent.comparisonPairs)
                .padding(.top, WK.Spacing.s)
        }
    }
}
