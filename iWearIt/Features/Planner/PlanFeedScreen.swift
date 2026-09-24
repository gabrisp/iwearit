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
    @State private var layout: Layout = .feed
    @State private var scrolled: AnyHashable?
    @State private var pageSize: CGSize = .zero
    @State private var editingOutfit: Outfit?
    @State private var editingIsNew = false
    /// **Una sola hoja, como en inspiración.** Con un `.sheet` por cada cosa
    /// —mover, elegir prendas, el calendario, probarse— SwiftUI atiende a una
    /// y deja mudas las demás. Ver `AppRouter.Sheet`.
    @State private var sheet: Sheet?

    enum Sheet: Identifiable {
        /// A qué día se lleva.
        case move(Outfit)
        /// Qué prendas lleva el nuevo.
        case picker
        /// Salto a una fecha.
        case day
        /// Cómo te queda puesto.
        case tryOn(Outfit)

        var id: String {
            switch self {
            case let .move(outfit): "move-\(outfit.stableID)"
            case .picker: "picker"
            case .day: "day"
            case let .tryOn(outfit): "tryon-\(outfit.stableID)"
            }
        }
    }

    /// Cuál está a punto de irse, esperando el sí.
    @State private var deleting: Outfit?

    /// Para que cada lienzo viaje a su sitio al cambiar de modo.
    @Namespace private var morph
    /// Para que el editor crezca desde la tarjeta que se abre.
    @Namespace private var zoom
    /// Para que los botones de la tarjeta y el menú de la rejilla sean el
    /// mismo cristal.
    @Namespace private var glass

    enum Layout { case feed, grid }

    /// La identidad de la tarjeta de crear. La misma en los dos modos: es lo
    /// que hace que sea **la misma tarjeta** y no dos parecidas.
    private static let createID = "plan.create"

    /// De dónde crece el editor cuando el outfit **acaba de nacer**.
    ///
    /// Un `UUID` y no una cadena: el id de una transición de zoom se guarda
    /// **con su tipo**, así que origen y destino tienen que ser el mismo tipo
    /// para encontrarse. Con un `AnyHashable` envolviendo una cadena en un
    /// lado y un `UUID` en el otro, la transición no emparejaba nada y la
    /// pantalla entraba de lado.
    private static let newOutfitZoomID = UUID()

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
            // **En una barra de área segura, no en la de navegación.**
            //
            // Estuvo en la barra de navegación un rato: la pinta el sistema,
            // con su fondo y su alto, y era lo lógico. Pero una barra de
            // navegación reparte el ancho como quiere, y cuando lo que pide un
            // elemento no cabe no lo encoge: lo esconde entero. Con una tira
            // de días —que es lo más ancho que hay en la pantalla— eso
            // significa que en una ventana estrecha el calendario desaparece,
            // y un control que a veces no está es peor que uno que ocupa.
            //
            // Aquí manda ella: la tira es la de siempre, con su cápsula y su
            // botón al lado, y la barra le reserva el sitio —así el scroll de
            // debajo sabe lo que tiene encima sin que nadie lo cuente a mano.
            // **En la barra de navegación, y midiendo lo que cabe.**
            //
            // La primera vez que estuvo aquí desaparecía en ventanas
            // estrechas: la barra de iOS 26 no encoge lo que no cabe — lo de
            // los lados lo mete en un menú "…" y lo del centro lo recorta — y
            // la tira pedía un ancho sacado del pager, que no es el de la
            // barra. Ahora la tira va en el **centro** —que nunca acaba en el
            // menú "…"— con el ancho que de verdad queda entre los botones de
            // los lados, y el cambio de modo es un solo botón a la derecha,
            // que siempre cabe. Es la misma forma que la maleta.
            //
            // Lo de antes, flotando en una barra de área segura:
            // .toolbarVisibility(.hidden, for: .navigationBar)
            // .adaptiveSafeAreaBar(edge: .top, spacing: 0) { strip }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    DayStripCapsule(
                        anchorDay: anchor,
                        selectedOffset: selectedOffset,
                        onOpenCalendar: { sheet = .day },
                        isInBar: true
                    )
                    // Se reserva el mismo hueco a los dos lados aunque a la
                    // izquierda no haya nada: así la tira queda centrada.
                    .frame(width: WKTabBarMetrics.principalWidth(sideButtons: 1))
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
                // **El id tiene que existir en pantalla.**
                //
                // Un outfit recién creado no tiene tarjeta todavía —se crea y
                // se entra a editarlo en el mismo turno—, así que el zoom
                // buscaba un origen que no estaba y la pantalla entraba de
                // lado, como un empujón cualquiera. Para ese caso el origen es
                // la pantalla, que sí está. Ver `SuitcaseDetailScreen`, que ya
                // lo resolvía así.
                .adaptiveZoomDestination(
                    id: editingIsNew ? Self.newOutfitZoomID : outfit.stableID,
                    in: zoom
                )
            }
            .sheet(item: $sheet) { which in
                switch which {
                case let .move(outfit):
                    StylistDayPicker { date in
                        move(outfit, to: date)
                        sheet = nil
                    }
                case .picker:
                    OutfitPickerSheet(store: appEnvironment.imageStore) { picked in
                        guard !picked.isEmpty else { return }
                        create(with: picked)
                    }
                case .day:
                    dayJump
                case let .tryOn(outfit):
                    // **Probarse desde el plan y no solo desde el editor.**
                    // Lo que tienes planeado para el jueves es justo lo que
                    // quieres verte puesto, y entrar a editarlo para eso era
                    // pasar por una pantalla de trabajo para mirar.
                    TryOnSheet(outfit: outfit)
                        .presentationBackground(WK.Palette.canvas)
                }
            }
            // Quitar un outfit del plan **pregunta**: es trabajo de colocar
            // prendas, y al lado del lápiz un resbalón lo tiraría entero.
            .alert(
                "¿Quitar este outfit?",
                isPresented: Binding(
                    get: { deleting != nil },
                    set: { if !$0 { deleting = nil } }
                ),
                presenting: deleting
            ) { outfit in
                Button("Quitar", role: .destructive) {
                    withAnimation(WKAnimation.content) { outfit.markDeleted() }
                    deleting = nil
                }
                Button("Cancelar", role: .cancel) { deleting = nil }
            } message: { _ in
                Text("Las prendas siguen en tu armario.")
            }
            .animation(WKAnimation.content, value: layout)
        }
    }

    /// El calendario de siempre. Ver `CalendarJumpSheet`.
    private var dayJump: some View {
        CalendarJumpSheet(
            selection: Binding(
                get: { day ?? Calendar.current.startOfDay(for: Date()) },
                set: { picked in
                    // Escribir el ancla del scroll **es** ir a ese día: la
                    // lista de días ya existe, así que se desliza hasta él en
                    // vez de recargar nada.
                    withAnimation(WKAnimation.content) {
                        day = Calendar.current.startOfDay(for: picked)
                    }
                }
            )
        )
    }

    /// La tira: el calendario, los días y el cambio de modo. La misma que
    /// llevaba el plan desde siempre, con su cápsula de cristal flotando sobre
    /// el lienzo. Ver `DayStripBar`.
    private var strip: some View {
        DayStripBar(
            anchorDay: anchor,
            selectedOffset: selectedOffset,
            onOpenCalendar: { sheet = .day },
            layoutSymbol: layout == .feed ? "square.grid.2x2" : "rectangle.portrait",
            onToggleLayout: {
                withAnimation(WKAnimation.content) {
                    layout = layout == .feed ? .grid : .feed
                }
            }
        )
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

    /// Lo que mide la tira con su aire. Ver `DayStripBar`.
    private static let stripHeight: CGFloat = 64

    /// **Lo que mide un hueco, descontando lo que tapan las barras.**
    ///
    /// Sin esto las tarjetas del plan salían más grandes que las de
    /// inspiración: allí el contenedor del scroll ya viene recortado por la
    /// barra de navegación y la de pestañas, y aquí la de arriba está
    /// escondida —manda la tira— así que hay que restarlas a mano.
    private var stride: CGFloat {
        // **Sin restar nada.** La barra de área segura encoge el marco del
        // scroll igual que lo hace la de pestañas, así que lo que se mide aquí
        // ya viene sin la tira. Restándola otra vez las tarjetas salían un
        // dedo más cortas que las de inspiración —medido en el simulador: 572
        // puntos contra 635—.
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
            day: date,
            store: appEnvironment.imageStore,
            pageSize: pageSize,
            stride: stride,
            morph: morph,
            zoom: zoom,
            createID: Self.createID + date.description,
            glass: glass,
            newOutfitID: Self.newOutfitZoomID,
            isPicking: sheet != nil,
            isEditing: editingOutfit != nil,
            onEdit: { edit($0) },
            onMove: { sheet = .move($0) },
            onTryOn: { sheet = .tryOn($0) },
            onDelete: { deleting = $0 },
            onCreate: { sheet = .picker }
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
                        glass: glass,
                        onEdit: { edit(entry.outfit) },
                        onMove: { sheet = .move(entry.outfit) },
                        onDuplicate: { duplicate(entry.outfit) },
                        onTryOn: { sheet = .tryOn(entry.outfit) },
                        onDelete: { deleting = entry.outfit }
                    )
                    .matchedGeometryEffect(id: entry.id, in: morph)
                    .adaptiveZoomSource(id: entry.id, in: zoom)
                    // **El menú, solo en la rejilla.** Es donde se ven varios
                    // a la vez, que es justo cuando apetece reutilizar uno:
                    // copiarlo para variarlo, mandarlo a otro día. En revista
                    // solo ves uno y ahí manda el gesto de pasar. Ver
                    // `PlannerGrid`, que ya lo hacía así.
                    // El mismo menú que la elipsis, por si el dedo va antes
                    // que el ojo: mantener pulsado es como se pide un menú en
                    // cualquier otra rejilla del sistema.
                    .contextMenu {
                        Button("Editar", systemImage: "pencil") { edit(entry.outfit) }
                        Button("Probármelo", systemImage: "person.crop.rectangle") {
                            sheet = .tryOn(entry.outfit)
                        }
                        Button("Duplicar", systemImage: "plus.square.on.square") {
                            duplicate(entry.outfit)
                        }
                        Button("Mover a otro día", systemImage: "calendar") {
                            sheet = .move(entry.outfit)
                        }
                        Button("Quitar", systemImage: "trash", role: .destructive) {
                            deleting = entry.outfit
                        }
                    }
                }

                // **La misma tarjeta de crear**, con la misma identidad: al
                // cambiar de modo no aparece una nueva, viaja la que ya había.
                PlanCreateCard(date: date)
                    .matchedGeometryEffect(id: Self.createID + date.description, in: morph)
                    .aspectRatio(CanvasSpace.width / CanvasSpace.height, contentMode: .fit)
                    .onTapGesture { sheet = .picker }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            // **Seis puntos más que en la revista, contados de verdad.**
            //
            // Seis a secas no era eso: en la revista el aire de arriba no es
            // cero, lo pone la propia tarjeta dentro de su hueco —ver
            // `PlanCardSize`—, así que la rejilla empezaba treinta puntos más
            // arriba que el lienzo de al lado. Ahora se suma al mismo número
            // que usa la tarjeta.
            .padding(.top, cardInset + Self.gridTopExtra)
            .padding(.bottom, WKTabBarMetrics.clearance)
        }
        .scrollIndicators(.hidden)
    }

    /// Lo que la rejilla respira **de más** que la revista. Ver `grid(of:)`.
    private static let gridTopExtra: CGFloat = 6

    /// El aire que la tarjeta grande deja dentro de su hueco. Es el mismo
    /// número que `PlanCardSize`, y por eso sale de ahí y no de una copia.
    private var cardInset: CGFloat { PlanCardSize.inset(stride: stride) }

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
        guard let components = OutfitBackdropPalette.components(for: outfit.backdropRaw)
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
    /// Qué día es este. Solo para el taco de la tarjeta vacía.
    let day: Date
    let store: ImageStore
    let pageSize: CGSize
    let stride: CGFloat
    let morph: Namespace.ID
    let zoom: Namespace.ID
    let createID: String
    /// El cristal compartido entre los botones y el menú.
    let glass: Namespace.ID
    /// De dónde crece el editor de un outfit recién creado.
    let newOutfitID: UUID
    /// Si el selector de prendas está puesto ahora mismo.
    let isPicking: Bool
    /// Si el editor está abierto encima.
    let isEditing: Bool
    let onEdit: (Outfit) -> Void
    let onMove: (Outfit) -> Void
    let onTryOn: (Outfit) -> Void
    let onDelete: (Outfit) -> Void
    let onCreate: () -> Void

    @State private var anchor: AnyHashable?

    var body: some View {
        // **El día vacío no es una lista de uno.**
        //
        // Metida en el scroll, la tarjeta de crear heredaba el hueco de una
        // pantalla entera —el que hace que los lienzos enganchen siempre en el
        // mismo punto— y con la tira de días encima ese hueco empieza más
        // abajo de lo que acaba: la tarjeta quedaba alta, con un palmo de aire
        // debajo y casi nada arriba. Sin nada que pasar, no hay nada que
        // enganchar: se centra y ya está.
        if entries.isEmpty {
            PlanCreateCard(date: day)
                .matchedGeometryEffect(id: createID, in: morph)
                // **De aquí crece el editor de lo recién creado.** Un origen
                // puesto en la pantalla entera envolvía a los de cada
                // tarjeta, y el zoom cogía el de fuera: la transición salía
                // del borde de la pantalla en vez del lienzo que tocaste.
                .adaptiveZoomSource(id: newOutfitID, in: zoom)
                .padding(.horizontal, WK.Spacing.screenInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .onTapGesture { onCreate() }
        } else {
            feed
        }
    }

    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    PlanFeedCard(
                        entry: entry,
                        store: store,
                        glass: glass,
                        onEdit: { onEdit(entry.outfit) },
                        onMove: { onMove(entry.outfit) },
                        onTryOn: { onTryOn(entry.outfit) },
                        onDelete: { onDelete(entry.outfit) }
                    )
                    .matchedGeometryEffect(id: entry.id, in: morph)
                    .modifier(PlanCardSize(page: pageSize, stride: stride))
                    // **Después de medirla.** Puesto antes, el origen del
                    // zoom era la tarjeta sin su hueco, así que la pantalla
                    // crecía desde un rectángulo que no es el que se ve.
                    .adaptiveZoomSource(id: entry.id, in: zoom)
                    .id(AnyHashable(entry.id))
                }

            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $anchor, anchor: .center)
        .scrollIndicators(.hidden)
        // **Y con outfits, el tirón.**
        //
        // Llegas al último lienzo del día, sigues tirando hacia arriba porque
        // quieres ver si hay más, y la respuesta llega en el mismo movimiento
        // con el que has preguntado: no hay más, pero puedes añadir otro. Es
        // el mismo gesto que ya trae más propuestas en inspiración y el que
        // tenía el plan viejo. Ver `overscrollAction`.
        .modifier(
            CreateOnOverscroll(isOn: !isPicking && !isEditing, action: onCreate)
        )
    }
}

