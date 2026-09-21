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

    public init() {}

    public func select(_ id: UUID?) {
        guard selectedID != id else { return }
        selectedID = id
    }

    public func isSelected(_ id: UUID) -> Bool { selectedID == id }
    public func clear() { selectedID = nil }
}
