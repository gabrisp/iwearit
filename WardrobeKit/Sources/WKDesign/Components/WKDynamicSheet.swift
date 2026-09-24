import Combine
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
/// Hoja que toma su altura del contenido.
///
/// ## Cómo se mide, que es lo único difícil
///
/// El contenido se fija en vertical —`fixedSize`— para que diga lo que mide
/// **él** en vez de estirarse a lo que la hoja le dé. Ese número se mide, se
/// recorta a lo que cabe en pantalla y se convierte en el detent.
///
/// Y el detent se anima: cambiar `.height(a)` por `.height(b)` le da al
/// sistema dos valores sin nada en medio, así que la hoja daba un salto al
/// cambiar de paso. Con un modificador `Animatable`, la altura se interpola
/// fotograma a fotograma y la hoja **crece**.
///
/// El teclado, aparte: un detent fijo no se aparta solo, así que un campo
/// abajo se quedaba detrás de las teclas. La altura crece por lo que el
/// teclado tapa —y solo en hojas más altas que él, porque a las cortas ya las
/// levanta el sistema—.
///
/// Es el comportamiento del `LocktyDynamicSheet`, que es de donde viene.
private struct WKDynamicSheetHeight: ViewModifier {
    @State private var sheetHeight: CGFloat = 0
    @State private var keyboardInset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            // El mismo aire arriba que abajo. Sin esto el contenido arranca
            // pegado al borde de la hoja y el pie parece descolgado.
            .padding(.top, WK.Spacing.xxl)
            .padding(.bottom, WK.Spacing.l)
            .frame(maxWidth: .infinity)
            // Que el contenido mida lo suyo y no lo que la hoja le proponga.
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { apply(measured: $0) }
            .modifier(WKSheetDetent(height: presentedHeight))
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.disabled)
            .onReceive(Self.keyboardHeight) { height in
                withAnimation(.snappy(duration: 0.28)) { keyboardInset = height }
            }
    }

    private var presentedHeight: CGFloat {
        guard keyboardInset > 0, sheetHeight > keyboardInset else { return sheetHeight }
        return min(sheetHeight + min(keyboardInset, sheetHeight), wkScreenHeight)
    }

    private func apply(measured size: CGSize) {
        guard size != .zero else { return }
        let target = min(size.height, wkSheetMaximumContentHeight)
        guard sheetHeight != 0 else {
            sheetHeight = target
            return
        }
        // Un punto de holgura: sin él, redondeos de medio píxel disparan una
        // animación de altura en cada pasada.
        guard abs(target - sheetHeight) > 1 else { return }
        withAnimation(.smooth(duration: 0.42)) { sheetHeight = target }
    }

    /// Lo que mide el teclado según va y viene. `willChangeFrame` y no
    /// `willShow`: un teclado que cambia de alto —barra de sugerencias, otro
    /// idioma— también mueve la hoja.
    private static var keyboardHeight: AnyPublisher<CGFloat, Never> {
        let willChange = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .map { notification -> CGFloat in
                let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                return frame?.height ?? 0
            }
        let willHide = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }
        return willChange.merge(with: willHide).eraseToAnyPublisher()
    }
}

/// El alto de la pantalla, para topar la hoja.
@MainActor
var wkScreenHeight: CGFloat {
    (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.height ?? 0
}

/// El detent, **interpolado**.
///
/// `Animatable` para que la altura pase por todos los valores intermedios: sin
/// esto, cambiar de un detent a otro es un corte entre dos números sin nada en
/// medio.
private nonisolated struct WKSheetDetent: ViewModifier, Animatable {
    var height: CGFloat

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func body(content: Content) -> some View {
        content.presentationDetents(height == 0 ? [.medium] : [.height(height)])
    }
}

// **La versión de antes, comentada y no borrada.**
//
// Metía el contenido en un `ScrollView` siempre y medía dentro de él: el
// scroll se estira a lo que la hoja le dé, así que medir ahí dentro es medir
// el hueco que ya tenía, no lo que hay que enseñar. De ahí que las hojas
// abrieran a media pantalla con el contenido arriba y un palmo de vacío
// debajo, y que cambiar de paso diera un salto.
//
// private struct WKDynamicSheetHeight: ViewModifier {
//     @State private var contentHeight: CGFloat = 0
//
//     func body(content: Content) -> some View {
//         let limit = wkSheetMaximumContentHeight
//         let measured = min(max(contentHeight, 120), limit)
//
//         ScrollView(.vertical) {
//             content
//                 // El mismo aire arriba que abajo. Sin esto el contenido arranca
//                 // pegado al borde de la hoja y el pie parece descolgado.
//                 .padding(.top, WK.Spacing.xxl)
//                 .padding(.bottom, WK.Spacing.l)
//                 .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
//                     guard abs(height - contentHeight) > 0.5 else { return }
//                     contentHeight = height
//                 }
//         }
//         .scrollDisabled(contentHeight <= limit)
//         .scrollBounceBehavior(.basedOnSize)
//         .scrollIndicators(.hidden)
//         .presentationDetents([.height(measured)])
//         .presentationDragIndicator(.visible)
//         .presentationBackgroundInteraction(.disabled)
//         .animation(.snappy(duration: 0.3), value: measured)
//     }
// }

public extension View {
    /// Presenta esta hoja con la altura de su contenido.
    func wkDynamicSheet() -> some View {
        modifier(WKDynamicSheetHeight())
    }
}
