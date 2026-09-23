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
    /// Revista o rejilla. **Lo decide la pantalla**, no esta pestaña: el botón
    /// vive en la barra de la maleta, junto a la tira de días, igual que en el
    /// plan. Tenerlo aquí además del de la barra eran dos botones para lo
    /// mismo que ni siquiera se ponían de acuerdo.
    let layout: PlannerLayout
    /// Lo que tapan las barras de la maleta, que ignora el área segura.
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    let onEdit: (Outfit, Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var pageSize: CGSize = .zero
    @State private var movingOutfit: Outfit?
    @State private var isPicking = false
    @State private var page: Int?

    @Namespace private var morph

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
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(0..<dayCount, id: \.self) { index in
                    Group {
                        switch layout {
                        case .book: feed(ofDay: index)
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
        // Con su propio scroll, como en el plan: el sitio por donde va es del
        // día, no de la pestaña. Ver `PlanDayFeed`.
        SuitcaseDayFeed(
            outfits: outfits(ofDay: index),
            suitcase: suitcase,
            store: appEnvironment.imageStore,
            pageSize: pageSize,
            morph: morph,
            createID: "create-\(index)",
            isPicking: isPicking,
            onEdit: { onEdit($0, false) },
            onMove: { movingOutfit = $0 },
            onCreate: { isPicking = true }
        )
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
                    // El mismo menú que en la rejilla del plan: aquí se ven
                    // varios a la vez y es cuando apetece copiar uno o
                    // cambiarlo de día.
                    .contextMenu {
                        Button("Editar", systemImage: "pencil") { onEdit(outfit, false) }
                        Button("Duplicar", systemImage: "plus.square.on.square") {
                            duplicate(outfit)
                        }
                        if suitcase.tripDayCount != nil {
                            Button("Mover a otro día", systemImage: "calendar") {
                                movingOutfit = outfit
                            }
                        }
                        Button("Eliminar", systemImage: "trash", role: .destructive) {
                            withAnimation(WKAnimation.content) { outfit.markDeleted() }
                        }
                    }
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

    /// Copiar uno para variarlo. Se queda en la misma maleta y en el mismo
    /// día del viaje, que es de donde sale.
    private func duplicate(_ outfit: Outfit) {
        let copy = Outfit(name: outfit.name)
        copy.backdropRaw = outfit.backdropRaw
        modelContext.insert(copy)
        copy.suitcase = suitcase
        copy.suitcaseDayIndex = outfit.suitcaseDayIndex

        for item in outfit.visibleItems {
            let clone = CanvasItem(transform: item.transform, garment: item.garment)
            if let sticker = item.sticker { clone.apply(sticker) }
            clone.isFlipped = item.isFlipped
            clone.outfit = copy
            modelContext.insert(clone)
        }
        try? modelContext.save()
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

/// Los outfits de un día del viaje, uno por pantalla.
private struct SuitcaseDayFeed: View {
    let outfits: [Outfit]
    let suitcase: Suitcase
    let store: ImageStore
    let pageSize: CGSize
    let morph: Namespace.ID
    let createID: String
    let isPicking: Bool
    let onEdit: (Outfit) -> Void
    let onMove: (Outfit) -> Void
    let onCreate: () -> Void

    @State private var anchor: AnyHashable?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(outfits, id: \.stableID) { outfit in
                    SuitcaseFeedCard(
                        outfit: outfit,
                        suitcase: suitcase,
                        store: store,
                        onEdit: { onEdit(outfit) },
                        onMove: { onMove(outfit) }
                    )
                    .matchedGeometryEffect(id: outfit.stableID, in: morph)
                    .modifier(PlanCardSize(page: pageSize))
                    .id(AnyHashable(outfit.stableID))
                }

                // Asomarse es crear, y no quedarse: en cuanto asoma, el scroll
                // vuelve al último outfit y el selector se abre encima. Ver
                // `PlanDayFeed`.
                PlanCreateCard(title: "Añadir un outfit")
                    .matchedGeometryEffect(id: createID, in: morph)
                    .modifier(PlanCardSize(page: pageSize))
                    .onScrollVisibilityChange(threshold: 0.4) { isVisible in
                        guard isVisible, !isPicking else { return }
                        guard let last = outfits.last else { return }
                        onCreate()
                        withAnimation(WKAnimation.content) {
                            anchor = AnyHashable(last.stableID)
                        }
                    }
                    .onTapGesture { onCreate() }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $anchor, anchor: .center)
        .scrollIndicators(.hidden)
        .onChange(of: isPicking) { _, isOpen in
            guard !isOpen, let last = outfits.last else { return }
            withAnimation(WKAnimation.content) { anchor = AnyHashable(last.stableID) }
        }
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
            // Con aire en las dos medidas: pegados al canto, en una celda de
            // rejilla el pulgar los roza al arrancar el scroll.
            .padding(isCompact ? WK.Spacing.s : WK.Spacing.m)
        }
        .contentShape(.rect)
        // Doble toque para editar, igual que en el plan y en el resto de
        // lienzos. Un toque simple no: compite con el scroll.
        .onTapGesture(count: 2, perform: onEdit)
        // Mantener pulsado, **solo en la revista**: en la rejilla esa
        // pulsación saca el menú. Ver `PlanFeedCard`.
        .modifier(LongPressToEdit(isOn: !isCompact, action: onEdit))
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

/// Mantener pulsado para editar, donde toca.
private struct LongPressToEdit: ViewModifier {
    let isOn: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if isOn {
            content.onLongPressGesture(perform: action)
        } else {
            content
        }
    }
}
