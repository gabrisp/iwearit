import SwiftUI

/// Separador entre grupos de la toolbar.
///
/// `ToolbarSpacer` es iOS 26. En iOS 18 no existe nada equivalente, así que se
/// omite: los items quedan juntos en un solo grupo, que es la degradación
/// correcta — no se inventa un hueco que el sistema no sabe dibujar.
public struct AdaptiveToolbarSpacer: ToolbarContent {
    public init() {}

    @ToolbarContentBuilder
    public var body: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarSpacer(.fixed)
        }
    }
}
