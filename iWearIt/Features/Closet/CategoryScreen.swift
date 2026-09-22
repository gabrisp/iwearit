import SwiftData
import SwiftUI
import WKDesign
import WKPersistence

/// Una balda vista en vertical, con todas sus prendas.
///
/// ## El modo selección
///
/// Quitar prendas de una en una —abrir la ficha, editar, eliminar, confirmar,
/// volver— es cuatro pantallas por prenda, y las prendas que sobran nunca
/// sobran de una en una: sobran diez de golpe después de una importación
/// mala. El lápiz de la barra enciende la selección múltiple y el borrado va
/// abajo, centrado y con el número de lo que se lleva.
struct CategoryScreen: View {
    private let name: String
    /// Si esta pantalla **ya es** la de favoritas: entonces el filtro sobra.
    private let isFavouritesOnly: Bool
    @Query private var garments: [Garment]
    @State private var searchText = ""
    /// El filtro del corazón. Se apaga al salir: es una forma de mirar, no un
    /// ajuste que haya que acordarse de quitar.
    @State private var showsFavouritesOnly = false
    @State private var isSelecting = false
    /// Lo marcado, por identidad persistente y no por objeto: así la selección
    /// sobrevive a que la consulta se reordene.
    @State private var selection: Set<PersistentIdentifier> = []
    // Lo borra `closetBulkActions`.
    // @State private var isConfirmingDelete = false

    @Environment(\.modelContext) private var modelContext

    init(slug: String, name: String) {
        self.name = name
        self.isFavouritesOnly = false
        _garments = Query(FetchDescriptor<Garment>.visibleGarments(inCategoryWithSlug: slug))
    }

    /// Todas las favoritas, de cualquier balda.
    ///
    /// La misma pantalla y no una nueva: buscar, seleccionar y borrar
    /// funcionan igual, y lo único que cambia es de dónde salen las prendas.
    init(favourites name: String) {
        self.name = name
        self.isFavouritesOnly = true
        _garments = Query(FetchDescriptor<Garment>.favouriteGarments())
    }

