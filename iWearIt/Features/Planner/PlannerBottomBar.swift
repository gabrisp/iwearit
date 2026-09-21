import SwiftUI
import WKDesign
import WKPersistence

/// La sección de acciones del planificador, sobre la tab bar.
///
/// **Una sola para toda la pantalla, no una por lienzo.** El botón vive aquí y
/// no dentro de cada página porque el scroll vertical tiene tantas páginas como
/// outfits tenga el día: repetirlo en cada una lo convierte en decorado que se
/// repite, y encima obliga a mirar dónde ha quedado esta vez.
///
/// El texto cambia según si hay outfit, y cambia **fundiéndose**: el botón es
/// el mismo objeto haciendo lo mismo —llevarte al lienzo—, y desaparecer para
/// reaparecer lo contaría como dos botones distintos.
///
/// Aquí abajo solo va **la acción**. Cómo se mira el plan —revista o rejilla—
/// es un ajuste de la vista y vive arriba, junto al día: mezclarlo con "editar
/// outfit" pone en la misma barra algo que cambia el contenido y algo que
/// cambia la forma de verlo.
struct PlannerBottomBar: View {
    let hasOutfit: Bool
    let onEdit: () -> Void

    var body: some View {
        // **Calcado del CTA del armario**: mismo contenedor, mismo `Label` con
        // `.headline`, mismos paddings, mismo cristal interactivo y misma
        // transición. Cualquier diferencia aquí se ve como un botón distinto
        // que hace lo mismo en otro sitio.
        AdaptiveGlassContainer(spacing: WK.Spacing.s) {
            content
        }
    }

    private var content: some View {
        Button(action: onEdit) {
            Label(
                hasOutfit ? "Editar outfit" : "Crear outfit",
                systemImage: hasOutfit ? "pencil" : "tshirt"
            )
            .font(.headline)
            .contentTransition(.numericText())
            .padding(.horizontal, WK.Spacing.l)
            .padding(.vertical, WK.Spacing.s + 2)
        }
        .adaptiveGlassInteractive(in: .capsule)
        .adaptiveGlassTransition()
        .animation(WKAnimation.content, value: hasOutfit)
    }
}
