import SwiftUI
import WKDesign

/// El flujo de onboarding.
///
/// El chrome —barra de progreso, botón de volver— es del contenedor y **no se
/// mueve**: solo cambia el medio. Eso hace que pasar de paso se lea como la
/// misma pantalla avanzando y no como una pantalla nueva llegando.
struct OnboardingFlow: View {
    let onFinish: () -> Void

    @State private var model = OnboardingModel()

    var body: some View {
        // `NavigationStack` propio: es lo que hace que iOS 26 difumine solo el
        // contenido que pasa por debajo de las barras. Sin él, `safeAreaBar`
        // reserva el hueco pero no tiene nada a lo que engancharse.
        NavigationStack {
            OnboardingStepContent(model: model, onFinish: onFinish)
                .transition(model.transition)
                .id(model.step)
                // El cristal del botón se funde de un paso al siguiente en vez
                // de desaparecer y volver: el botón es el mismo objeto, solo
                // cambia lo que dice.
                .adaptiveGlassTransition()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WK.Palette.canvas.ignoresSafeArea())
                .adaptiveSafeAreaBar(edge: .top) { header }
                .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var header: some View {
        if model.step != .welcome {
            HStack(spacing: WK.Spacing.m) {
                Button {
                    model.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(WK.Font.headline)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .frame(width: 36, height: 36)
                        // .background(WK.Palette.ink(0.07), in: .circle)
                        .contentShape(.circle)
                }
                // Cristal interactivo, como el resto de botones del onboarding.
                .buttonStyle(.plain)
                .adaptiveGlassInteractive(in: .circle)

                OnboardingProgressBar(
                    step: model.step.progressIndex,
                    total: OnboardingStep.allCases.count - 1
                )
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.vertical, WK.Spacing.s)
        }
    }
}

/// Qué paso se muestra. Vista aparte para que el `switch` no viva dentro del
/// `@ViewBuilder` del contenedor.
private struct OnboardingStepContent: View {
    let model: OnboardingModel
    let onFinish: () -> Void

    var body: some View {
        switch model.step {
        case .welcome:         WelcomeStep(model: model)
        case .goal:            GoalStep(model: model)
        case .pain:            PainStep(model: model)
        case .statements:      StatementsStep(model: model)
        case .spend:           SpendStep(model: model)
        case .wardrobeSize:    WardrobeSizeStep(model: model)
        case .socialProof:     SocialProofStep(model: model)
        case .calculating:     CalculatingStep(model: model)
        case .savings:         SavingsStep(model: model)
        case .comparison:      ComparisonStep(model: model)
        case .photoPermission: PhotoPermissionStep(model: model)
        case .scanning:        ScanningStep(model: model)
        case .scanReview:      ScanReviewStep(model: model)
        case .scanSummary:     ScanSummaryStep(model: model)
        case .paywall:         PaywallStep(onFinish: onFinish)
        }
    }
}

/// Marco común de un paso: título, contenido y botón.
///
/// Los catorce pasos comparten esta forma. Escribirla una vez es lo que evita
/// que la séptima pantalla tenga el botón dos puntos más abajo que la sexta.
struct OnboardingStepScaffold<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let primaryTitle: String
    private let isEnabled: Bool
    private let onPrimary: () -> Void
    private let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        primaryTitle: String = "Continuar",
        isEnabled: Bool = true,
        onPrimary: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.primaryTitle = primaryTitle
        self.isEnabled = isEnabled
        self.onPrimary = onPrimary
        self.content = content()
    }

    var body: some View {
        // Sin `ScrollView`: el contenido de un paso cabe en pantalla por
        // diseño. Metido en un scroll, el título quedaba recortado por debajo
        // de la barra superior y daba la sensación de que la pantalla estaba
        // mal medida. Si algún paso no cupiera, la respuesta es acortar ese
        // paso, no dejar que el usuario tenga que buscar el botón.
        VStack(spacing: WK.Spacing.l) {
            VStack(spacing: WK.Spacing.s) {
                Text(title)
                    .font(WK.Font.largeTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(WK.Palette.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(WK.Font.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(WK.Palette.secondaryText)
                }
            }
            .padding(.top, WK.Spacing.l)

            content
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .adaptiveSafeAreaBar(edge: .bottom) {
            // El cristal no puede muestrear otro cristal: el contenedor da
            // región de muestreo común a lo que haya aquí.
            AdaptiveGlassContainer(spacing: WK.Spacing.s) {
                WKPrimaryButton(primaryTitle, surface: .glass, action: onPrimary)
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1 : 0.4)
                    .animation(WKAnimation.selection, value: isEnabled)
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.s)
        }
    }
}
