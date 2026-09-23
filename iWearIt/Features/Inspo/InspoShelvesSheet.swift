import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Qué baldas entran en la inspiración.
///
/// ## Por qué por balda y no por prenda
///
/// Porque el armario ya está dividido así, y lo que sobra en las propuestas
/// suele sobrar entero: la ropa de disfraces, la de trabajar en el campo, la
/// de esquiar. Marcar prenda a prenda sería el mismo trabajo repetido treinta
/// veces para decir una sola cosa.
///
/// ## No es esconder la balda
///
/// Lo excluido sigue en el armario, se busca, se abre y se puede poner a mano
/// en cualquier outfit. Lo único que cambia es que el estilista no lo propone.
struct InspoShelvesSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<GarmentCategory> { !$0.isHidden && $0.deletedAt == nil },
        sort: [SortDescriptor(\GarmentCategory.sortOrder)]
    )
    private var categories: [GarmentCategory]

    /// Sin repetir slug: con sincronización pueden llegar dos filas de la
    /// misma balda, y una lista con dos "Camisetas" es un sinsentido. Ver
    /// `ClosetScreen`.
    private var shelves: [GarmentCategory] {
        var seen = Set<String>()
        return categories.filter { seen.insert($0.slug).inserted }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(shelves) { shelf in
                        InspoShelfRow(shelf: shelf)
                    }
                } footer: {
                    Text("Lo que dejes fuera sigue en el armario: solo deja de aparecer en las propuestas.")
                }
            }
            .navigationTitle("Qué entra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }
                        .tint(WK.Palette.primaryText)
                        .adaptiveProminentButton()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Una balda con su interruptor. Vista propia para que marcar una no
/// reevalúe la lista entera.
private struct InspoShelfRow: View {
    @Bindable var shelf: GarmentCategory

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { !shelf.isExcludedFromInspo },
                set: { shelf.isExcludedFromInspo = !$0 }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(shelf.name)
                    .foregroundStyle(WK.Palette.primaryText)
                Text("\(shelf.visibleGarments.count) prendas")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
            }
        }
    }
}
