import SwiftUI
import WKCore
import WKDesign

extension SuitcaseTint {
    /// El color de fondo de un lienzo de esta maleta.
    ///
    /// Vive en el target de la app y no junto al enum: `SuitcaseTint` está en
    /// `WKCore`, que no depende de nadie —SwiftUI incluido— y es esa regla la
    /// que mantiene el grafo en una sola dirección. El enum guarda los
    /// componentes; convertirlos en un `Color` es cosa de quien pinta.
    ///
    /// Al 35%: el tinte tiñe el papel, no lo sustituye. A plena intensidad la
    /// retícula de puntos desaparece y el lienzo deja de parecer papel.
    static func backdrop(for raw: String?) -> Color {
        guard let raw, let tint = SuitcaseTint(rawValue: raw) else { return WK.Palette.canvas }
        return Color(
            red: tint.components.red,
            green: tint.components.green,
            blue: tint.components.blue
        )
        .opacity(0.35)
    }
}
