import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// El plan, **como la inspiración**: un lienzo por pantalla y a subir.
///
/// ## Por qué se parece a inspiración y no al librito
///
/// Porque mirar lo que tienes planeado es el mismo gesto que mirar lo que te
/// proponen: pasar, mirar, decidir. El librito de páginas por día contaba otra
/// cosa —un calendario que se hojea— y obligaba a dos navegaciones a la vez:
/// de lado para cambiar de día y hacia arriba para ver los outfits de ese día.
/// Aquí hay una sola: subes, y lo que viene es lo siguiente que te vas a
/// poner, con su día escrito encima.
///
/// **Un día cada vez, y de lado se cambia de día.** Arriba y abajo, los outfits
/// de ese día; a izquierda y derecha, los días — que es lo que ya hacía la
/// rejilla y lo que espera cualquiera delante de un calendario. Y para irse
/// lejos, el calendario de siempre en la barra: pasar veinte días de uno en uno
/// no es navegar, es remar.
///
/// Y al final de la fila, la tarjeta de crear — la misma que remata la rejilla,
/// con la misma identidad, así que al cambiar de modo viaja a su sitio en vez
/// de aparecer de la nada.
///
/// - Note: la pantalla vieja (`PlannerScreen`) **no se ha borrado**. Es la que
///   sabe de paso de página con curl, tira de días y rejilla por día; si esto
///   no cuaja, volver es cambiar una línea en `RootTabView`.
struct PlanFeedScreen: View {
    @Binding var tab: RootTab

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(sort: \PlannedDay.dayStart) private var days: [PlannedDay]

    /// Qué día se está mirando. Lo escribe el scroll de lado y lo puede
    /// cambiar el calendario.
    @State private var day: Date? = Calendar.current.startOfDay(for: Date())
    @State private var isPickingDay = false
    @State private var layout: Layout = .feed
    @State private var scrolled: AnyHashable?
    @State private var pageSize: CGSize = .zero
    @State private var editingOutfit: Outfit?
    @State private var editingIsNew = false
    @State private var movingOutfit: Outfit?
    @State private var isPicking = false

    /// Para que cada lienzo viaje a su sitio al cambiar de modo.
    @Namespace private var morph
    /// Para que el editor crezca desde la tarjeta que se abre.
    @Namespace private var zoom

    enum Layout { case feed, grid }

    /// La identidad de la tarjeta de crear. La misma en los dos modos: es lo
    /// que hace que sea **la misma tarjeta** y no dos parecidas.
    private static let createID = "plan.create"

    /// Lo planeado para un día.
    private func entries(of date: Date) -> [Entry] {
        days
            .first { $0.dayStart == date }?
            .orderedOutfits
            .filter { !$0.garments.isEmpty }
            .map { Entry(outfit: $0, day: date) }
            ?? []
    }

    /// Los días por los que se puede pasar de lado.
    ///
    /// Una semana hacia atrás y tres meses hacia delante: lo de ayer se mira
    /// alguna vez —"¿qué me puse?"— y lo de dentro de cuatro meses no lo
    /// planea nadie. Para salirse de ahí está el calendario, que no tiene
    /// límites.
    private var window: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (-7...90).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    struct Entry: Identifiable {
        let outfit: Outfit
        let day: Date
        var id: UUID { outfit.stableID }
    }

