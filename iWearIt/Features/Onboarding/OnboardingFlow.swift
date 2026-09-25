import SwiftUI
import WKCanvas
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
    /// Lo que pide el paso actual para el botón global.
    @State private var button: OnboardingButtonConfig?
    @Environment(\.colorScheme) private var colorScheme

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
            // **Todo el onboarding pasa en un mismo lienzo**: el papel de
            // puntos está fijo detrás de todos los pasos y avanza un poco con
            // cada uno, como si se bajara por una hoja larga. Las pantallas no
            // se deslizan: se disuelven y las nuevas se posan encima.
            // ZStack {
            //     WK.Palette.canvas
            //     WK.Palette.ink(0.08)
            // }
            // .ignoresSafeArea()
            OnboardingPaper(step: model.step.rawValue)
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
                    // .modifier(card(for: page))
                    .modifier(CanvasPageEffect(
                        isLeaving: page == model.outgoing,
                        progress: model.pageProgress
                    ))
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
        // **Un solo botón para todo el onboarding.** Cada paso dice qué pone,
        // si se ve y si lleva una nota debajo; aquí se pinta, y al pasar de
        // paso solo cambia su texto. Ver `onboardingButton`.
        .adaptiveSafeAreaBar(edge: .bottom) {
            OnboardingButtonBar(config: button)
                // En la bienvenida el fondo son las fotos, siempre claras: en
                // oscuro el botón salía con el texto del mismo color que su
                // cristal. Ahí va en claro.
                .environment(\.colorScheme, model.step == .welcome ? .light : colorScheme)
        }
        .onPreferenceChange(OnboardingButtonKey.self) { button = $0 }
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
                    step: model.step.progressIndex(in: model.variant),
                    total: model.variant.visibleCount - 1
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
        case .conversation:    ConversationStep(model: model)
        case .reveal:          RevealStep(model: model)
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
        primaryTitle: String = String(localized: "common.continue", defaultValue: "Continue"),
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
                    .onboardingEntrance(0)
                if let subtitle {
                    Text(subtitle)
                        .font(WK.Font.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .onboardingEntrance(1)
                }
            }
            .padding(.top, WK.Spacing.l)

            content
                .frame(maxWidth: .infinity)
                .onboardingEntrance(2)

            if !fillsToBottom {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        // **El botón es del onboarding, no del paso**: el paso dice qué pone
        // y el contenedor lo pinta una sola vez. Ver `OnboardingButton`.
        .onboardingButton(primaryTitle, isEnabled: isEnabled, action: onPrimary)
        // El botón de cada paso, de antes.
        // .adaptiveSafeAreaBar(edge: .bottom) {
        //     // El cristal no puede muestrear otro cristal: el contenedor da
        //     // región de muestreo común a lo que haya aquí.
        //     AdaptiveGlassContainer(spacing: WK.Spacing.s) {
        //         WKPrimaryButton(primaryTitle, surface: .glass, action: onPrimary)
        //             // **El botón no llega ni se va**: es el mismo de paso a
        //             // paso. El del paso que sale desaparece al instante y el
        //             // nuevo ya está en su sitio, así que solo se ve cambiar
        //             // lo que dice. Con los dos animándose, se pisaban.
        //             // .onboardingEntrance(3)
        //             .onboardingPersistentButton()
        //             .disabled(!isEnabled)
        //             .opacity(isEnabled ? 1 : 0.4)
        //             .animation(WKAnimation.selection, value: isEnabled)
        //     }
        //     .padding(.horizontal, WK.Spacing.screenInset)
        //     .padding(.bottom, WK.Spacing.s)
        // }
    }
}


// MARK: - El lienzo del onboarding

/// **El papel de puntos de todo el onboarding**, fijo detrás de los pasos. Con
/// cada paso baja un poco —hacia atrás, sube—: se lee como recorrer una misma
/// hoja larga y no como cambiar de pantalla.
private struct OnboardingPaper: View {
    let step: Int

    /// Cuánto baja por paso.
    private static let travel: CGFloat = 46

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                WK.Palette.canvas
                DotGridBackground()
                    // Tenue: es papel, no un estampado.
                    .opacity(0.25)
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height + Self.travel * CGFloat(OnboardingStep.allCases.count)
                    )
                    .offset(y: -Self.travel * CGFloat(step))
                    .animation(.smooth(duration: 0.9), value: step)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
        }
    }
}

/// **El paso que se va se disuelve**: pierde opacidad, se desenfoca un poco y
/// sube, como tinta que se levanta del papel. El que llega no se mueve en
/// bloque: sus piezas se posan solas. Ver `onboardingEntrance`.
private struct CanvasPageEffect: ViewModifier {
    let isLeaving: Bool
    /// De 0 a 1: cuánto ha avanzado el cambio de paso.
    let progress: Double

    func body(content: Content) -> some View {
        // La que sale se va en la primera mitad del cambio.
        let out = isLeaving ? min(1, progress * 1.8) : 0
        content
            .environment(\.onboardingPageIsLeaving, isLeaving)
            .opacity(1 - out)
            .blur(radius: 8 * out)
            .offset(y: -24 * out)
            .scaleEffect(1 - 0.03 * out, anchor: .top)
    }
}

