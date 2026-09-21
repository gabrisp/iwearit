import SwiftUI
import UIKit

/// Cuánto deja siempre una hoja por encima de sí misma.
///
/// Nada en iWearIt se presenta a `.large`. Una hoja pegada al borde superior es
/// una pantalla disfrazada de hoja: desaparece lo que hay detrás, no queda nada
/// que tocar para cerrar, y las esquinas redondeadas parecen un error de
/// render. Este hueco es lo que dice que lo de debajo sigue ahí.
public let wkSheetTopGap: CGFloat = 110

/// Altura máxima que puede tener el contenido de una hoja.
@MainActor
public var wkSheetMaximumContentHeight: CGFloat {
    let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
        .screen.bounds.height ?? 0
    return max(screen - wkSheetTopGap, 0)
}

/// Hoja que toma su altura del contenido.
///
/// Una hoja con dos campos no tiene por qué ocupar media pantalla, y una con
/// diez no debería cortarse. Se mide lo que hay dentro y ese es el detent.
///
/// Por encima del límite pasa a hacer scroll: si no, el último control se
/// quedaría por debajo del borde de la pantalla sin forma de llegar a él.
private struct WKDynamicSheetHeight: ViewModifier {
    @State private var contentHeight: CGFloat = 0

    func body(content: Content) -> some View {
        let limit = wkSheetMaximumContentHeight
        let measured = min(max(contentHeight, 120), limit)

        ScrollView(.vertical) {
            content
                // El mismo aire arriba que abajo. Sin esto el contenido arranca
                // pegado al borde de la hoja y el pie parece descolgado.
                .padding(.top, WK.Spacing.xxl)
                .padding(.bottom, WK.Spacing.l)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    guard abs(height - contentHeight) > 0.5 else { return }
                    contentHeight = height
                }
        }
        .scrollDisabled(contentHeight <= limit)
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .presentationDetents([.height(measured)])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.disabled)
        .animation(.snappy(duration: 0.3), value: measured)
    }
}

public extension View {
    /// Presenta esta hoja con la altura de su contenido.
    func wkDynamicSheet() -> some View {
        modifier(WKDynamicSheetHeight())
    }
}