    var body: some View {
        NavigationStack {
            pager
            .background(WK.Palette.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .rootTabBar(.planner, selection: $tab, onAssistant: nil)
            .navigationDestination(item: $editingOutfit) { outfit in
                AdvancedCanvasScreen(
                    outfit: outfit,
                    store: appEnvironment.imageStore,
                    isNew: editingIsNew
                )
                .adaptiveZoomDestination(id: AnyHashable(outfit.stableID), in: zoom)
            }
            .sheet(item: $movingOutfit) { outfit in
                StylistDayPicker { date in
                    move(outfit, to: date)
                    movingOutfit = nil
                }
            }
            .sheet(isPresented: $isPicking) {
                OutfitPickerSheet(store: appEnvironment.imageStore) { picked in
                    guard !picked.isEmpty else { return }
                    create(with: picked)
                }
            }
            // El calendario de siempre, ahora desde la barra. Ver
            // `CalendarJumpSheet`.
            .sheet(isPresented: $isPickingDay) {
                CalendarJumpSheet(
                    selection: Binding(
                        get: { day ?? Calendar.current.startOfDay(for: Date()) },
                        set: { picked in
                            // Escribir el ancla del scroll **es** ir a ese día:
                            // la lista de días ya existe, así que se desliza
                            // hasta él en vez de recargar nada.
                            withAnimation(WKAnimation.content) {
                                day = Calendar.current.startOfDay(for: picked)
                            }
                        }
                    )
                )
            }
            .animation(WKAnimation.content, value: layout)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // **El calendario, arriba a la izquierda.** Es lo que cambia de día, y
        // como tira ocupaba una franja entera de pantalla para enseñar siete
        // días de los que se usan dos.
        ToolbarItem(placement: .topBarLeading) {
            Button { isPickingDay = true } label: {
                Image(systemName: "calendar")
            }
            .tint(WK.Palette.primaryText)
        }
        ToolbarItem(placement: .principal) {
            Text(title)
                .font(WK.Font.callout)
                .foregroundStyle(WK.Palette.primaryText)
                .fixedSize()
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(WKAnimation.content) {
                    layout = layout == .feed ? .grid : .feed
                }
            } label: {
                Image(systemName: layout == .feed ? "square.grid.2x2" : "rectangle.portrait")
                    .contentTransition(.symbolEffect(.replace.downUp))
            }
            .tint(WK.Palette.primaryText)
        }
    }

    /// El día que se está mirando.
    private var title: String { Self.dayLabel(for: day ?? Date()) }

    // MARK: Los días, de lado

    /// **De lado se cambia de día.**
    ///
    /// Un `ScrollView` horizontal con paginado y no el pager de UIKit del
    /// planificador viejo: aquí dentro va otro scroll —el de los outfits del
    /// día— y anidar el de SwiftUI dentro del de UIKit era pelearse por el
    /// dedo en cada gesto diagonal.
    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(window, id: \.self) { date in
                    Group {
                        switch layout {
                        case .feed: feed(of: date)
                        case .grid: grid(of: date)
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(date)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $day)
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
    }

    // MARK: Revista

    private func feed(of date: Date) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(entries(of: date)) { entry in
                    PlanFeedCard(
                        entry: entry,
                        store: appEnvironment.imageStore,
                        onEdit: { edit(entry.outfit) },
                        onMove: { movingOutfit = entry.outfit }
                    )
                    .matchedGeometryEffect(id: entry.id, in: morph)
                    .adaptiveZoomSource(id: AnyHashable(entry.id), in: zoom)
                    .modifier(PlanCardSize(page: pageSize))
                    .id(AnyHashable(entry.id))
                }

                // **Asomarse ya es entrar.** Nadie quiere quedarse mirando una
                // tarjeta que dice "crear": subir hasta ella *es* la decisión,
                // así que en cuanto asoma de verdad se abre el selector. Es el
                // mismo gesto que trae más propuestas en inspiración.
                PlanCreateCard()
                    .matchedGeometryEffect(id: Self.createID + date.description, in: morph)
                    .modifier(PlanCardSize(page: pageSize))
                    .onScrollVisibilityChange(threshold: 0.55) { isVisible in
                        guard isVisible, !isPicking, editingOutfit == nil else { return }
                        isPicking = true
                    }
                    .onTapGesture { isPicking = true }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    // MARK: Rejilla

    private func grid(of date: Date) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: WK.Spacing.m)],
                spacing: WK.Spacing.m
            ) {
                ForEach(entries(of: date)) { entry in
                    PlanGridCell(
                        entry: entry,
                        store: appEnvironment.imageStore,
                        onEdit: { edit(entry.outfit) },
                        onMove: { movingOutfit = entry.outfit }
                    )
                    .matchedGeometryEffect(id: entry.id, in: morph)
                    .adaptiveZoomSource(id: AnyHashable(entry.id), in: zoom)
                }

                // **La misma tarjeta de crear**, con la misma identidad: al
                // cambiar de modo no aparece una nueva, viaja la que ya había.
                PlanCreateCard()
                    .matchedGeometryEffect(id: Self.createID + date.description, in: morph)
                    .aspectRatio(CanvasSpace.width / CanvasSpace.height, contentMode: .fit)
                    .onTapGesture { isPicking = true }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WKTabBarMetrics.clearance)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Acciones

    private func edit(_ outfit: Outfit, isNew: Bool = false) {
        editingIsNew = isNew
        editingOutfit = outfit
    }

    /// Mover es cambiarle el día, que es lo único que se hace con un outfit ya
    /// planeado y no cabía en ningún sitio: antes había que abrirlo, borrarlo
    /// del día y volver a crearlo en el otro.
    private func move(_ outfit: Outfit, to date: Date) {
        let dayStart = Calendar.current.startOfDay(for: date)
        let existing = try? modelContext.fetch(
            FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.dayStart == dayStart })
        )
        let day = existing?.first ?? {
            let new = PlannedDay(dayStart: dayStart)
            modelContext.insert(new)
            return new
        }()
        outfit.plannedDay = day
        try? modelContext.save()
        DiagnosticsLog.record("PLAN", "outfit movido a \(Self.dayLabel(for: dayStart))")
    }

    /// Crear cuelga del día que estés mirando, y de hoy si no hay ninguno.
    private func create(with garments: [Garment]) {
        let outfit = Outfit()
        modelContext.insert(outfit)
        // Al día que se está mirando: es el que tienes delante.
        move(outfit, to: day ?? Date())

        for garment in garments {
            let slot = OutfitSlot.slot(for: garment.kind)
            let item = CanvasItem(transform: slot.transform, garment: garment)
            item.outfit = outfit
            modelContext.insert(item)
        }
        try? modelContext.save()
        edit(outfit, isNew: true)
    }

    static func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Hoy" }
        if calendar.isDateInTomorrow(date) { return "Mañana" }
        return date.formatted(.dateTime.weekday(.wide).day().month())
    }
}

