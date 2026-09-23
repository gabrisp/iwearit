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
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(FetchDescriptor<Garment>.favouriteGarments())
    private var garments: [Garment]

    @Query(FetchDescriptor<Outfit>.favouriteOutfits())
    private var outfits: [Outfit]

    /// Qué se está mirando. Se apaga al salir: es una forma de mirar, no un
    /// ajuste que haya que acordarse de quitar.
    @State private var filter: Filter = .all
    @State private var editingOutfit: Outfit?
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
                            HangingGarmentView(garment: GarmentRef(garment))
                        }
                    }
                    .transition(.blurReplace)
                }
            }
            .padding(WK.Spacing.m)
            // **El cambio de filtro se mueve.** Lo que entra y lo que sale es
            // lo mismo que había —las mismas celdas, unas cuantas menos—, así
            // que cambiar de golpe parece que la pantalla se ha recargado en
            // vez de que se ha filtrado.
            .animation(WKAnimation.content, value: filter)
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas.ignoresSafeArea())
        .adaptiveScrollEdge(.top)
        .navigationTitle("Favoritos")
        .navigationBarTitleDisplayMode(.inline)
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
        .adaptiveSafeAreaBar(edge: .bottom) {
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
        .navigationDestination(item: $editingOutfit) { outfit in
            AdvancedCanvasScreen(outfit: outfit, store: appEnvironment.imageStore)
                .adaptiveZoomDestination(id: AnyHashable(outfit.stableID), in: zoom)
        }
    }
}

/// Un conjunto guardado: se mira, y con doble toque o pulsación larga se abre
/// en su editor, como cualquier otro lienzo de la app.
private struct FavouriteOutfitCell: View {
    let outfit: Outfit
    let store: ImageStore
    let onOpen: () -> Void

    var body: some View {
        LookCanvasView(
            garments: outfit.garments,
            store: store,
            backdrop: backdropColor,
            outfit: outfit,
            showsBorder: true
        )
        .contentShape(.rect)
        .onTapGesture(count: 2, perform: onOpen)
        .onLongPressGesture(perform: onOpen)
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
