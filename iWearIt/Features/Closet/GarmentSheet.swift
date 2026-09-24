import SwiftData
import SwiftUI
import WKDesign
import WKPersistence

/// La hoja que se abre al **tocar** una prenda.
///
/// No es el editor. Aquí solo se mira la prenda y se decide qué hacer con
/// ella; cambiar sus datos es una de las opciones, no el estado por defecto.
/// Abrir directo en modo edición obliga a leer cinco filas de formulario para
/// hacer lo que casi siempre se quiere hacer, que es ponérsela en un outfit.
struct GarmentSheet: View {
    @Bindable var garment: Garment
    /// Se llama cuando esta hoja **ya se ha ido** tras pedir borrar la prenda.
    var onDelete: (() -> Void)?
    @State private var isDeleting = false

    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var isPresentingEditor = false
    @State private var isPresentingComposer = false

    var body: some View {
        VStack(spacing: WK.Spacing.l) {
            GarmentSheetChrome(name: garment.name)

            // Con las dos versiones a un toque: la foto recortada y, si se ha
            // generado, la reconstruida. Ver `GarmentImageSwitcher`.
            GarmentImageSwitcher(garment: garment)

            actions
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.top, WK.Spacing.m)
        // Del tamaño de su contenido. Una hoja a pantalla completa para cuatro
        // botones y una foto obliga a un gesto largo para volver a lo que
        // estabas mirando, y deja media pantalla vacía.
        .wkDynamicSheet()
        // Borrar cierra primero el editor, luego esta hoja, y solo entonces
        // se borra la prenda. Al revés, la prenda desaparecía de la balda con
        // la hoja todavía abierta y la hoja se desmontaba borrosa.
        .sheet(isPresented: $isPresentingEditor, onDismiss: {
            guard isDeleting else { return }
            if let onDelete { onDelete() } else { garment.markDeleted() }
            dismiss()
        }) {
            GarmentEditSheet(garment: garment, onDelete: { isDeleting = true })
        }
        .outfitCreationFlow(isActive: $isPresentingComposer, startingGarment: garment)
    }

    /// Cuatro acciones y ninguna más. La lista larga de opciones convierte una
    /// decisión de un segundo en una pantalla que hay que leer.
    private var actions: some View {
        HStack(alignment: .top, spacing: WK.Spacing.m) {
            GarmentAction(symbol: "tshirt", label: String(localized: "common.createOutfit", defaultValue: "Create outfit")) {
                isPresentingComposer = true
            }
            GarmentAction(
                symbol: garment.isFavorite ? "heart.fill" : "heart",
                label: String(localized: "closet.garmentsheet.favorite", defaultValue: "Favorite"),
                tint: garment.isFavorite ? .red : nil
            ) {
                withAnimation(WKAnimation.selection) { garment.isFavorite.toggle() }
            }
            GarmentAction(symbol: "slider.horizontal.3", label: String(localized: "common.edit", defaultValue: "Edit")) {
                isPresentingEditor = true
            }
            GarmentAction(symbol: "square.and.arrow.up", label: String(localized: "closet.garmentsheet.share", defaultValue: "Share")) {
                // TODO(F11): ShareLink con el recorte en PNG.
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// La píldora con el nombre.
///
/// El nombre y no la marca: "Zara" describe a mil prendas y no distingue
/// ninguna. Lo que hace falta leer de un vistazo es cuál de todas es esta.
///
/// Sin chevron de vuelta: es una hoja del tamaño de su contenido, y se cierra
/// arrastrando o tocando fuera. Un botón para lo que ya hace el gesto ocupa
/// sitio y sugiere que hace falta.
private struct GarmentSheetChrome: View {
    let name: String

    var body: some View {
        Text(name)
            .font(WK.Font.headline)
            .foregroundStyle(WK.Palette.primaryText)
            .lineLimit(1)
            .padding(.horizontal, WK.Spacing.m)
            .padding(.vertical, WK.Spacing.s)
            .adaptiveGlass(in: .capsule)
            .frame(maxWidth: .infinity)
    }
}

/// Un botón circular con su etiqueta debajo.
///
/// Vista propia y no un `@ViewBuilder` repetido cuatro veces: es exactamente el
/// caso en que repetir el cuerpo dentro del builder cuesta cuatro diffs en vez
/// de uno por acción.
private struct GarmentAction: View {
    let symbol: String
    let label: String
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: WK.Spacing.s) {
                Image(systemName: symbol)
                    .font(WK.Font.headline)
                    .foregroundStyle(tint ?? WK.Palette.primaryText)
                    .frame(width: 56, height: 56)
                    .background(WK.Palette.ink(0.07), in: .circle)
                    .contentShape(.circle)
                    .contentTransition(.symbolEffect(.replace.downUp))

                Text(label)
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(WKPressStyle())
    }
}
