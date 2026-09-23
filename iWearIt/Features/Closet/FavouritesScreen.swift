import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// Lo que has marcado como tuyo: prendas y conjuntos, en el mismo sitio.
///
/// ## Por qué juntos
///
/// Porque el corazón significa lo mismo en los dos casos —"esto me gusta"— y
/// separarlos en dos pantallas obliga a acordarse de en cuál guardaste qué.
/// Aquí están todos y el filtro de abajo enseña solo prendas o solo conjuntos
/// cuando hace falta.
struct FavouritesScreen: View {
    /// Presentada como hoja —el archivo del estilista— necesita su equis: una
    /// pantalla empujada se cierra con el gesto de volver, una hoja no siempre.
    var isModal = false

    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(FetchDescriptor<Garment>.favouriteGarments())
    private var garments: [Garment]

    @Query(FetchDescriptor<Outfit>.favouriteOutfits())
    private var outfits: [Outfit]

    /// Qué se está mirando. Se apaga al salir: es una forma de mirar, no un
    /// ajuste que haya que acordarse de quitar.
    @State private var filter: Filter = .all
    @State private var editingOutfit: Outfit?
    /// Si se está eligiendo qué quitar.
    @State private var isSelecting = false
    @State private var pickedOutfits: Set<PersistentIdentifier> = []
    @State private var pickedGarments: Set<PersistentIdentifier> = []
    @Environment(\.modelContext) private var modelContext
    /// De dónde sale el editor al abrirse: de la celda que se ha tocado.
    @Namespace private var zoom

    enum Filter: Hashable, CaseIterable {
        case all, garments, outfits

        var title: String {
            switch self {
            case .all: "Todo"
            case .garments: "Prendas"
            case .outfits: "Outfits"
            }
        }
    }

    private var showsOutfits: Bool { filter != .garments }
    private var showsGarments: Bool { filter != .outfits }
    private var visibleOutfits: [Outfit] { outfits.filter { !$0.garments.isEmpty } }

    /// **El filtro solo cuando hay de los dos.**
    ///
    /// Con solo prendas guardadas, "Todo · Prendas · Outfits" ofrece dos
    /// pestañas que enseñan lo mismo y una que se queda en blanco: es un
    /// control que promete algo que no hay. Aparece cuando hay las dos cosas,
    /// que es cuando de verdad sirve para separarlas.
    private var showsFilter: Bool { !visibleOutfits.isEmpty && !garments.isEmpty }

