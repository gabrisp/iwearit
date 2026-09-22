import SwiftUI

/// La acción principal de una pantalla.
///
/// Relleno y color de etiqueta **explícitos**, nunca delegados al tinte del
/// sistema: con el acento en blanco (modo oscuro), `borderedProminent` pinta la
/// etiqueta también en blanco y el botón queda ilegible. Decidir los dos juntos
/// es lo único que garantiza contraste en ambos esquemas.
public struct WKPrimaryButton: View {

    /// Cómo se dibuja la superficie del botón.
    public enum Surface: Sendable {
        /// Relleno sólido con esquinas suaves. El de dentro de la app.
        case filled
        /// Cristal teñido en cápsula. El del onboarding, donde el botón flota
        /// sobre contenido que cambia y conviene que se note que está encima.
        case glass
    }

    private let title: String
    private let systemImage: String?
    private let surface: Surface
    private let role: ButtonRole?
    private let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        surface: Surface = .filled,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.surface = surface
        self.role = role
        self.action = action
    }

    public var body: some View {
        switch surface {
        case .filled:
            Button(action: action) { label }
                .buttonStyle(WKPressStyle())
        case .glass:
            // **Un botón normal con su cristal.** El cristal va en el propio
            // botón, por fuera, y sin nuestro estilo de pulsación: ese estilo
            // agrupa y aclara el contenido para hundirlo, y eso convierte el
            // cristal en una imagen plana —pierde el brillo al tocar, el
            // reflejo y la forma de reaccionar—. El cristal interactivo ya se
            // hunde y se ilumina solo al pulsarlo.
            Button(action: action) { label }
                .buttonStyle(.plain)
                .adaptiveGlassProminent(tint: fill, in: .capsule)
        }
    }

    private var label: some View {
        Label {
            Text(title).font(.headline)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity)
        .padding(.vertical, WK.Spacing.m)
        // La etiqueta se decide **junto** al relleno, siempre. Dejársela al
        // tinte del sistema produce texto blanco sobre blanco en oscuro.
        .foregroundStyle(role == .destructive ? Color.white : WK.Palette.onAccent)
        .modifier(SurfaceModifier(surface: surface, tint: fill))
        // Imprescindible: `background` **dibuja** la superficie pero no
        // extiende el área de toque. Sin esto solo responden los glifos del
        // texto, no la cápsula — y un botón que casi nunca responde parece
        // roto, no pequeño.
        .contentShape(.capsule)
    }

    private var fill: Color {
        role == .destructive ? .red : WK.Palette.accent
    }
}

/// Aplica la superficie elegida. Un modificador aparte porque `@ViewBuilder`
/// con dos ramas cambiaría la identidad de la vista en cada render.
private struct SurfaceModifier: ViewModifier {
    let surface: WKPrimaryButton.Surface
    let tint: Color

    func body(content: Content) -> some View {
        switch surface {
        case .filled:
            content.background(tint, in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))
        case .glass:
            // El cristal lo pone el botón por fuera: ver `body`.
            content
        }
    }
}

/// Acción secundaria: mismo tamaño, sin relleno.
public struct WKSecondaryButton: View {
    private let title: String
    private let systemImage: String?
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label {
                Text(title).font(.headline)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WK.Spacing.m)
            .foregroundStyle(WK.Palette.primaryText)
            .background(WK.Palette.ink(0.06), in: .capsule)
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}

/// Hundido al pulsar. Sin mantener pulsado: un botón se toca y ya.
public struct WKPressStyle: ButtonStyle {
    public init() {}

    /// Cuánto encoge al pulsar.
    private static let pressedScale = 0.94
    /// El destello. Sube el brillo de lo que hay dentro, así que respeta el
    /// alfa: una prenda recortada destella con su forma y no con su caja.
    private static let flash = 0.07

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // **Una sola pieza.** Sin esto, cada capa del contenido se escala y
            // se ilumina por su cuenta: en la maleta, el asa y las ruedas salen
            // del cuerpo y se movían por separado, y el conjunto se deshacía al
            // pulsar en vez de hundirse entero.
            .compositingGroup()
            .brightness(configuration.isPressed ? Self.flash : 0)
            .scaleEffect(configuration.isPressed ? Self.pressedScale : 1)
            // Asimétrico, y es lo que hace que se lea como un destello: entra
            // de golpe —el dedo ya está ahí, no hay nada que anticipar— y sale
            // con calma. Con la misma duración en los dos sentidos parece un
            // botón blando, no un golpe.
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: 0.07)
                    : .snappy(duration: 0.3),
                value: configuration.isPressed
            )
    }
}

#Preview {
    VStack(spacing: WK.Spacing.m) {
        WKPrimaryButton("Crear outfits", systemImage: "tshirt") {}
        WKPrimaryButton("Continuar", surface: .glass) {}
        WKSecondaryButton("Añadir prenda", systemImage: "plus") {}
        WKPrimaryButton("Eliminar", role: .destructive) {}
    }
    .padding(WK.Spacing.screenInset)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(WK.Palette.canvas)
}