/// El tirón del final que crea un outfit, o nada.
///
/// En un modificador porque `overscrollAction` no se puede poner "a medias":
/// con el selector abierto encima, o con el editor delante, el scroll sigue
/// vivo por debajo y un rebote dispararía otra vez lo que ya está abierto.
struct CreateOnOverscroll: ViewModifier {
    let isOn: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if isOn {
            content.overscrollAction(
                // Los mismos números que en el armario, que es donde este
                // gesto ya existía: el mismo tirón tiene que costar lo mismo y
                // la píldora tiene que salir a la misma altura.
                //
                // El hueco de la barra de pestañas **ya está reservado** —va
                // como área segura—, así que aquí basta un respiro. Con la
                // barra contada a mano encima de eso, la píldora salía un
                // palmo más arriba que la del armario.
                threshold: 84,
                label: "Crear un outfit",
                bottomInset: WK.Spacing.m,
                // El retraso ya no se pone aquí: lo lleva el propio gesto,
                // que sabe cuándo ha terminado de volver el lienzo. Ver
                // `OverscrollAction.fireIfDue`.
                action: action
            )
        } else {
            content
        }
    }
}

/// Lo que mide una tarjeta del plan: una pantalla, con su aire dentro.
///
/// El mismo reparto que la inspiración —once doceavas partes— para que el
/// enganche del scroll y el centro de la pantalla sean el mismo punto. Ver
/// `InspoCardSize`.
struct PlanCardSize: ViewModifier {
    /// El aire de la tarjeta dentro de su hueco, en función de lo que mide el
    /// hueco. Estático para que la rejilla pueda pedir el mismo número en vez
    /// de copiarlo.
    static func inset(stride: CGFloat) -> CGFloat {
        max(WK.Spacing.xs, stride / 24)
    }