extension View {
    /// **Se posa en el lienzo**: llega desde un poco más arriba, sin opacidad
    /// y algo desenfocado, y se asienta. `order` escalona las piezas de un
    /// paso —título, subtítulo, contenido, botón— para que no lleguen en
    /// bloque.
    func onboardingEntrance(_ order: Int) -> some View {
        modifier(OnboardingEntrance(order: order))
    }
}

private struct OnboardingEntrance: ViewModifier {
    let order: Int
    @State private var isSettled = false

    func body(content: Content) -> some View {
        content
            .opacity(isSettled ? 1 : 0)
            .offset(y: isSettled ? 0 : -22)
            .blur(radius: isSettled ? 0 : 6)
            .onAppear {
                // Tras la primera mitad del cambio, cuando la de antes ya se
                // ha ido.
                withAnimation(.spring(duration: 0.65, bounce: 0.18).delay(0.28 + Double(order) * 0.09)) {
                    isSettled = true
                }
            }
    }
}

extension EnvironmentValues {
    /// Si este paso es el que se va. Ver `onboardingPersistentButton`.
    @Entry var onboardingPageIsLeaving = false
}

extension View {
    /// El botón principal del paso: se esconde **al instante** cuando el paso
    /// se va, para que el del paso nuevo parezca el mismo.
    func onboardingPersistentButton() -> some View {
        modifier(PersistentButton())
    }
}

private struct PersistentButton: ViewModifier {
    @Environment(\.onboardingPageIsLeaving) private var isLeaving

    func body(content: Content) -> some View {
        content
            .opacity(isLeaving ? 0 : 1)
            .transaction { $0.animation = nil }
    }
}


// MARK: - El botón global

/// Lo que un paso pide al botón del onboarding.
struct OnboardingButtonConfig: Equatable {
    var title: String
    var isEnabled = true
    /// Una línea pequeña debajo del botón, si la hay.
    var footnote: String?
    /// La acción. Fuera de la igualdad: es un cierre, y lo que se compara es
    /// lo que se ve. Lee el estado del paso al pulsarse, así que no se queda
    /// vieja.
    var action: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.isEnabled == rhs.isEnabled && lhs.footnote == rhs.footnote
    }
}

extension OnboardingButtonConfig {
    /// "Sin botón", dicho por un paso. Distinto de `nil`, que es "este paso no
    /// dice nada" —el que se va—.
    static let hidden = OnboardingButtonConfig(title: "", action: {})
    var isHidden: Bool { title.isEmpty }
}

struct OnboardingButtonKey: PreferenceKey {
    static let defaultValue: OnboardingButtonConfig? = nil
    /// Si dos pasos lo piden a la vez —mientras uno se va—, gana el último:
    /// el que se queda, que va encima. El que se va no lo pide. Ver
    /// `onboardingButton`.
    static func reduce(value: inout OnboardingButtonConfig?, nextValue: () -> OnboardingButtonConfig?) {
        if let next = nextValue() { value = next }
    }
}

extension View {
    /// **Pide el botón global** tal cual, o ninguno con `nil`.
    func onboardingButton(_ config: OnboardingButtonConfig?) -> some View {
        modifier(OnboardingButtonRequest(config: config))
    }

    /// **Pide el botón global** con este texto. Un paso que no lo pide no
    /// lo tiene: el botón se esconde.
    func onboardingButton(
        _ title: String,
        isEnabled: Bool = true,
        footnote: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        modifier(OnboardingButtonRequest(config: .init(title: title, isEnabled: isEnabled, footnote: footnote, action: action)))
    }
}

private struct OnboardingButtonRequest: ViewModifier {
    let config: OnboardingButtonConfig?
    @Environment(\.onboardingPageIsLeaving) private var isLeaving

    func body(content: Content) -> some View {
        // El paso que se va ya no manda sobre el botón.
        // Un paso que no quiere botón lo dice con un valor vacío: ver
        // `OnboardingButtonKey.hidden`.
        content.preference(key: OnboardingButtonKey.self, value: isLeaving ? nil : (config ?? .hidden))
    }
}

/// El botón y su nota. **Uno para todo el onboarding**: el texto cambia con
/// `numericText` —ver `WKPrimaryButton`— y el cristal se queda.
private struct OnboardingButtonBar: View {
    let config: OnboardingButtonConfig?

    var body: some View {
        VStack(spacing: WK.Spacing.s) {
            if let config, !config.isHidden {
                AdaptiveGlassContainer(spacing: WK.Spacing.s) {
                    WKPrimaryButton(config.title, surface: .glass, action: config.action)
                        .disabled(!config.isEnabled)
                        .opacity(config.isEnabled ? 1 : 0.4)
                }
                .transition(.opacity.combined(with: .offset(y: 16)))
                if let footnote = config.footnote {
                    Text(footnote)
                        .font(WK.Font.caption)
                        .foregroundStyle(WK.Palette.tertiaryText)
                        .multilineTextAlignment(.center)
                        .contentTransition(.numericText())
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.s)
        .animation(.smooth(duration: 0.4), value: config?.title)
        .animation(.smooth(duration: 0.3), value: config?.isEnabled)
        .animation(.smooth(duration: 0.4), value: config == nil || config?.isHidden == true)
        .animation(.smooth(duration: 0.4), value: config?.footnote)
    }
}
