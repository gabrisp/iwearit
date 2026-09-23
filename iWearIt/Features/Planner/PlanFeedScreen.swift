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
            // **En la barra, no flotando.**
            //
            // Es la misma tira de siempre, pero puesta donde van las cosas de
            // la pantalla: así el sistema le da el mismo fondo, el mismo alto
            // y el mismo sitio que a cualquier otra barra, y el scroll de
            // debajo sabe que está ahí sin tener que descontarla a mano.
            //
            // Dos elementos hermanos y no una pieza con un botón pegado: el
            // calendario con los días es uno, el cambio de modo es el otro, y
            // los dos los pinta la barra igual.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DayStripCapsule(
                        anchorDay: anchor,
                        selectedOffset: selectedOffset,
                        onOpenCalendar: { isPickingDay = true },
                        hasBackground: false
                    )
                    // Los días necesitan ancho: sin decirlo, el scroll pide
                    // todo el que hay y echa al botón de al lado fuera de la
                    // barra. Con tope por arriba: un elemento que pide más de
                    // lo que la barra puede dar no se encoge, la barra lo
                    // esconde entero.
                    .frame(width: min(max(180, pageSize.width - Self.toolbarButtonSpace), 340))
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

    /// Qué día se mira, como desplazamiento desde hoy: es como habla la tira.
    private var selectedOffset: Binding<Int> {
        Binding(
            get: { offset(of: day ?? anchor) },
            set: { newValue in
                withAnimation(WKAnimation.content) { day = date(atOffset: newValue) }
            }
        )
    }

    /// Lo que se le deja al botón de la derecha, con su aire.
    private static let toolbarButtonSpace: CGFloat = 96

    /// **Lo que mide un hueco, descontando lo que tapan las barras.**
    ///
    /// Sin esto las tarjetas del plan salían más grandes que las de
    /// inspiración: allí el contenedor del scroll ya viene recortado por la
    /// barra de navegación y la de pestañas, y aquí la de arriba está
    /// escondida —manda la tira— así que hay que restarlas a mano.
    private var stride: CGFloat {
        // **Ya no se resta nada.** Con la tira dentro de la barra de
        // navegación, el contenedor del scroll llega recortado por arriba y
        // por abajo igual que en inspiración, que es de donde tiene que salir
        // el tamaño de las tarjetas.
        max(320, pageSize.height)
    }

    /// Hoy, que es desde donde se cuentan los días de la tira.
    private var anchor: Date { Calendar.current.startOfDay(for: Date()) }

    private func offset(of date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: anchor, to: date).day ?? 0
    }

    private func date(atOffset offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: anchor) ?? anchor
    }

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
        // Sin hueco a mano: la tira va en la barra y el área segura ya la
        // tiene en cuenta. El hueco que había aquí, con la barra puesta, se
        // sumaba al suyo y dejaba las tarjetas hundidas.
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
    }

    // MARK: Revista

    private func feed(of date: Date) -> some View {
        // **Cada día con su propio scroll.** El sitio donde está el scroll es
        // de ese día, no de la pantalla: con un solo estado compartido, el día
        // que se ve escribía la posición y los otros cuatro del pager
        // intentaban ir al mismo sitio —a una tarjeta que no es suya— y se
        // volvían al principio.
        PlanDayFeed(
            entries: entries(of: date),
            store: appEnvironment.imageStore,
            pageSize: pageSize,
            stride: stride,
            morph: morph,
            zoom: zoom,
            createID: Self.createID + date.description,
            isPicking: isPicking,
            isEditing: editingOutfit != nil,
            onEdit: { edit($0) },
            onMove: { movingOutfit = $0 },
            onCreate: { isPicking = true }
        )
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
                    // **El menú, solo en la rejilla.** Es donde se ven varios
                    // a la vez, que es justo cuando apetece reutilizar uno:
                    // copiarlo para variarlo, mandarlo a otro día. En revista
                    // solo ves uno y ahí manda el gesto de pasar. Ver
                    // `PlannerGrid`, que ya lo hacía así.
                    .contextMenu {
                        Button("Editar", systemImage: "pencil") { edit(entry.outfit) }
                        Button("Duplicar", systemImage: "plus.square.on.square") {
                            duplicate(entry.outfit)
                        }
                        Button("Mover a otro día", systemImage: "calendar") {
                            movingOutfit = entry.outfit
                        }
                        // Destructivo y el último: lo que borra va abajo y en
                        // rojo, para que el dedo no lo encuentre de camino a
                        // otra cosa.
                        Button("Eliminar", systemImage: "trash", role: .destructive) {
                            withAnimation(WKAnimation.content) { entry.outfit.markDeleted() }
                        }
                    }
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

    /// Copiar uno para variarlo sin perder el original. Se queda en el mismo
    /// día: duplicar es "otro parecido para hoy", y si era para otro día está
    /// mover al lado en el mismo menú.
    private func duplicate(_ outfit: Outfit) {
        let copy = Outfit(name: outfit.name)
        copy.backdropRaw = outfit.backdropRaw
        modelContext.insert(copy)
        copy.plannedDay = outfit.plannedDay

        for item in outfit.visibleItems {
            let clone = CanvasItem(transform: item.transform, garment: item.garment)
            if let sticker = item.sticker { clone.apply(sticker) }
            clone.isFlipped = item.isFlipped
            clone.outfit = copy
            modelContext.insert(clone)
        }
        try? modelContext.save()
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

    /// El papel de un outfit: el suyo, o el de la app si no tiene.
    static func backdrop(of outfit: Outfit) -> Color {
        guard
            let raw = outfit.backdropRaw,
            let components = OutfitBackdrop(rawValue: raw)?.components
        else { return WK.Palette.canvas }
        return WK.Palette.canvasTint(
            red: components.red,
            green: components.green,
            blue: components.blue
        )
    }

    static func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Hoy" }
        if calendar.isDateInTomorrow(date) { return "Mañana" }
        return date.formatted(.dateTime.weekday(.wide).day().month())
    }
}

