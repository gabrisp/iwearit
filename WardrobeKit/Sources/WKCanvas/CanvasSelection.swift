import CoreGraphics
import Foundation
import Observation

/// Qué prenda está seleccionada.
///
/// Un `@Observable` minúsculo y no un `@State` en el canvas: solo lo leen el
/// anillo de selección y la barra de acciones, así que cambiar la selección no
/// reevalúa el canvas entero ni las prendas no implicadas.
@MainActor
@Observable
public final class CanvasSelection {
    public private(set) var selectedID: UUID?

    /// Si la pieza que se está moviendo está centrada, y en qué eje.
    ///
    /// Vive aquí y no en la prenda porque **lo dibuja el lienzo**: la guía
    /// cruza el papel de lado a lado, así que no puede salir de una vista que
    /// mide lo que mide la prenda. Y vive en este objeto y no en un `@State`
    /// del lienzo para no reevaluarlo entero en cada fotograma del arrastre.
    public var centering = CanvasMath.Centering()

    public init() {}

    public func select(_ id: UUID?) {
        guard selectedID != id else { return }
        selectedID = id
    }

    public func isSelected(_ id: UUID) -> Bool { selectedID == id }

    public func clear() {
        selectedID = nil
        centering = CanvasMath.Centering()
    }
}