    let page: CGSize
    /// Lo que mide un hueco. Si no se dice, el del contenedor.
    var stride: CGFloat?

    func body(content: Content) -> some View {
        content
            .padding(.vertical, PlanCardSize.inset(stride: stride ?? page.height))
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
    /// El cristal que comparten estos botones con el menú de la rejilla.
    let glass: Namespace.ID
    let onEdit: () -> Void
    let onMove: () -> Void
    let onTryOn: () -> Void
    let onDelete: () -> Void

    var body: some View {
        LookCanvasView(
            garments: entry.outfit.garments,
            store: store,
            backdrop: backdrop,
            outfit: entry.outfit,
            showsBorder: true,
            // El doble toque tiene que llegar también encima de la ropa: si la
            // prenda no lo lleva, ahí el gesto no existe. Ver `GarmentTouch`.
            onDoubleTap: onEdit
        )
        // **Sin píldora de fecha.** El día ya está arriba, en la tira, y
        // repetirlo dentro de cada lienzo es decir dos veces lo mismo tapando
        // la ropa.
        .overlay(alignment: .topTrailing) {
            // **Tres, y con sitio para los tres.** Aquí se ve un solo lienzo
            // a pantalla completa: hay hueco de sobra para las tres cosas que
            // se le hacen a un outfit planeado —abrirlo, cambiarlo de día,
            // quitarlo— y esconderlas tras un menú sería un toque de más para
            // todas.
            // **Un solo cristal, no tres pegados.** El contenedor funde las
            // superficies vecinas —para eso está— y es lo que hace que al
            // pasar a la rejilla los tres se conviertan en la elipsis en vez
            // de desaparecer y aparecer otra cosa: comparten identidad de
            // cristal con ella. Ver `adaptiveGlassID`.
            AdaptiveGlassContainer(spacing: WK.Spacing.xs) {
            VStack(spacing: WK.Spacing.xs) {
                WKCircleButton("pencil", size: .compact, action: onEdit)
                    .tint(WK.Palette.primaryText)
                    .adaptiveGlassID("actions-\(entry.id)", in: glass)
                WKCircleButton(
                    "arrow.up.and.down.and.arrow.left.and.right",
                    size: .compact,
                    action: onMove
                )
                .tint(WK.Palette.primaryText)
                // **Probárselo, aquí también.** Lo que tienes puesto para el
                // jueves es justo lo que quieres verte, y tenerlo solo en el
                // menú de la rejilla lo dejaba a dos toques de distancia en la
                // pantalla donde más se mira.
                WKCircleButton("person.crop.rectangle", size: .compact, action: onTryOn)
                    .tint(WK.Palette.primaryText)
                // El color **en el símbolo** y no en el `tint`: el estilo del
                // botón pinta su etiqueta con el color primario, así que el
                // tinte de fuera no llegaba y la papelera salía negra como
                // las demás.
                WKCircleButton(size: .compact, action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
            }
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
    /// El cristal compartido con los botones de la tarjeta grande.
    let glass: Namespace.ID
    let onEdit: () -> Void
    let onMove: () -> Void
    let onDuplicate: () -> Void
    let onTryOn: () -> Void
    let onDelete: () -> Void

    var body: some View {
        // **El mismo lienzo que a pantalla completa.** Con su papel: el color
        // es del outfit, no del tamaño con el que se mire, y en la rejilla
        // salían todos grises mientras en grande cada uno tenía el suyo.
        LookCanvasView(
            garments: entry.outfit.garments,
            store: store,
            backdrop: PlanFeedScreen.backdrop(of: entry.outfit),
            outfit: entry.outfit,
            showsBorder: true,
            onDoubleTap: onEdit
        )
        .overlay(alignment: .topTrailing) {
            // **Uno solo, y detrás un menú.** En una celda de rejilla tres
            // botones ocupan media tarjeta y se tocan entre ellos: el pulgar
            // acierta el de al lado al pasar. Con la elipsis, la celda enseña
            // el outfit y las acciones se piden cuando se quieren —y caben
            // todas, incluidas las que en grande no están.
            AdaptiveGlassContainer(spacing: WK.Spacing.xs) {
                Menu {
                    Button("Editar", systemImage: "pencil", action: onEdit)
                    Button("Probármelo", systemImage: "person.crop.rectangle", action: onTryOn)
                    Button("Duplicar", systemImage: "plus.square.on.square", action: onDuplicate)
                    Button("Mover a otro día", systemImage: "calendar", action: onMove)
                    Button("Quitar", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WK.Palette.primaryText)
                        .frame(width: 34, height: 34)
                        .contentShape(.circle)
                        .adaptiveGlassInteractive(in: .circle)
                }
                // La misma identidad que el lápiz de la tarjeta grande: los
                // tres botones se funden en este al cambiar de modo.
                .adaptiveGlassID("actions-\(entry.id)", in: glass)
            }
            // Separado del canto, como en grande: pegado al borde se lee como
            // si se saliera de la tarjeta, y el pulgar lo rozaba al pasar.
            .padding(WK.Spacing.s)
        }
    }
}

/// Crear uno nuevo. **La misma tarjeta** al final de la revista y al final de
/// la rejilla: no son dos botones que hacen lo mismo, es uno que está donde
/// acaba lo que hay.
struct PlanCreateCard: View {
    var title = "Crear un outfit"
    /// El día al que iría. Con él, la tarjeta lleva el taco de calendario —el
    /// mismo sticker que se le pone a un outfit planeado—, y el hueco vacío se
    /// lee como **ese día** y no como un botón suelto en medio de la pantalla.
    var date: Date?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
    }

    var body: some View {
        shape
            // **Un solo relleno, y el borde por dentro.**
            //
            // Estaba pintada con dos capas translúcidas —un relleno de tinta
            // al 3% y encima un trazo al 12%— y donde se cruzaban, que es
            // justo el borde, el color se sumaba: un canto más oscuro que el
            // resto de la tarjeta, como si estuviera mal recortada. Con
            // `strokeBorder` el trazo cae entero dentro y con un solo valor de
            // tinta la tarjeta es de un color, no de dos.
            .fill(WK.Palette.shelf)
            .overlay {
                shape.strokeBorder(
                    WK.Palette.ink(0.10),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                )
            }
            .overlay {
                // **Todo en el medio.** El taco de la fecha estaba en una
                // esquina y el "+" en el centro, así que la tarjeta tenía dos
                // sitios donde mirar y ninguno era el principal. En columna
                // se lee de una: qué día es, y qué se puede hacer con él.
                VStack(spacing: WK.Spacing.m) {
                    if let date {
                        // Color macizo y la opacidad aparte: ver
                        // `DatePadGlyph`.
                        DatePadGlyph(date: date, size: 40, opacity: 0.35)
                            .foregroundStyle(WK.Palette.primaryText)
                    }
                    VStack(spacing: WK.Spacing.xs) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .medium))
                        Text(title)
                            .font(WK.Font.headline)
                    }
                    .foregroundStyle(WK.Palette.secondaryText)
                }
            }
            .aspectRatio(CanvasSpace.width / CanvasSpace.height, contentMode: .fit)
    }
}