    private var pickedCount: Int { pickedOutfits.count + pickedGarments.count }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: WK.Spacing.l) {
                if showsOutfits, !visibleOutfits.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: WK.Spacing.m)],
                        spacing: WK.Spacing.m
                    ) {
                        ForEach(visibleOutfits, id: \.stableID) { outfit in
                            FavouriteOutfitCell(
                                outfit: outfit,
                                store: appEnvironment.imageStore,
                                isSelecting: isSelecting,
                                isSelected: pickedOutfits.contains(outfit.persistentModelID),
                                onToggle: { toggle(outfit) },
                                onOpen: { editingOutfit = outfit }
                            )
                            // El editor sale **de su celda**, como en el plan.
                            .adaptiveZoomSource(id: AnyHashable(outfit.stableID), in: zoom)
                        }
                    }
                    .transition(.blurReplace)
                }

                if showsGarments, !garments.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 108), spacing: WK.Spacing.m)],
                        spacing: WK.Spacing.l
                    ) {
                        ForEach(garments) { garment in
                            // La percha ya sabe elegirse: es la misma que usa
                            // la edición en bloque del armario.
                            HangingGarmentView(
                                garment: GarmentRef(garment),
                                isSelecting: isSelecting,
                                isSelected: pickedGarments.contains(garment.persistentModelID),
                                onToggleSelection: { toggle(garment) }
                            )
                        }
                    }
                    .transition(.blurReplace)
                }
            }
            // El mismo margen que la barra de arriba y que el resto de
            // pantallas: con el de dentro de una tarjeta, la rejilla no
            // cuadraba con el título ni con los botones.
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.vertical, WK.Spacing.m)
            // **El cambio de filtro se mueve.** Lo que entra y lo que sale es
            // lo mismo que había —las mismas celdas, unas cuantas menos—, así
            // que cambiar de golpe parece que la pantalla se ha recargado en
            // vez de que se ha filtrado.
            .animation(WKAnimation.content, value: filter)
        }
        // Y si deja de haber de los dos tipos mientras quitas cosas, el filtro
        // se va y lo que quede se enseña entero.
        .onChange(of: showsFilter) { _, both in
            if !both { withAnimation(WKAnimation.content) { filter = .all } }
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas.ignoresSafeArea())
        .adaptiveScrollEdge(.top)
        .navigationTitle("Favoritos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal, !isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(WK.Palette.primaryText)
                }
            }
            // **El lápiz elige, el visto termina.** Quitar de favoritos de uno
            // en uno es abrir cada prenda y buscar su corazón; aquí se marcan
            // las que sobran y se quitan de una vez.
            if !garments.isEmpty || !visibleOutfits.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(WKAnimation.selection) {
                            isSelecting.toggle()
                            if !isSelecting { clearPicks() }
                        }
                    } label: {
                        Image(systemName: isSelecting ? "checkmark" : "pencil")
                    }
                    .tint(WK.Palette.primaryText)
                }
            }
        }
        .overlay {
            if visibleOutfits.isEmpty, garments.isEmpty {
                ContentUnavailableView {
                    Label("Todavía no hay favoritos", systemImage: "heart")
                } description: {
                    Text("El corazón de una prenda o de un conjunto lo guarda aquí.")
                }
            }
        }
        // El filtro abajo y no en la barra de arriba: es donde está el pulgar
        // y es donde vive el mismo control en las maletas.
        .adaptiveSafeAreaBar(edge: .bottom) { bottomBar }
        .animation(WKAnimation.content, value: isSelecting)
        .navigationDestination(item: $editingOutfit) { outfit in
            AdvancedCanvasScreen(outfit: outfit, store: appEnvironment.imageStore)
                .adaptiveZoomDestination(id: AnyHashable(outfit.stableID), in: zoom)
        }
    }

    /// Abajo: el filtro, o lo que se hace con lo marcado.
    @ViewBuilder
    private var bottomBar: some View {
        if isSelecting {
            FavouritesRemoveBar(count: pickedCount, action: removePicked)
        } else if showsFilter {
            WKTextTabBar(
                tabs: Filter.allCases,
                // Animado desde el propio enlace: el control segmentado es de
                // UIKit y escribe el valor a secas, así que si no se anima
                // aquí no se anima en ningún sitio.
                selection: Binding(
                    get: { filter },
                    set: { new in withAnimation(WKAnimation.content) { filter = new } }
                )
            ) { $0.title }
                .sensoryFeedback(.selection, trigger: filter)
                .padding(.bottom, WK.Spacing.xs)
        }
    }

    // MARK: Elegir y quitar

    private func toggle(_ outfit: Outfit) {
        let id = outfit.persistentModelID
        withAnimation(WKAnimation.selection) {
            if pickedOutfits.contains(id) { pickedOutfits.remove(id) } else { pickedOutfits.insert(id) }
        }
    }

    private func toggle(_ garment: Garment) {
        let id = garment.persistentModelID
        withAnimation(WKAnimation.selection) {
            if pickedGarments.contains(id) { pickedGarments.remove(id) } else { pickedGarments.insert(id) }
        }
    }

    private func clearPicks() {
        pickedOutfits.removeAll()
        pickedGarments.removeAll()
    }

    /// Quitar de favoritos **no es borrar**… salvo cuando lo es.
    ///
    /// Una prenda sigue en el armario sin corazón, así que basta con quitarlo.
    /// Un conjunto propuesto por la inspiración, en cambio, **solo existe
    /// porque lo guardaste**: si le quitas el corazón y no está en ningún día
    /// ni en ninguna maleta, dejarlo sería guardar algo que ya no aparece en
    /// ninguna pantalla. Ese se esconde; los demás solo pierden el corazón.
    private func removePicked() {
        withAnimation(WKAnimation.content) {
            for outfit in visibleOutfits where pickedOutfits.contains(outfit.persistentModelID) {
                outfit.isFavorite = false
                if outfit.plannedDay == nil, outfit.suitcase == nil {
                    outfit.markDeleted()
                }
            }
            for garment in garments where pickedGarments.contains(garment.persistentModelID) {
                garment.isFavorite = false
            }
            clearPicks()
        }
        try? modelContext.save()
    }
}