/// Lo que mide una tarjeta del plan: una pantalla, con su aire dentro.
///
/// El mismo reparto que la inspiración —once doceavas partes— para que el
/// enganche del scroll y el centro de la pantalla sean el mismo punto. Ver
/// `InspoCardSize`.
private struct PlanCardSize: ViewModifier {
    let page: CGSize

    func body(content: Content) -> some View {
        content
            .padding(.vertical, max(WK.Spacing.xs, page.height / 24))
            .containerRelativeFrame(.vertical)
            .scrollTransition(.interactive, axis: .vertical) { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : 0.35)
                    .scaleEffect(phase.isIdentity ? 1 : 0.88)
            }
    }
}

/// Un outfit planeado, a pantalla completa.
///
/// Dos acciones y ninguna más: **el lápiz** para abrirlo y **mover** para
/// cambiarle el día. Ni corazón ni calendario — aquí ya está planeado, así que
/// ponerle fecha no significa nada, y el corazón es del armario.
private struct PlanFeedCard: View {
    let entry: PlanFeedScreen.Entry
    let store: ImageStore
    let onEdit: () -> Void
    let onMove: () -> Void

    var body: some View {
        LookCanvasView(
            garments: entry.outfit.garments,
            store: store,
            backdrop: backdrop,
            outfit: entry.outfit,
            showsBorder: true
        )
        .overlay(alignment: .topLeading) {
            Text(PlanFeedScreen.dayLabel(for: entry.day))
                .font(WK.Font.caption.weight(.medium))
                .foregroundStyle(WK.Palette.secondaryText)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.xs)
                .adaptiveGlass(in: .capsule)
                .padding(WK.Spacing.m)
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: WK.Spacing.xs) {
                WKCircleButton("pencil", size: .compact, action: onEdit)
                    .tint(WK.Palette.primaryText)
                WKCircleButton(
                    "arrow.up.and.down.and.arrow.left.and.right",
                    size: .compact,
                    action: onMove
                )
                .tint(WK.Palette.primaryText)
            }
            .padding(WK.Spacing.m)
        }
    }

    private var backdrop: Color {
        guard
            let raw = entry.outfit.backdropRaw,
            let components = OutfitBackdrop(rawValue: raw)?.components
        else { return WK.Palette.canvas }
        return WK.Palette.canvasTint(
            red: components.red,
            green: components.green,
            blue: components.blue
        )
    }
}

/// El mismo outfit, en la rejilla.
private struct PlanGridCell: View {
    let entry: PlanFeedScreen.Entry
    let store: ImageStore
    let onEdit: () -> Void
    let onMove: () -> Void

    var body: some View {
        LookCanvasView(
            garments: entry.outfit.garments,
            store: store,
            outfit: entry.outfit,
            showsBorder: true
        )
        .overlay(alignment: .bottomLeading) {
            Text(PlanFeedScreen.dayLabel(for: entry.day))
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
                .padding(WK.Spacing.s)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: WK.Spacing.xs) {
                WKCircleButton("pencil", size: .compact, action: onEdit)
                    .tint(WK.Palette.primaryText)
                WKCircleButton(
                    "arrow.up.and.down.and.arrow.left.and.right",
                    size: .compact,
                    action: onMove
                )
                .tint(WK.Palette.primaryText)
            }
            .padding(WK.Spacing.xs)
        }
    }
}

/// Crear uno nuevo. **La misma tarjeta** al final de la revista y al final de
/// la rejilla: no son dos botones que hacen lo mismo, es uno que está donde
/// acaba lo que hay.
private struct PlanCreateCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
            .fill(WK.Palette.ink(0.03))
            .overlay {
                RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
                    .stroke(WK.Palette.ink(0.12), style: StrokeStyle(lineWidth: 1, dash: [8, 6]))
            }
            .overlay {
                VStack(spacing: WK.Spacing.s) {
                    Image(systemName: "plus")
                        .font(.system(size: 26))
                        .foregroundStyle(WK.Palette.secondaryText)
                    Text("Crear un outfit")
                        .font(WK.Font.headline)
                        .foregroundStyle(WK.Palette.secondaryText)
                }
            }
            .aspectRatio(CanvasSpace.width / CanvasSpace.height, contentMode: .fit)
    }
}
