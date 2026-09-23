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

    /// Lo planeado de hoy en adelante, en orden.
    ///
    /// Lo de ayer no se enseña: el plan es lo que viene. Lo que ya pasó está en
    /// el armario, en el recuento de veces que te lo has puesto.
    private var entries: [Entry] {
        let today = Calendar.current.startOfDay(for: Date())
        return days
            .filter { $0.dayStart >= today }
            .flatMap { day in
                day.orderedOutfits
                    .filter { !$0.garments.isEmpty }
                    .map { Entry(outfit: $0, day: day.dayStart) }
            }
    }

    struct Entry: Identifiable {
        let outfit: Outfit
        let day: Date
        var id: UUID { outfit.stableID }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch layout {
                case .feed: feed
                case .grid: grid
                }
            }
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
            .animation(WKAnimation.content, value: layout)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
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

    /// Qué día se está mirando, arriba. En rejilla, cuántos hay.
    private var title: String {
        guard layout == .feed else {
            return entries.count == 1 ? "1 outfit" : "\(entries.count) outfits"
        }
        guard
            let id = scrolled as? UUID,
            let entry = entries.first(where: { $0.id == id })
        else { return "Plan" }
        return Self.dayLabel(for: entry.day)
    }

    // MARK: Revista

    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
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

                PlanCreateCard()
                    .matchedGeometryEffect(id: Self.createID, in: morph)
                    .modifier(PlanCardSize(page: pageSize))
                    .id(AnyHashable(Self.createID))
                    .onTapGesture { isPicking = true }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolled, anchor: .center)
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
    }

    // MARK: Rejilla

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: WK.Spacing.m)],
                spacing: WK.Spacing.m
            ) {
                ForEach(entries) { entry in
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
                    .matchedGeometryEffect(id: Self.createID, in: morph)
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
        let target = (scrolled as? UUID)
            .flatMap { id in entries.first { $0.id == id }?.day }
            ?? Calendar.current.startOfDay(for: Date())
        move(outfit, to: target)

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
