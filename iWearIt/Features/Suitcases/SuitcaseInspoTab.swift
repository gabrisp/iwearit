import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// Inspiración **con lo que te llevas**.
///
/// ## Por qué aquí y no la de siempre
///
/// Porque en un viaje la pregunta es otra. En casa tienes el armario entero y
/// lo que falta es decidir; en la maleta ya has decidido —metes ocho prendas—
/// y lo que falta es sacarles partido: cuántos conjuntos distintos salen de
/// eso, y si con una camisa más salen cuatro más.
///
/// Así que el estilista trabaja **solo con lo que hay en el equipaje**, y
/// ponerle fecha a un conjunto es ponerlo en un día del viaje, no en el
/// calendario de casa. El corazón sí guarda fuera: un conjunto que te gusta te
/// gusta también cuando vuelves.
struct SuitcaseInspoTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    let suitcase: Suitcase
    /// Cuánto hay que dejar libre arriba y abajo: lo pone la pantalla, que es
    /// la que sabe dónde está la barra de la maleta.
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    @Query(FetchDescriptor<Garment>.visibleGarments())
    private var garments: [Garment]

    @State private var feed: InspoFeed?
    @State private var swipe = InspoSwipe()
    @State private var saved: Set<UUID> = []
    @State private var datingLook: StylistLook?
    @State private var editingOutfit: Outfit?
    @State private var scrolled: UUID?
    @State private var pageHeight: CGFloat = 0

    /// Lo que va en la maleta: las prendas del equipaje y las que ya están
    /// puestas en algún conjunto del viaje.
    private var packed: Set<UUID> {
        var ids = Set(suitcase.packingEntries.compactMap(\.garment?.id))
        for outfit in suitcase.visibleOutfits {
            for garment in outfit.garments { ids.insert(garment.id) }
        }
        return ids
    }

    private var byID: [UUID: Garment] {
        Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var looks: [StylistLook] { feed?.looks ?? [] }

    var body: some View {
        Group {
            if packed.count < 3 {
                SuitcaseInspoEmpty(count: packed.count)
            } else if looks.isEmpty {
                ProgressView()
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: packed) { await prepare() }
        .sheet(item: $datingLook) { look in
            SuitcaseDayPicker(suitcase: suitcase) { dayIndex in
                plan(look, on: dayIndex)
                datingLook = nil
            }
        }
        .navigationDestination(item: $editingOutfit) { outfit in
            AdvancedCanvasScreen(outfit: outfit, store: appEnvironment.imageStore, isNew: true)
        }
    }

    private var list: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: WK.Spacing.m) {
                ForEach(looks) { look in
                    InspoLookCard(
                        look: look,
                        garments: look.garmentIDs.compactMap { byID[$0] },
                        outfit: nil,
                        store: appEnvironment.imageStore,
                        backdrop: InspoPalette.backdrop(for: look),
                        isSaved: saved.contains(look.id),
                        onSave: { save(look) },
                        onPlan: { datingLook = look },
                        onRegenerate: { regenerate(look) },
                        onEdit: { edit(look) },
                        onDismiss: { withAnimation(WKAnimation.content) { feed?.dismiss(look) } },
                        onDislike: { withAnimation(WKAnimation.content) { feed?.dislike(look) } },
                        swipe: swipe
                    )
                    .containerRelativeFrame(.vertical, count: 12, span: 11, spacing: WK.Spacing.m)
                    .scrollTransition(.interactive, axis: .vertical) { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.35)
                            .scaleEffect(phase.isIdentity ? 1 : 0.88)
                    }
                }
            }
            .padding(.vertical, pageHeight / 24)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolled)
        .scrollIndicators(.hidden)
        .overlay { InspoVerdictPill(swipe: swipe) }
        .safeAreaPadding(.top, topInset)
        .safeAreaPadding(.bottom, bottomInset)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
    }

    // MARK: Acciones

    /// Monta el feed la primera vez y lo rehace si cambia lo que llevas.
    private func prepare() async {
        let made = feed ?? InspoFeed(
            container: appEnvironment.container,
            weather: appEnvironment.weather
        )
        made.restrictedTo = packed
        if feed == nil {
            feed = made
            await made.loadWeather()
            made.start()
        } else {
            made.shuffle()
        }
    }

    /// El corazón guarda **fuera**: es tuyo, no del viaje.
    private func save(_ look: StylistLook) {
        guard let outfit = materialise(look, isFavorite: true, inTrip: false) else { return }
        _ = outfit
        try? modelContext.save()
        saved.insert(look.id)
    }

    /// Y la fecha es un día **de este viaje**.
    private func plan(_ look: StylistLook, on dayIndex: Int) {
        guard let outfit = materialise(look, isFavorite: false, inTrip: true) else { return }
        outfit.suitcaseDayIndex = dayIndex
        try? modelContext.save()
        saved.insert(look.id)
    }

    private func edit(_ look: StylistLook) {
        guard let outfit = materialise(look, isFavorite: false, inTrip: true) else { return }
        try? modelContext.save()
        editingOutfit = outfit
    }

    private func regenerate(_ look: StylistLook) {
        guard
            let feed,
            let replacement = feed.replacement(
                for: look, excluding: Set(looks.flatMap(\.garmentIDs))
            )
        else { return }
        withAnimation(WKAnimation.content) { feed.replace(look, with: replacement) }
    }

    private func materialise(_ look: StylistLook, isFavorite: Bool, inTrip: Bool) -> Outfit? {
        let pieces = look.garmentIDs.compactMap { byID[$0] }
        guard !pieces.isEmpty else { return nil }
        let outfit = OutfitAssembly.make(
            from: pieces,
            name: look.headline,
            origin: .inspo,
            isFavorite: isFavorite,
            backdropRaw: InspoPalette.backdrop(for: look).rawValue,
            context: modelContext,
            seed: InspoPalette.seed(for: look)
        )
        if inTrip { outfit.suitcase = suitcase }
        return outfit
    }
}

/// Qué día del viaje.
///
/// Días del viaje y no un calendario: dentro de una maleta, "el 25" no
/// significa nada hasta que sabes que es el tercer día. Con fechas puestas se
/// enseñan las dos cosas.
private struct SuitcaseDayPicker: View {
    let suitcase: Suitcase
    let onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<max(1, suitcase.tripDayCount ?? 3), id: \.self) { index in
                    Button {
                        onPick(index)
                        dismiss()
                    } label: {
                        HStack {
                            Text("Día \(index + 1)")
                                .foregroundStyle(WK.Palette.primaryText)
                            Spacer()
                            if let date = suitcase.date(forDayIndex: index) {
                                Text(date.formatted(.dateTime.weekday(.abbreviated).day().month()))
                                    .font(WK.Font.caption)
                                    .foregroundStyle(WK.Palette.secondaryText)
                            }
                        }
                    }
                }
            }
            // Sin fechas, la maleta no tiene días: se ofrecen tres huecos,
            // que es lo que hace la propia maleta con los outfits preparados.
            .navigationTitle("¿Qué día?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(WK.Palette.primaryText)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct SuitcaseInspoEmpty: View {
    let count: Int

    var body: some View {
        ContentUnavailableView {
            Label("Todavía no hay con qué", systemImage: "suitcase")
        } description: {
            Text(
                count == 0
                    ? "Mete ropa en el equipaje y aquí verás qué conjuntos salen con ella."
                    : "Con \(count) prendas no salen conjuntos distintos. Mete alguna más."
            )
        }
    }
}