/// Los outfits de un día, uno por pantalla.
///
/// Vista propia y no un trozo de `body` porque tiene algo que es **suyo**: por
/// dónde va su scroll. Cinco días viven a la vez en el pager y cada uno se
/// acuerda de por dónde iba.
private struct PlanDayFeed: View {
    let entries: [PlanFeedScreen.Entry]
    let store: ImageStore
    let pageSize: CGSize
    let stride: CGFloat
    let morph: Namespace.ID
    let zoom: Namespace.ID
    let createID: String
    /// Si el selector de prendas está puesto ahora mismo.
    let isPicking: Bool
    /// Si el editor está abierto encima.
    let isEditing: Bool
    let onEdit: (Outfit) -> Void
    let onMove: (Outfit) -> Void
    let onCreate: () -> Void

    @State private var anchor: AnyHashable?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    PlanFeedCard(
                        entry: entry,
                        store: store,
                        onEdit: { onEdit(entry.outfit) },
                        onMove: { onMove(entry.outfit) }
                    )
                    .matchedGeometryEffect(id: entry.id, in: morph)
                    .adaptiveZoomSource(id: AnyHashable(entry.id), in: zoom)
                    .modifier(PlanCardSize(page: pageSize, stride: stride))
                    .id(AnyHashable(entry.id))
                }

                // **Asomarse ya es entrar.** Nadie quiere quedarse mirando una
                // tarjeta que dice "crear": subir hasta ella *es* la decisión,
                // así que en cuanto asoma de verdad se abre el selector. Es el
                // mismo gesto que trae más propuestas en inspiración.
                PlanCreateCard()
                    .matchedGeometryEffect(id: createID, in: morph)
                    .modifier(PlanCardSize(page: pageSize, stride: stride))
                    // **Solo si había algo antes.** Con el día vacío, esta
                    // tarjeta es lo único en pantalla: dispararse al verse
                    // sería abrir el selector nada más llegar al día. Con
                    // outfits detrás, llegar hasta aquí es un tirón hacia
                    // arriba —una decisión— y entonces sí.
                    .onScrollVisibilityChange(threshold: 0.55) { isVisible in
                        guard isVisible, !isPicking, !isEditing else { return }
                        guard !entries.isEmpty else { return }
                        onCreate()
                    }
                    .onTapGesture { onCreate() }
                    .id(Self.createAnchor)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $anchor, anchor: .center)
        .scrollIndicators(.hidden)
        // **De la tarjeta de crear no te quedas colgado.**
        //
        // Es un botón, no un sitio: al cerrarse el selector la vista vuelve al
        // último outfit, así que nunca te quedas parado delante de una tarjeta
        // que ya hizo lo suyo. Solo se puede estar ahí cuando el día está
        // vacío, porque entonces no hay otro sitio al que volver.
        .onChange(of: isPicking) { _, isOpen in
            guard !isOpen, let last = entries.last else { return }
            withAnimation(WKAnimation.content) { anchor = AnyHashable(last.id) }
        }
    }

    /// La identidad de la tarjeta de crear dentro del scroll. Constante: el
    /// scroll solo necesita distinguirla de los outfits.
    private static let createAnchor = AnyHashable("plan.create.anchor")
}

