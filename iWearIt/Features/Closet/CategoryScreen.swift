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
    @Query private var garments: [Garment]
    @State private var searchText = ""
    @State private var isSelecting = false
    /// Lo marcado, por identidad persistente y no por objeto: así la selección
    /// sobrevive a que la consulta se reordene.
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var isConfirmingDelete = false

    @Environment(\.modelContext) private var modelContext

    init(slug: String, name: String) {
        self.name = name
        _garments = Query(FetchDescriptor<Garment>.visibleGarments(inCategoryWithSlug: slug))
    }

    private var visible: [Garment] {
        guard !searchText.isEmpty else { return garments }
        return garments.filter { $0.name.localizedStandardContains(searchText) }
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
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Buscar en \(name)")
        .toolbar {
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
        // El borrado, abajo y centrado: es donde llega el pulgar y es donde no
        // se toca sin querer al ir a por una prenda.
        .adaptiveSafeAreaBar(edge: .bottom) { deleteBar }
        .confirmationDialog(
            selection.count == 1
                ? "¿Eliminar esta prenda?"
                : "¿Eliminar \(selection.count) prendas?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) { deleteSelected() }
            Button("Cancelar", role: .cancel) {}
        }
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Balda vacía" : "Sin resultados",
                    systemImage: searchText.isEmpty ? "tray" : "magnifyingglass"
                )
            }
        }
    }

    @ViewBuilder
    private var deleteBar: some View {
        if isSelecting {
            Button {
                isConfirmingDelete = true
            } label: {
                Label(
                    selection.isEmpty
                        ? "Selecciona prendas"
                        : "Eliminar \(selection.count)",
                    systemImage: "trash"
                )
                .font(WK.Font.headline)
                .foregroundStyle(selection.isEmpty ? WK.Palette.secondaryText : .red)
                .padding(.horizontal, WK.Spacing.l)
                .frame(height: 44)
                .contentShape(.capsule)
            }
            .buttonStyle(WKPressStyle())
            .disabled(selection.isEmpty)
            .adaptiveGlassInteractive(in: .capsule)
            .padding(.bottom, WK.Spacing.s)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func toggle(_ garment: Garment) {
        let id = garment.persistentModelID
        withAnimation(WKAnimation.selection) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        }
    }

    private func deleteSelected() {
        let doomed = garments.filter { selection.contains($0.persistentModelID) }
        withAnimation(WKAnimation.content) {
            for garment in doomed { garment.markDeleted() }
            selection.removeAll()
            isSelecting = false
        }
    }
}
