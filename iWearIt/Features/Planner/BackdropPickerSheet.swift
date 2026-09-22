import SwiftUI
import WKCanvas
import WKDesign
import WKPersistence

/// Elige el color de fondo del outfit.
///
/// Hoja dinámica y sin barra: tocar un color **es** la acción y se ve el efecto
/// al instante, así que un botón de confirmar solo añadiría un paso.
struct BackdropPicker: View {
    /// El outfit, no el día.
    ///
    /// Ya no se presenta como hoja propia —de ahí que no acabe en `Sheet`—:
    /// vive dentro de la misma tarjeta de cristal que la bandeja, para que los
    /// dos botones que están uno al lado del otro se comporten igual.
    ///
    /// El color es de **cómo queda el outfit**, no del hueco del calendario, y
    /// por eso se elige desde dentro del editor: para cambiarlo antes había que
    /// salir a la pantalla de planificar, que es salirse de lo que estás
    /// haciendo para tocar lo que estás mirando.
    let outfit: Outfit

    @Environment(\.dismiss) private var dismiss

    private var current: String? { outfit.backdropRaw }

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.m) {
            Text("Color del fondo")
                .font(WK.Font.title)
                .foregroundStyle(WK.Palette.primaryText)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: WK.Spacing.s), count: 5),
                spacing: WK.Spacing.m
            ) {
                ForEach(OutfitBackdrop.allCases) { backdrop in
                    BackdropSwatch(
                        backdrop: backdrop,
                        isSelected: current == backdrop.rawValue
                    ) {
                        apply(backdrop)
                    }
                }
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.m)
    }

    private func apply(_ backdrop: OutfitBackdrop) {
        withAnimation(WKAnimation.selection) {
            outfit.backdropRaw = backdrop.rawValue
        }
        dismiss()
    }
}

/// Una muestra de color.
///
/// Vista propia y no un `@ViewBuilder` repetido seis veces: repetirlo dentro
/// del builder cuesta seis diffs en vez de uno por muestra.
private struct BackdropSwatch: View {
    let backdrop: OutfitBackdrop
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                // La muestra, igual de clara que como queda el lienzo.
                .fill(WK.Palette.canvasTint(
                    red: backdrop.components.red,
                    green: backdrop.components.green,
                    blue: backdrop.components.blue
                ))
                .frame(height: 56)
                .overlay {
                    RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                        .stroke(WK.Palette.accent, lineWidth: isSelected ? 3 : 0)
                }
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
        .animation(WKAnimation.selection, value: isSelected)
    }
}