    private var visible: [Garment] {
        var result = garments
        if showsFavouritesOnly { result = result.filter(\.isFavorite) }
        guard !searchText.isEmpty else { return result }
        return result.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), spacing: WK.Spacing.m)],
                spacing: WK.Spacing.l
            ) {
                ForEach(visible) { garment in
                    HangingGarmentView(
                        garment: GarmentRef(garment),
                        isSelecting: isSelecting,
                        isSelected: selection.contains(garment.persistentModelID),
                        onToggleSelection: { toggle(garment) }
                    )
                }
            }
            .padding(WK.Spacing.m)
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas.ignoresSafeArea())
        .adaptiveScrollEdge(.top)
        // El título y el buscador del sistema, como siempre. El campo dentro
        // de la barra se probó y estaba peor: la balda perdía su nombre.
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Buscar en \(name)")
        .toolbar {
            // El campo en el centro de la barra, comentado: ver arriba.
            // ToolbarItem(placement: .principal) {
            //     CategorySearchField(text: $searchText, shelf: name)
            // }
            // **El corazón filtra, no marca.** En la balda hay veinte camisas
            // y las que se ponen de verdad son tres: esto las deja solas sin
            // salir de la balda ni perder lo que estuvieras buscando.
            if !isFavouritesOnly {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(WKAnimation.content) { showsFavouritesOnly.toggle() }
                    } label: {
                        Image(systemName: showsFavouritesOnly ? "heart.fill" : "heart")
                            .foregroundStyle(showsFavouritesOnly ? .red : WK.Palette.primaryText)
                            .contentTransition(.symbolEffect(.replace.downUp))
                            .contentShape(.rect)
                    }
                    .sensoryFeedback(.selection, trigger: showsFavouritesOnly)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(WKAnimation.content) {
                        isSelecting.toggle()
                        if !isSelecting { selection.removeAll() }
                    }
                } label: {
                    Image(systemName: isSelecting ? "xmark" : "pencil")
                }
                .tint(WK.Palette.primaryText)
            }
        }
        // **Las mismas acciones que en el armario**: mover, editar, etiquetas,
        // calidez, favorita y eliminar. Antes aquí solo se podía borrar.
        .closetBulkActions(on: selected, isActive: isSelecting) {
            selection.removeAll()
            isSelecting = false
        }
        .overlay {
            if visible.isEmpty {
                if showsFavouritesOnly || isFavouritesOnly, searchText.isEmpty {
                    ContentUnavailableView(
                        "Ninguna favorita",
                        systemImage: "heart",
                        description: Text("Marca con el corazón las prendas que más te pones.")
                    )
                } else {
                    ContentUnavailableView(
                        searchText.isEmpty ? "Balda vacía" : "Sin resultados",
                        systemImage: searchText.isEmpty ? "tray" : "magnifyingglass"
                    )
                }
            }
        }
    }

    /// Lo marcado, resuelto a prendas.
    private var selected: [Garment] {
        garments.filter { selection.contains($0.persistentModelID) }
    }

    // La barra de solo borrar. Sustituida por `closetBulkActions`, que trae
    // además mover, editar, etiquetas, calidez y favorita.
    //
    // @ViewBuilder
    // private var deleteBar: some View {
    //     if isSelecting {
    //         Button {
    //             isConfirmingDelete = true
    //         } label: {
    //             Label(
    //                 selection.isEmpty
    //                     ? "Selecciona prendas"
    //                     : "Eliminar \(selection.count)",
    //                 systemImage: "trash"
    //             )
    //             .font(WK.Font.headline)
    //             .foregroundStyle(selection.isEmpty ? WK.Palette.secondaryText : .red)
    //             .padding(.horizontal, WK.Spacing.l)
    //             .frame(height: 44)
    //             .contentShape(.capsule)
    //         }
    //         .buttonStyle(WKPressStyle())
    //         .disabled(selection.isEmpty)
    //         .adaptiveGlassInteractive(in: .capsule)
    //         .padding(.bottom, WK.Spacing.s)
    //         .transition(.move(edge: .bottom).combined(with: .opacity))
    //     }
    // }

    private func toggle(_ garment: Garment) {
        let id = garment.persistentModelID
        withAnimation(WKAnimation.selection) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        }
    }

    // private func deleteSelected() {
    //     let doomed = garments.filter { selection.contains($0.persistentModelID) }
    //     withAnimation(WKAnimation.content) {
    //         for garment in doomed { garment.markDeleted() }
    //         selection.removeAll()
    //         isSelecting = false
    //     }
    // }
}

// El buscador en la barra. Se queda comentado: el sistema ya pone uno y el
// título de la balda tiene que verse.
// /// El buscador de la balda, en el centro de la barra.
// ///
// /// Un campo y nada más: la lupa a la izquierda dice qué es, y la X aparece solo
// /// cuando hay algo escrito. En cristal, como el resto de la barra.
// private struct CategorySearchField: View {
//     @Binding var text: String
//     /// El nombre de la balda: es el marcador cuando no hay nada escrito, así
//     /// que no hace falta además un título encima.
//     let shelf: String

//     @FocusState private var isFocused: Bool

//     var body: some View {
//         HStack(spacing: WK.Spacing.xs) {
//             Image(systemName: "magnifyingglass")
//                 .font(.footnote.weight(.semibold))
//                 .foregroundStyle(WK.Palette.secondaryText)

//             TextField(shelf, text: $text)
//                 .font(WK.Font.callout)
//                 .foregroundStyle(WK.Palette.primaryText)
//                 .textInputAutocapitalization(.never)
//                 .autocorrectionDisabled()
//                 .submitLabel(.search)
//                 .focused($isFocused)

//             if !text.isEmpty {
//                 Button {
//                     text = ""
//                 } label: {
//                     Image(systemName: "xmark.circle.fill")
//                         .font(.footnote)
//                         .foregroundStyle(WK.Palette.tertiaryText)
//                         .contentShape(.circle)
//                 }
//                 .buttonStyle(WKPressStyle())
//                 .transition(.scale.combined(with: .opacity))
//             }
//         }
//         .padding(.horizontal, WK.Spacing.s)
//         .frame(width: 190, height: 36)
//         .adaptiveGlassInteractive(in: .capsule)
//         .animation(WKAnimation.selection, value: text.isEmpty)
//         .contentShape(.capsule)
//         .onTapGesture { isFocused = true }
//     }
// }
