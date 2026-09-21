import SwiftUI

/// Un paso de un flujo, y a qué profundidad está.
///
/// La profundidad es lo único que un paso declara. Todo lo demás —hacia dónde
/// anima, qué significa "atrás"— sale de comparar dos.
public protocol WKFlowStep: Hashable {
    /// Cuánto se ha entrado. La raíz es 0. Dos pasos alcanzados desde el mismo
    /// sitio comparten profundidad: son hermanos y ninguno está detrás del otro.
    var flowDepth: Int { get }
}

/// Un paso sustituyendo a otro dentro de una hoja.
///
/// Estas hojas no llevan `NavigationStack` —una hoja que empuja se gana una
/// barra que nadie pidió—, así que un flujo cambia una pantalla por otra y
/// anima el cambio. Hacia dónde anima es lo único que hace que se lea como
/// navegación y no como un parpadeo.
///
/// La dirección sale de las profundidades y no de una lista de pares de
/// pantallas escrita a mano: esa lista está mal en cuanto se inserta un paso, y
/// está mal **en silencio**.
///
/// Es una clase y no un `@State` por un motivo concreto: la transición de
/// salida es la que la vista que se va recibió en su último render, así que la
/// dirección hay que fijarla **antes** de la transacción animada. Con un struct
/// en `@State`, ambas cosas ocurrirían a la vez y la pantalla entrante animaría
/// en un sentido y la saliente en el otro.
@MainActor
@Observable
public final class WKFlowStack<Step: WKFlowStep> {
    public private(set) var step: Step
    private(set) var isGoingBack = false

    public init(_ step: Step) {
        self.step = step
    }

    public func move(to next: Step) {
        guard next != step else { return }
        isGoingBack = next.flowDepth < step.flowDepth
        withAnimation(WKAnimation.content) { step = next }
    }

    /// Si estamos en el primer paso, que es lo que decide si el botón de la
    /// izquierda es una salida o una vuelta atrás.
    public var isAtRoot: Bool { step.flowDepth == 0 }

    public static var animation: Animation { .snappy(duration: 0.38, extraBounce: 0.02) }

    /// Entrar desliza desde la derecha; volver, desde la izquierda.
    public var transition: AnyTransition { .wkSlide(fromLeading: isGoingBack) }
}

/// El marco en el que se dibuja cada paso de un flujo.
///
/// El chrome es del padre y **no se mueve**: el botón de cerrar, el título y el
/// botón de abajo se quedan donde están mientras el medio cambia. Eso es lo que
/// hace que un cambio de paso se lea como la misma pantalla pensando, en vez de
/// como una pantalla nueva llegando.
///
/// El paso elige el texto del botón principal; el botón es del padre.
public struct WKFlowScreen<Content: View>: View {
    private let title: String
    private let subtitle: String?
    /// Lo que dispara la animación del medio. Es la identidad del paso, no su
    /// contenido: así un paso puede actualizarse sin animar.
    private let stepID: AnyHashable
    private let transition: AnyTransition
    private let primaryTitle: String
    private let isPrimaryEnabled: Bool
    private let isAtRoot: Bool
    private let onLeading: () -> Void
    private let onPrimary: () -> Void
    private let content: Content

    public init(
        title: String,
        subtitle: String? = nil,
        stepID: AnyHashable,
        transition: AnyTransition,
        primaryTitle: String,
        isPrimaryEnabled: Bool = true,
        isAtRoot: Bool,
        onLeading: @escaping () -> Void,
        onPrimary: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.stepID = stepID
        self.transition = transition
        self.primaryTitle = primaryTitle
        self.isPrimaryEnabled = isPrimaryEnabled
        self.isAtRoot = isAtRoot
        self.onLeading = onLeading
        self.onPrimary = onPrimary
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: WK.Spacing.l) {
            header
            VStack(spacing: WK.Spacing.s) {
                Text(title)
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(WK.Palette.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            // El título cambia **con** el contenido: si solo se animara el
            // medio, el texto que lo describe saltaría de golpe.
            .transition(.opacity.combined(with: .blurReplace))
            .id(title)
            .frame(maxWidth: .infinity)

            content
                .transition(transition)
                .id(stepID)

            WKPrimaryButton(primaryTitle, action: onPrimary)
                .disabled(!isPrimaryEnabled)
                .opacity(isPrimaryEnabled ? 1 : 0.45)
                .animation(.smooth(duration: 0.2), value: isPrimaryEnabled)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
    }

    private var header: some View {
        HStack {
            Button(action: onLeading) {
                Image(systemName: isAtRoot ? "xmark" : "chevron.left")
                    .font(.headline)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(WK.Palette.ink(0.07), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())
            Spacer()
        }
    }
}
