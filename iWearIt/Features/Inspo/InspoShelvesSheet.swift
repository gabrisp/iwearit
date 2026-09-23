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
///
/// ## Y se elige con píldoras
///
/// Como el resto de la app —tipo, material, calidez, etiquetas—: una fila de
/// píldoras que se encienden. Una lista de interruptores era otro control
/// distinto para la misma pregunta, y encima ocupaba una fila por balda.
struct InspoShelvesSheet: View {
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
        return categories.filter { seen.insert($0.slug).inserted && !$0.visibleGarments.isEmpty }
    }

    var body: some View {
        WKChipSheet(
            title: "Qué entra",
            subtitle: "Lo que apagues sigue en el armario: solo deja de salir propuesto",
            options: shelves.map { .init(id: $0.slug, label: $0.name) },
            selection: Binding(
                get: { Set(shelves.filter { !$0.isExcludedFromInspo }.map(\.slug)) },
                set: { included in
                    for shelf in shelves {
                        shelf.isExcludedFromInspo = !included.contains(shelf.slug)
                    }
                }
            ),
            // Sin tope y pudiendo quedarse sin ninguna: apagarlas todas es una
            // respuesta válida —aunque entonces no haya nada que proponer— y
            // fingir que no lo es obliga a dejar una encendida a la fuerza.
            allowsEmpty: true
        )
    }
}
