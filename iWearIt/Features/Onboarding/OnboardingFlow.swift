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
    /// Los márgenes seguros, para que las pantallas se vuelvan tarjeta desde
    /// la pantalla entera. Ver `WKPageCardTransition`.
    @State private var safeInsets = EdgeInsets()

    var body: some View {
        // **Sin `NavigationStack`.** Estaba para que `safeAreaBar` difuminara
        // lo de debajo de la barra de arriba, y esa barra ya no es
        // `safeAreaBar`. Además la pila pinta su propio efecto de borde
        // arriba aunque la barra esté oculta, y al encoger la pantalla a
        // tarjeta se veía como una franja blanca.
        // NavigationStack {
        ZStack {
            // Detrás, un escalón más oscuro: solo se ve mientras las
            // pantallas pasan como tarjetas, y es lo que las despega.
            //
            // **Una capa fija debajo y no un `.background`** del contenedor
            // que cambia de identidad: puesta así no llegaba a pintarse y
            // detrás de las tarjetas se veía la ventana en blanco.
            ZStack {
                WK.Palette.canvas
                WK.Palette.ink(0.08)
            }
            .ignoresSafeArea()

            // Las dos pantallas mientras pasa la página —la que sale y la que
            // entra—, por su paso para que cada una conserve su estado. Ver
            // `OnboardingModel.move`.
            ForEach(pages, id: \.self) { page in
                OnboardingStepContent(step: page, model: model, onFinish: onFinish)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // El fondo de cada pantalla lo pinta la tarjeta, con la
                    // forma con la que se recorta y que abarca la pantalla
                    // entera. Ver `PageCardEffect`.
                    .modifier(card(for: page))
                    // La que entra, encima: llega tapando a la que se va.
                    .zIndex(page == model.outgoing ? 0 : 1)
                    // Solo se toca la que se queda.
                    .allowsHitTesting(page == model.step)
            }
        }
        // El cristal del botón se funde de un paso al siguiente en vez
        // de desaparecer y volver: el botón es el mismo objeto, solo
        // cambia lo que dice.
        .adaptiveGlassTransition()
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: {
            safeInsets = $0
        }
        // `safeAreaInset` y no `safeAreaBar`: la barra de iOS 26
        // difumina lo que pasa por debajo, y mientras la pantalla se
        // encoge a tarjeta ese difuminado se veía como una franja
        // blanca en el canto de arriba.
        // De vuelta en la barra: la franja blanca al encoger no la ponía la
        // barra sino los fondos, y eso ya lo resuelve la tarjeta. Ver
        // `PageCardEffect`.
        // .safeAreaInset(edge: .top, spacing: 0) { header }
        .adaptiveSafeAreaBar(edge: .top) { header }
        .animation(WKAnimation.content, value: model.step == .welcome)
    }

    /// La que sale primero, la que entra después.
    private var pages: [OnboardingStep] {
        [model.outgoing, model.step].compactMap { $0 }
    }

    /// El efecto de tarjeta de cada pantalla, según el paso de página.
    private func card(for page: OnboardingStep) -> PageCardEffect {
        let forward: CGFloat = model.isGoingBack ? -1 : 1
        let isLeaving = page == model.outgoing
        let progress: Double
        if isLeaving {
            progress = model.pageProgress
        } else {
            progress = model.outgoing == nil ? 0 : 1 - model.pageProgress
        }
        return PageCardEffect(
            progress: progress,
            isLeaving: isLeaving,
            side: isLeaving ? -forward : forward,
            insets: safeInsets,
            background: WK.Palette.canvas
        )
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
            // Aparecen fundiéndose al salir de la bienvenida, no de golpe.
            .transition(.opacity)
        }
    }
}

/// Qué paso se muestra. Vista aparte para que el `switch` no viva dentro del
/// `@ViewBuilder` del contenedor.
private struct OnboardingStepContent: View {
    /// **El paso como valor, fijado al crear la vista.** Leyendo `model.step`
    /// aquí dentro, la pantalla que se estaba yendo se redibujaba con el paso
    /// nuevo —el modelo es observable— y durante la transición se veía la
    /// pantalla siguiente dentro de la tarjeta de la anterior.
    let step: OnboardingStep
    let model: OnboardingModel
    let onFinish: () -> Void

    var body: some View {
        switch step {
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
        case .scanFound:       ScanFoundStep(model: model)
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
    /// El contenido llega hasta abajo y pasa bajo el botón. Para un scroll:
    /// con el hueco y el espaciador de debajo no tocaba el borde de la zona
    /// segura, el sistema no lo extendía y se cortaba en seco encima del
    /// botón.
    private let fillsToBottom: Bool
    private let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        primaryTitle: String = "Continuar",
        isEnabled: Bool = true,
        fillsToBottom: Bool = false,
        onPrimary: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.primaryTitle = primaryTitle
        self.isEnabled = isEnabled
        self.fillsToBottom = fillsToBottom
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

            if !fillsToBottom {
                Spacer(minLength: 0)
            }
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
