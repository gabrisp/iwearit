import SwiftData
import SwiftUI
import WKDesign
import WKPersistence

/// Elegir balda con una rueda, no con un `Picker` del sistema.
///
/// Seleccionar **es** desplazar: la fila que queda en el centro es la
/// respuesta, y eso permite recorrer veinte baldas con un solo gesto en vez de
/// abrir un menú y buscar.
struct ShelfPickerSheet: View {
    @Bindable var garment: Garment

    @Query(
        filter: #Predicate<GarmentCategory> { !$0.isHidden && $0.deletedAt == nil },
        sort: [SortDescriptor(\GarmentCategory.sortOrder)]
    )
    private var categories: [GarmentCategory]

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            Text("Balda")
                .font(WK.Font.title)
                .foregroundStyle(WK.Palette.primaryText)

            WKWheelPicker(
                items: categories.map(\.slug),
                selection: $selection
            ) { slug in
                Text(categories.first { $0.slug == slug }?.name ?? "")
                    .font(WK.Font.title)
            }
            .frame(height: 220)

            WKPrimaryButton("Mover aquí") { apply() }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .wkDynamicSheet()
        .onAppear { selection = garment.category?.slug }
    }

    private func apply() {
        // Mover a mano bloquea la prenda: la auto-clasificación no vuelve a
        // tocarla. Que el modelo te devuelva mañana lo que moviste hoy es la
        // forma más rápida de perder la confianza del usuario.
        if let slug = selection, let category = categories.first(where: { $0.slug == slug }) {
            garment.category = category
            garment.categoryLockedByUser = true
        }
        dismiss()
    }
}