/// Lo que mide una tarjeta del plan: una pantalla, con su aire dentro.
///
/// El mismo reparto que la inspiración —once doceavas partes— para que el
/// enganche del scroll y el centro de la pantalla sean el mismo punto. Ver
/// `InspoCardSize`.
struct PlanCardSize: ViewModifier {
    let page: CGSize
    /// Lo que mide un hueco. Si no se dice, el del contenedor.
    var stride: CGFloat?

    func body(content: Content) -> some View {
        content
            .padding(.vertical, max(WK.Spacing.xs, (stride ?? page.height) / 24))
            .frame(height: stride)
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
        // **Sin píldora de fecha.** El día ya está arriba, en la tira, y
        // repetirlo dentro de cada lienzo es decir dos veces lo mismo tapando
        // la ropa.
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
        .contentShape(.rect)
        // Doble toque para entrar a editar, como en cualquier otro lienzo.
        .onTapGesture(count: 2, perform: onEdit)
        // **Y aquí sí, mantener pulsado.** En la revista se ve un solo lienzo
        // y no hay menú que sacar, así que la pulsación larga queda libre para
        // lo único que se hace con el que tienes delante: abrirlo. En la
        // rejilla no, porque ahí saca el menú.
        .onLongPressGesture(perform: onEdit)
    }

    private var backdrop: Color { PlanFeedScreen.backdrop(of: entry.outfit) }
}

/// El mismo outfit, en la rejilla.
private struct PlanGridCell: View {
    let entry: PlanFeedScreen.Entry
    let store: ImageStore
    let onEdit: () -> Void
    let onMove: () -> Void

    var body: some View {
        // **El mismo lienzo que a pantalla completa.** Con su papel: el color
        // es del outfit, no del tamaño con el que se mire, y en la rejilla
        // salían todos grises mientras en grande cada uno tenía el suyo.
        LookCanvasView(
            garments: entry.outfit.garments,
            store: store,
            backdrop: PlanFeedScreen.backdrop(of: entry.outfit),
            outfit: entry.outfit,
            showsBorder: true
        )
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
            // Separados del canto, como en grande: pegados al borde se leen
            // como si se salieran de la tarjeta, y en una celda pequeña el
            // pulgar los rozaba al pasar.
            .padding(WK.Spacing.s)
        }
        .contentShape(.rect)
        // El mismo doble toque que en grande. Un toque simple no: en una
        // rejilla se toca sin querer al arrancar el scroll.
        .onTapGesture(count: 2, perform: onEdit)
    }
}

/// Crear uno nuevo. **La misma tarjeta** al final de la revista y al final de
/// la rejilla: no son dos botones que hacen lo mismo, es uno que está donde
/// acaba lo que hay.
struct PlanCreateCard: View {
    var title = "Crear un outfit"

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
                    Text(title)
                        .font(WK.Font.headline)
                        .foregroundStyle(WK.Palette.secondaryText)
                }
            }
            .aspectRatio(CanvasSpace.width / CanvasSpace.height, contentMode: .fit)
    }
}
