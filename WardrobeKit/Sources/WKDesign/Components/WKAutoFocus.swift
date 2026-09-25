import SwiftUI

public extension View {
    /// **El teclado sale solo** al llegar al campo: en una hoja de un solo
    /// dato, lo primero que vas a hacer es escribir, y un toque más para
    /// empezar es un toque de sobra.
    ///
    /// Con un respiro: pedir el foco en el mismo instante en que la hoja
    /// empieza a subir se pierde, porque el campo aún no está en pantalla.
    ///
    /// Quitarlo **antes de salir** lo hace quien sale —ver `resignFocus`—:
    /// cerrar la hoja con el teclado arriba lo deja bajando por su cuenta
    /// detrás de la animación, y se ve el tirón.
    func wkFocusOnAppear(_ focus: FocusState<Bool>.Binding, delay: Duration = .milliseconds(350)) -> some View {
        task {
            try? await Task.sleep(for: delay)
            focus.wrappedValue = true
        }
    }
}

/// Quita el teclado y espera a que baje antes de seguir. Ver
/// `wkFocusOnAppear`.
@MainActor
public func resignFocus(_ focus: FocusState<Bool>.Binding, then action: @escaping () -> Void) {
    guard focus.wrappedValue else { action(); return }
    focus.wrappedValue = false
    Task {
        try? await Task.sleep(for: .milliseconds(250))
        action()
    }
}
