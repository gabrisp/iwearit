import SwiftUI

/// Confirmaciones breves, en una píldora que baja desde arriba.
///
/// Es la alternativa honesta a no decir nada. Cuando guardas una prenda y la
/// hoja se cierra sola, sin un aviso no sabes si se ha guardado o si la app se
/// ha cerrado sin hacer nada — y la única forma de comprobarlo es ir al armario
/// a mirar. Una alerta para esto es peor: pide un toque para cerrar algo que ya
/// has entendido.
@MainActor
@Observable
public final class WKToastCenter {
    public private(set) var current: WKToast?

    /// Oculta el que esté puesto si llega otro. Sin esto, dos guardados
    /// seguidos dejan el primer temporizador vivo y el segundo aviso se va
    /// antes de tiempo.
    private var dismissal: Task<Void, Never>?

    public init() {}

    public func show(_ toast: WKToast) {
        dismissal?.cancel()
        current = toast
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }
}

public struct WKToast: Equatable, Identifiable, Sendable {
    public let id = UUID()
    public let message: String
    public let symbol: String
    public let tint: Color

    public init(_ message: String, symbol: String = "checkmark.circle.fill", tint: Color = .green) {
        self.message = message
        self.symbol = symbol
        self.tint = tint
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// La capa donde se pinta. Se pone **una vez, en la raíz**.
///
/// Encima de todo y sin capturar toques: un aviso que no se puede atravesar
/// bloquea justo la parte de arriba de la pantalla durante dos segundos.
private struct WKToastLayer: ViewModifier {
    let center: WKToastCenter

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = center.current {
                WKToastPill(toast: toast)
                    .padding(.top, WK.Spacing.s)
                    .transition(
                        .move(edge: .top)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.92, anchor: .top))
                    )
            }
        }
        .animation(WKAnimation.arrival, value: center.current)
        .allowsHitTesting(true)
    }
}

/// La píldora. Vista propia para que la capa no lleve su cuerpo dentro del
/// `@ViewBuilder` del `overlay`.
private struct WKToastPill: View {
    let toast: WKToast

    var body: some View {
        HStack(spacing: WK.Spacing.s) {
            Image(systemName: toast.symbol)
                .font(WK.Font.headline)
                .foregroundStyle(toast.tint)
            Text(toast.message)
                .font(WK.Font.headline)
                .foregroundStyle(WK.Palette.primaryText)
        }
        .padding(.horizontal, WK.Spacing.m)
        .padding(.vertical, WK.Spacing.s + 2)
        .background(WK.Palette.shelf, in: .capsule)
        .overlay(Capsule().stroke(WK.Palette.ink(0.08), lineWidth: 1))
        .shadow(color: WK.Palette.ink(0.14), radius: 18, y: 8)
        .allowsHitTesting(false)
    }
}

public extension View {
    /// Instala la capa de avisos. Va en la raíz de la app, no por pantalla:
    /// una hoja que se cierra al guardar no puede enseñar su propio aviso
    /// porque desaparece antes de que se lea.
    func wkToastLayer(_ center: WKToastCenter) -> some View {
        modifier(WKToastLayer(center: center))
    }
}

#Preview {
    @Previewable @State var center = WKToastCenter()

    VStack {
        WKPrimaryButton(String(localized: "wkdesign.wktoast.save", defaultValue: "Save", bundle: .module)) { center.show(WKToast(String(localized: "common.itemSaved", defaultValue: "Item saved", bundle: .module))) }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(WK.Palette.canvas)
    .wkToastLayer(center)
}