/// Lo que se hace con lo marcado: quitarlo de favoritos.
///
/// Una sola acción y con su nombre escrito: aquí no hay seis cosas que hacer
/// en bloque como en el armario, hay una, y un icono suelto en una barra vacía
/// no dice de qué va.
private struct FavouritesRemoveBar: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WK.Spacing.xs) {
                Image(systemName: "heart.slash")
                Text(count == 1 ? "Quitar 1" : "Quitar \(count)")
            }
            .font(WK.Font.headline)
            .foregroundStyle(count == 0 ? WK.Palette.secondaryText : WK.Palette.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .contentShape(.capsule)
        }
        .buttonStyle(WKPlainGlassButtonStyle(shape: Capsule(style: .continuous)))
        .disabled(count == 0)
        .opacity(count == 0 ? 0.5 : 1)
        .animation(WKAnimation.selection, value: count)
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.xs)
    }
}

/// Un conjunto guardado: se mira, y con doble toque o pulsación larga se abre
/// en su editor, como cualquier otro lienzo de la app.
private struct FavouriteOutfitCell: View {
    let outfit: Outfit
    let store: ImageStore
    /// En modo selección el toque **marca** en vez de abrir el editor, igual
    /// que en la percha de una prenda.
    var isSelecting = false
    var isSelected = false
    var onToggle: () -> Void = {}
    let onOpen: () -> Void

    var body: some View {
        LookCanvasView(
            garments: outfit.garments,
            store: store,
            backdrop: backdropColor,
            outfit: outfit,
            showsBorder: true
        )
        .overlay(alignment: .topTrailing) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        isSelected ? WK.Palette.onAccent : WK.Palette.secondaryText,
                        isSelected ? WK.Palette.accent : WK.Palette.ink(0.08)
                    )
                    .padding(WK.Spacing.s)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .opacity(isSelecting && !isSelected ? 0.55 : 1)
        .scaleEffect(isSelecting && !isSelected ? 0.94 : 1)
        .animation(WKAnimation.selection, value: isSelected)
        .animation(WKAnimation.selection, value: isSelecting)
        // **El lápiz, que es por donde se entra ahora.** Al quitar el doble
        // toque y la pulsación larga esta celda se quedaba sin puerta, y un
        // favorito que no se puede abrir es una foto.
        .overlay(alignment: .topLeading) {
            if !isSelecting {
                WKCircleButton("pencil", size: .compact, action: onOpen)
                    .tint(WK.Palette.primaryText)
                    .padding(WK.Spacing.s)
            }
        }
        .contentShape(.rect)
        // Un toque marca mientras se está eligiendo; fuera de eso, la tarjeta
        // se abre como siempre.
        .onTapGesture { if isSelecting { onToggle() } }
        // Sin doble toque ni pulsación larga: ver `InspoLookCard`. Aquí
        // además abrían el editor, que descarta el outfit al cerrarse con la
        // equis — dos toques sin querer y el favorito se iba.
        // .onTapGesture(count: 2) { if !isSelecting { onOpen() } }
        // .onLongPressGesture { if !isSelecting { onOpen() } }
    }

    private var backdropColor: Color {
        guard let components = OutfitBackdrop(rawValue: outfit.backdropRaw ?? "")?.components else {
            return WK.Palette.canvas
        }
        return WK.Palette.canvasTint(
            red: components.red,
            green: components.green,
            blue: components.blue
        )
    }
}
