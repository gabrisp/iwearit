import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// Los outfits de la maleta, **como el plan**: un lienzo por pantalla, los días
/// de lado y la tarjeta de crear al final.
///
/// ## Por qué el mismo gesto que en el plan
///
/// Porque es lo mismo: días con ropa asignada. Que la maleta se hojeara de una
/// manera y el plan de otra obligaba a aprender dos veces lo mismo, y encima la
/// de la maleta era la rara —paso de página con curl— justo en la pantalla
/// donde menos falta hace.
///
/// - Note: la pestaña vieja (`SuitcaseOutfitsTab`) **no se ha borrado**: sigue
///   en el repositorio con su revista, su rejilla con fechas y su lista de
///   preparados. Volver es cambiar una línea en `SuitcaseDetailScreen`.
struct SuitcaseOutfitsFeedTab: View {
    let suitcase: Suitcase
    @Binding var dayIndex: Int
    /// Lo que tapan las barras de la maleta, que ignora el área segura.
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    let onEdit: (Outfit, Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var layout: Layout = .feed
    @State private var pageSize: CGSize = .zero
    @State private var movingOutfit: Outfit?
    @State private var isPicking = false
    @State private var page: Int?

    @Namespace private var morph

    enum Layout { case feed, grid }

    /// Los días del viaje. Sin fechas, un solo hueco: lo preparado.
    private var dayCount: Int { suitcase.tripDayCount ?? 1 }

    private func outfits(ofDay index: Int) -> [Outfit] {
        suitcase.visibleOutfits
            .filter { !$0.garments.isEmpty }
            .filter { suitcase.tripDayCount == nil || $0.suitcaseDayIndex == index }
    }

    var body: some View {
        pager
            .background(WK.Palette.canvas.ignoresSafeArea())
            .safeAreaPadding(.top, topInset)
            .safeAreaPadding(.bottom, bottomInset)
            .sheet(item: $movingOutfit) { outfit in
                SuitcaseDayPicker(suitcase: suitcase) { index in
                    outfit.suitcaseDayIndex = index
                    try? modelContext.save()
                    movingOutfit = nil
                }
            }
            .sheet(isPresented: $isPicking) {
                OutfitPickerSheet(store: appEnvironment.imageStore) { picked in
                    guard !picked.isEmpty else { return }
                    create(with: picked)
                }
            }
            .onChange(of: page) { _, value in
                if let value { dayIndex = value }
            }
            .onChange(of: dayIndex) { _, value in
                if page != value { page = value }
            }
            .task { page = dayIndex }
            .animation(WKAnimation.content, value: layout)
            .overlay(alignment: .topTrailing) { layoutButton }
    }

    /// Cambiar de modo. Aquí y no en la barra de la pantalla: la barra es de la
    /// maleta y esto es de esta pestaña.
    private var layoutButton: some View {
        WKCircleButton(layout == .feed ? "square.grid.2x2" : "rectangle.portrait") {
            withAnimation(WKAnimation.content) {
                layout = layout == .feed ? .grid : .feed
            }
        }
        .tint(WK.Palette.primaryText)
        .padding(.trailing, WK.Spacing.screenInset)
        .padding(.top, WK.Spacing.s)
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(0..<dayCount, id: \.self) { index in
                    Group {
                        switch layout {
                        case .feed: feed(ofDay: index)
                        case .grid: grid(ofDay: index)
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
    }

    private func feed(ofDay index: Int) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(outfits(ofDay: index), id: \.stableID) { outfit in
                    SuitcaseFeedCard(
                        outfit: outfit,
                        suitcase: suitcase,
                        store: appEnvironment.imageStore,
                        onEdit: { onEdit(outfit, false) },
                        onMove: { movingOutfit = outfit }
                    )
                    .matchedGeometryEffect(id: outfit.stableID, in: morph)
                    .modifier(PlanCardSize(page: pageSize))
                }

                // Asomarse es crear, como en el plan.
                PlanCreateCard(title: "Añadir un outfit")
                    .matchedGeometryEffect(id: "create-\(index)", in: morph)
                    .modifier(PlanCardSize(page: pageSize))
                    // Solo si había outfits detrás: ver `PlanFeedScreen`.
                    .onScrollVisibilityChange(threshold: 0.55) { isVisible in
                        guard isVisible, !isPicking else { return }
                        guard !outfits(ofDay: index).isEmpty else { return }
                        isPicking = true
                    }
                    .onTapGesture { isPicking = true }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    private func grid(ofDay index: Int) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: WK.Spacing.m)],
                spacing: WK.Spacing.m
            ) {
                ForEach(outfits(ofDay: index), id: \.stableID) { outfit in
                    SuitcaseFeedCard(
                        outfit: outfit,
                        suitcase: suitcase,
                        store: appEnvironment.imageStore,
                        isCompact: true,
                        onEdit: { onEdit(outfit, false) },
                        onMove: { movingOutfit = outfit }
                    )
                    .matchedGeometryEffect(id: outfit.stableID, in: morph)
                }

                PlanCreateCard(title: "Añadir")
                    .matchedGeometryEffect(id: "create-\(index)", in: morph)
                    .aspectRatio(CanvasSpace.width / CanvasSpace.height, contentMode: .fit)
                    .onTapGesture { isPicking = true }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.top, WK.Spacing.xl)
        }
        .scrollIndicators(.hidden)
    }

    private func create(with garments: [Garment]) {
        // Sin origen: `inspo` es para lo que propuso el estilista, y esto lo
        // has montado tú eligiendo prendas.
        let outfit = OutfitAssembly.make(
            from: garments,
            name: nil,
            origin: nil,
            isFavorite: false,
            backdropRaw: nil,
            context: modelContext
        )
        outfit.suitcase = suitcase
        if suitcase.tripDayCount != nil { outfit.suitcaseDayIndex = page ?? dayIndex }
        try? modelContext.save()
        onEdit(outfit, true)
    }
}

/// Un outfit de la maleta. Las mismas dos acciones que en el plan: el lápiz y
/// mover. Ni corazón ni calendario — aquí el día es el del viaje, y para eso
/// está mover.
private struct SuitcaseFeedCard: View {
    let outfit: Outfit
    let suitcase: Suitcase
    let store: ImageStore
    var isCompact = false
    let onEdit: () -> Void
    let onMove: () -> Void

    var body: some View {
        LookCanvasView(
            garments: outfit.garments,
            store: store,
            backdrop: backdrop,
            outfit: outfit,
            showsBorder: true
        )
        .overlay(alignment: .topTrailing) {
            VStack(spacing: WK.Spacing.xs) {
                WKCircleButton("pencil", size: .compact, action: onEdit)
                    .tint(WK.Palette.primaryText)
                if suitcase.tripDayCount != nil {
                    WKCircleButton(
                        "arrow.up.and.down.and.arrow.left.and.right",
                        size: .compact,
                        action: onMove
                    )
                    .tint(WK.Palette.primaryText)
                }
            }
            .padding(isCompact ? WK.Spacing.xs : WK.Spacing.m)
        }
    }

    /// El papel de la maleta, que es lo que la distingue de las demás.
    private var backdrop: Color {
        guard
            let raw = suitcase.colorRaw,
            let tint = SuitcaseTint(rawValue: raw)
        else { return WK.Palette.canvas }
        return WK.Palette.canvasTint(
            red: tint.components.red,
            green: tint.components.green,
            blue: tint.components.blue
        )
    }
}
