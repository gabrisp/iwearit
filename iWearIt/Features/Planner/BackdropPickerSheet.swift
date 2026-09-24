import SwiftUI
import WKCanvas
import WKCore
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

    /// El color de la ropa de **este** conjunto, apagado. `nil` si el conjunto
    /// todavía no tiene prendas con color analizado.
    private var extracted: String? {
        OutfitBackdropPalette.extracted(
            from: outfit.garments.compactMap(\.colors.first).map {
                (red: $0.red, green: $0.green, blue: $0.blue, weight: $0.weight)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.m) {
            Text(String(localized: "planner.backdroppickersheet.backgroundColor", defaultValue: "Background color"))
                .font(WK.Font.title)
                .foregroundStyle(WK.Palette.primaryText)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: WK.Spacing.s), count: 5),
                spacing: WK.Spacing.m
            ) {
                // **El de la propia ropa, el primero.**
                //
                // Sacado de las prendas del conjunto y apagado: el papel tiene
                // que recordar a lo que sostiene sin competir con ello. Es el
                // único que no está en la paleta porque no puede estarlo —
                // cambia con cada outfit—. Ver `OutfitBackdropPalette`.
                if let extracted {
                    ColorSwatch(
                        components: OutfitBackdropPalette.components(for: extracted)
                            ?? (red: 1, green: 1, blue: 1),
                        isSelected: current == extracted,
                        badge: "eyedropper"
                    ) {
                        withAnimation(WKAnimation.selection) { outfit.backdropRaw = extracted }
                        dismiss()
                    }
                }

                ForEach(OutfitBackdrop.allCases) { backdrop in
                    ColorSwatch(
                        components: backdrop.components,
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
private struct ColorSwatch: View {
    let components: (red: Double, green: Double, blue: Double)
    let isSelected: Bool
    /// Un símbolo en la esquina, para la muestra que no es de la paleta.
    var badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                // La muestra, igual de clara que como queda el lienzo.
                .fill(WK.Palette.canvasTint(
                    red: components.red,
                    green: components.green,
                    blue: components.blue
                ))
                .frame(height: 56)
                .overlay {
                    RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                        .stroke(WK.Palette.accent, lineWidth: isSelected ? 3 : 0)
                }
                .overlay {
                    if let badge {
                        Image(systemName: badge)
                            .font(.caption)
                            .foregroundStyle(WK.Palette.secondaryText)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}
