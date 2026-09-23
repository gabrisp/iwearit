import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence
import WKServices

/// Inspiración: conjuntos ya montados con **tu ropa**, y un sitio donde
/// pedirlos a medida.
///
/// ## Qué es y qué no
///
/// No son fotos de revista: son tus prendas puestas en un lienzo, así que lo
/// que ves se puede guardar, editar y ponerse un día concreto como cualquier
/// outfit tuyo. Y el chat no habla con ningún servidor — el estilista es local
/// y se explica: cada propuesta sabe decir por qué (ver `Stylist`).
///
/// ## Por qué es una pantalla y no una hoja
///
/// Porque no se viene aquí a echar un vistazo y volver: se viene a pasar
/// conjuntos. Una hoja deja el armario asomando por detrás compitiendo por la
/// atención, y su gesto de cerrar pelea con el de pasar al siguiente.
///
/// ## Y por qué se pasan en vertical
///
/// Porque es el gesto que ya tiene el pulgar aprendido de cualquier feed: uno
/// entero en el centro, el de antes y el de después asomando por arriba y por
/// abajo para que se vea que hay más. Lo que está en el centro está a tamaño
/// completo; lo demás acompaña.
struct InspoScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment
    /// Quién presenta la hoja del estilista. Ver `AppRouter`.
    @Environment(AppRouter.self) private var router: AppRouter?

    /// Qué pestaña está puesta. La barra vive dentro de la pila de cada
    /// pantalla raíz: ver `rootTabBar`.
    @Binding var tab: RootTab
    let feed: InspoFeed

    /// Todo el armario, para resolver los conjuntos a prendas de verdad.
    ///
    /// El motor trabaja con identificadores —no puede tocar SwiftData desde
    /// donde corre— y la vista necesita los modelos para pintar sus imágenes.
    /// Esta consulta es el puente, y se hace **una vez** por pantalla.
    @Query(FetchDescriptor<Garment>.visibleGarments())
    private var garments: [Garment]

    @State private var saved: Set<UUID> = []
    /// Qué hoja está puesta, en **un solo sitio**: con un `.sheet` por cada
    /// una, SwiftUI atiende a uno y deja mudos los demás. Ver `AppRouter`.
    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        /// Qué baldas entran en las propuestas.
        case filters
        /// Qué día te pones este conjunto.
        case day(StylistLook)
        /// Dónde estás, para saber qué tiempo hace.
        case place

        var id: String {
            switch self {
            case .filters: "filters"
            case let .day(look): "day-\(look.id)"
            case .place: "place"
            }
        }
    }
    /// Lo que mide el feed: para centrar el conjunto enfocado y para saber si
    /// la pantalla está tumbada.
    @State private var pageSize: CGSize = .zero
    /// Mientras se montan los siguientes.
    @State private var isGenerating = false
    /// Cuántas tandas se han traído. Solo sirve para dar el golpecito: sube
    /// una vez por tanda de verdad, así que no hay forma de que suene dos
    /// veces ni de que suene cuando no ha llegado nada.
    @State private var batches = 0
    /// Si el gesto de los lados ya se ha enseñado alguna vez.
    @State private var hasHintedSwipe = true
    /// Cuánto se está tirando desde arriba, de 0 a 1. Ver `pullToShuffle`.
    @State private var pull: CGFloat = 0
    /// Si este tirón todavía puede disparar: uno por gesto.
    @State private var isPullArmed = false
    /// El conjunto que se está abriendo en el editor.
    @State private var editingOutfit: Outfit?
    /// De qué propuesta salió el editor, para devolverle lo editado.
    @State private var editedLook: StylistLook?
    /// Cuánto se está arrastrando la tarjeta de encima, **fuera del cuerpo de
    /// la pantalla**. Ver `InspoSwipe`.
    @State private var swipe = InspoSwipe()
    /// De dónde sale el editor al abrirse: de la propia tarjeta.
    @Namespace private var zoom
    /// Qué tarjeta se está mirando, para poder subir arriba al barajar.
    @State private var scrolled: UUID?

    private var shown: [StylistLook] { feed.looks }

    /// El id de la transición cuando no se sabe de qué tarjeta se salió.
    private static let noLookZoomID = UUID()

    /// El de la tarjeta del final, la que trae más.
    private static let moreCardID = UUID()

    /// Qué pone arriba: el sitio y los grados de hoy.
    private var weatherTitle: String {
        guard let forecast = feed.forecast else { return "Elegir sitio" }
        let degrees = Int(forecast.highCelsius.rounded())
        guard let place = forecast.place, !place.isEmpty else { return "\(degrees)°" }
        // Solo la ciudad: "Madrid, España, 33°" es el país repetido en la
        // barra más estrecha de la pantalla.
        let city = place.split(separator: ",").first.map(String.init) ?? place
        return "\(city), \(degrees)°"
    }

    private var weatherSymbol: String {
        feed.forecast?.condition.symbolName ?? "location"
    }

    private var byID: [UUID: Garment] {
        Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            feedView
                .background(WK.Palette.canvas.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                // **El estilista, solo aquí.** Preguntarle por un look es
                // algo que se hace mirando conjuntos; en el armario el botón
                // era un icono más que no venía a cuento.
                .rootTabBar(.inspo, selection: $tab, onAssistant: { router?.openStylist() })
                .navigationDestination(item: $editingOutfit) { outfit in
                    AdvancedCanvasScreen(
                        outfit: outfit,
                        store: appEnvironment.imageStore,
                        // Descartar en el editor se lleva el outfit: lo que
                        // había antes de entrar era una propuesta, no algo
                        // tuyo. Y la tarjeta vuelve a enseñar la propuesta.
                        isNew: true
                    )
                    // **El editor sale de la tarjeta que has abierto**, como
                    // en el plan. Sin el destino, la pantalla entra deslizando
                    // desde el lado y el conjunto que estabas mirando se
                    // queda sin relación con el que aparece.
                    .adaptiveZoomDestination(
                        // El de la tarjeta de la que salió. El de repuesto es
                        // una constante y no un `UUID()` nuevo: uno nuevo en
                        // cada pasada cambiaría de identidad entre fotogramas
                        // y la transición se quedaría sin destino.
                        id: AnyHashable(editedLook?.id ?? Self.noLookZoomID),
                        in: zoom
                    )
                }
                .sheet(item: $sheet) { which in
                    switch which {
                    case .filters:
                        InspoFiltersSheet(
                            anchors: Binding(
                                get: { feed.anchors },
                                set: { picked in
                                    withAnimation(WKAnimation.content) {
                                        feed.setAnchors(picked)
                                        scrolled = feed.looks.first?.id
                                    }
                                }
                            )
                        )
                    case let .day(look):
                        InspoDayPicker { date in
                            plan(look, on: date)
                            sheet = nil
                        }
                    case .place:
                        PlaceSearchSheet(title: "¿Dónde estás?") { place in
                            appEnvironment.weather.use(place)
                            Task { await feed.loadWeather() }
                        }
                    }
                }
        }
        .task {
            hasHintedSwipe = appEnvironment.tips.hasSeen(.swipeLook)
            // **El permiso, aquí y no al arrancar.** Es donde el motivo está
            // delante: esta pantalla viste según los grados que haga. Si ya se
            // ha contestado —sí o no— no se vuelve a preguntar.
            if appEnvironment.weather.place == nil, !appEnvironment.location.hasBeenAsked {
                if let place = await appEnvironment.location.current() {
                    appEnvironment.weather.use(place)
                }
            }
            await feed.loadWeather()
            feed.start()
        }
        // **Lo que pide el estilista.** Él no tiene pila de navegación —es una
        // hoja—, así que deja apuntado qué abrir y lo empuja esta pantalla,
        // que es la de debajo. Ver `AppRouter.editFromStylist`.
        .onChange(of: router?.editRequest) { _, request in
            guard let request else { return }
            editingOutfit = modelContext.registeredModel(for: request.persistentID)
        }
        // Al volver del editor: si el outfit sigue existiendo, se quedó lo
        // editado y la tarjeta lo enseña; si no —descartaste— se olvida y
        // vuelve la propuesta.
        .onChange(of: shown.map(\.id)) { _, _ in keepAnchorAlive() }
        .onChange(of: editingOutfit) { previous, current in
            // Y si el editor venía del estilista, se vuelve a él con la
            // conversación intacta.
            if current == nil, router?.editRequest != nil { router?.finishedEditing() }
            guard current == nil, let previous, let look = editedLook else { return }
            if previous.deletedAt == nil, previous.modelContext != nil {
                feed.remember(previous, for: look)
            } else {
                feed.forget(look)
            }
            editedLook = nil
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // **Arriba va el tiempo, no la palabra "Inspiración".**
        //
        // El título decía dónde estás, que ya lo sabes: has tocado la varita.
        // Lo que no sabes —y es lo que explica por qué hoy propone abrigo— es
        // que hacen ocho grados y llueve. Y si no hay sitio elegido, ese hueco
        // es justo donde pedirlo.
        ToolbarItem(placement: .principal) {
            Button { sheet = .place } label: {
                // Icono **y** texto, escritos a mano: un `Label` dentro de una
                // barra se queda solo con el icono, y "31°" sin el número no
                // dice nada.
                HStack(spacing: WK.Spacing.xs) {
                    Image(systemName: weatherSymbol)
                    Text(weatherTitle)
                }
                .font(WK.Font.callout)
                .foregroundStyle(WK.Palette.primaryText)
                // Para que la barra no lo estreche a puntos suspensivos.
                .fixedSize()
                // En su píldora de cristal, como los demás botones de la
                // barra: sin ella se lee como un título y no como algo que se
                // puede tocar — y esto se toca, para cambiar de sitio.
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.xs)
                .adaptiveGlassInteractive(in: .capsule)
            }
            .tint(WK.Palette.primaryText)
        }

        ToolbarItem(placement: .topBarLeading) {
            // **Un solo botón a este lado.** De qué se tira para montar
            // —prendas de partida y baldas— es una sola pregunta, y estaba
            // repartida en dos iconos pegados que abrían dos hojas. Relleno
            // cuando hay prendas puestas: es la única señal de que lo que ves
            // no sale del armario entero.
            Button { sheet = .filters } label: {
                Image(
                    systemName: feed.anchors.isEmpty
                        ? "line.3.horizontal.decrease"
                        : "line.3.horizontal.decrease.circle.fill"
                )
            }
            .tint(feed.anchors.isEmpty ? WK.Palette.primaryText : WK.Palette.accent)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { shuffle() } label: {
                // **El botón se enciende mientras tiras.**
                //
                // Tirar hacia abajo desde arriba baraja, y un gesto que no
                // dice qué va a hacer no se descubre. Lo que crece es el
                // aura —redonda, como el botón—, no el icono: un símbolo que
                // se hincha dentro de una barra que no cambia de alto se ve
                // como un fallo de medidas. Y lo que va quedando dentro del
                // aura se lee en blanco, así que el icono se enciende por
                // dentro en vez de moverse.
                ShuffleGlow(pull: pull)
            }
            .tint(WK.Palette.primaryText)
            .sensoryFeedback(.impact(weight: .light), trigger: pull >= 1)
        }
    }

    @ViewBuilder
    private var feedView: some View {
        if shown.isEmpty {
            InspoEmptyState(hasGarments: !garments.isEmpty)
        } else if isWide {
            // **Tumbado, se pasa de lado.**
            //
            // En un iPad en horizontal la pantalla es más ancha que alta: un
            // conjunto por página deja dos palmos de vacío a cada lado, y el
            // gesto que pide esa forma es el del dedo cruzando, no el de
            // subir. De pie —el iPhone siempre, el iPad en vertical— se queda
            // como estaba.
            wideFeed
        } else {
            tallFeed
        }
    }

    private var tallFeed: some View {
        ScrollView(.vertical) {
            // **Sin separación ni márgenes aquí.** El aire entre tarjetas va
            // dentro de cada hueco —ver `InspoCardSize`—, de modo que cada
            // elemento de la lista mide exactamente una pantalla. Con el aire
            // fuera, el sitio donde engancha `viewAligned` y el centro de la
            // pantalla no eran el mismo punto, y al pasar de conjunto la
            // tarjeta quedaba un pelín alta o un pelín baja según por dónde
            // fueras.
            LazyVStack(spacing: 0) {
                cards(axis: .vertical)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        // **Anclado al centro.** Por defecto el identificador se alinea con el
        // borde de arriba, así que al llevar la vista a un conjunto —al
        // barajar, o al traer más— quedaba pegado al techo y con un palmo de
        // aire debajo, que es justo lo contrario de lo que hace el gesto.
        .scrollPosition(id: $scrolled, anchor: .center)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.always, axes: .vertical)
        .overlay { InspoVerdictPill(swipe: swipe) }
        // El golpecito al traer más, como el del tirón de arriba: la tarjeta
        // del final se llena, y eso se nota en la mano además de verse.
        .sensoryFeedback(.impact(weight: .medium), trigger: batches)
        .modifier(PullToShuffle(pull: $pull, isArmed: $isPullArmed, action: shuffle))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
    }

    private var wideFeed: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: WK.Spacing.m) {
                cards(axis: .horizontal)
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolled, anchor: .center)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.always, axes: .horizontal)
        .overlay { InspoVerdictPill(swipe: swipe) }
        .sensoryFeedback(.impact(weight: .medium), trigger: batches)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
    }

    /// Las tarjetas, que son las mismas se pasen como se pasen.
    @ViewBuilder
    private func cards(axis: Axis) -> some View {
        ForEach(shown) { look in
            InspoLookCard(
                look: look,
                garments: look.garmentIDs.compactMap { byID[$0] },
                outfit: outfit(for: look),
                store: appEnvironment.imageStore,
                backdrop: InspoPalette.color(InspoPalette.backdrop(for: look)),
                isSaved: saved.contains(look.id),
                onSave: { save(look) },
                onPlan: { sheet = .day(look) },
                onRegenerate: { regenerate(look) },
                onEdit: { edit(look) },
                onDismiss: { withAnimation(WKAnimation.content) { discard(look) } },
                onDislike: { withAnimation(WKAnimation.content) { dislike(look) } },
                swipe: swipe,
                showsHint: look.id == shown.first?.id && !hasHintedSwipe,
                onHintShown: { appEnvironment.tips.complete(.swipeLook) }
            )
            .adaptiveZoomSource(id: AnyHashable(look.id), in: zoom)
            .modifier(InspoCardSize(axis: axis, page: pageSize))
        }

        // **Y una tarjeta más al final.**
        //
        // En vez de una píldora flotando sobre el borde, la última tarjeta de
        // la pila es la que trae más: cuesta subirla —hay que tirar del
        // final— y cuando sube, se llena. El gesto es el mismo que para pasar
        // de conjunto, así que no hay nada nuevo que aprender.
        InspoMoreCard(count: InspoFeed.capacity, isWorking: isGenerating)
            .modifier(InspoCardSize(axis: axis, page: pageSize))
            .id(Self.moreCardID)
            // Al asomar de verdad —más de la mitad— se pone a montar. Antes de
            // eso no: rozarla al pasar de conjunto no es pedir ocho más.
            .onScrollVisibilityChange(threshold: 0.6) { isVisible in
                guard isVisible else { return }
                generateMore()
            }
    }

    /// Si la pantalla es más ancha que alta.
    private var isWide: Bool { pageSize.width > pageSize.height }

    /// **El ancla del scroll, siempre apuntando a algo que existe.**
    ///
    /// `scrollPosition(id:)` se queda clavado si el identificador al que
    /// apunta desaparece de la lista —y desaparece en cuanto descartas el
    /// conjunto que estabas mirando, o cambias las prendas de partida—: el
    /// scroll dejaba de responder y parecía que la pantalla se había colgado.
    private func keepAnchorAlive() {
        guard let scrolled else { return }
        guard scrolled != Self.moreCardID else { return }
        guard !shown.contains(where: { $0.id == scrolled }) else { return }
        // **Se suelta, no se manda a ningún sitio.** Apuntarlo al primero era
        // un salto arriba del todo en cuanto descartabas algo; dejarlo en nada
        // desatasca el scroll igual y la lista se queda donde está, que es
        // donde la dejó el dedo.
        self.scrolled = nil
    }

    // MARK: Acciones

    /// Guardar es **hacerlo tuyo**: deja de ser una propuesta y pasa a
    /// favoritos, donde se edita como cualquier outfit.
    ///
    /// Y no tiene nada que ver con ponérselo un día: se puede guardar sin
    /// fecha —te gusta y ya— y se puede poner una fecha sin guardarlo.
    private func save(_ look: StylistLook) {
        let outfit = outfit(for: look) ?? materialise(look, isFavorite: true)
        guard let outfit else { return }
        outfit.isFavorite = true
        try? modelContext.save()
        feed.remember(outfit, for: look)
        saved.insert(look.id)
    }

    /// Ponérselo un día: el que elijas, no hoy por defecto.
    private func plan(_ look: StylistLook, on date: Date) {
        let outfit = outfit(for: look) ?? materialise(look, isFavorite: false)
        guard let outfit else { return }
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
        feed.remember(outfit, for: look)
    }

    /// Doble toque o pulsación larga: se abre en el editor con sus prendas ya
    /// colocadas, y lo que salga de ahí **vuelve a esta tarjeta**.
    private func edit(_ look: StylistLook) {
        let outfit = outfit(for: look) ?? materialise(look, isFavorite: false)
        guard let outfit else { return }
        try? modelContext.save()
        editedLook = look
        editingOutfit = outfit
    }

    /// El outfit de una propuesta, si ya se hizo uno.
    private func outfit(for look: StylistLook) -> Outfit? {
        guard let id = feed.outfitID(for: look) else { return nil }
        return modelContext.registeredModel(for: id)
    }

    /// Otro conjunto en su sitio, sin tocar los demás.
    private func regenerate(_ look: StylistLook) {
        guard
            let replacement = feed.replacement(
                for: look, excluding: Set(shown.flatMap(\.garmentIDs))
            )
        else { return }
        withAnimation(WKAnimation.content) { feed.replace(look, with: replacement) }
    }

    private func discard(_ look: StylistLook) {
        moveAnchor(off: look)
        feed.dismiss(look)
    }

    /// Suelta el ancla antes de que el conjunto al que apunta desaparezca.
    ///
    /// Antes apuntaba al siguiente, y eso era un scroll programado de una
    /// pantalla entera **mientras** la tarjeta descartada seguía ocupando
    /// sitio: se movía una pantalla y, al colapsar el hueco, volvía. Soltando
    /// el ancla, el hueco se cierra y el siguiente sube a su sitio solo, que
    /// es lo que se espera al tirar una carta de encima de la pila.
    private func moveAnchor(off look: StylistLook) {
        guard scrolled == look.id else { return }
        scrolled = nil
    }

    /// Baraja la tanda entera y sube arriba del todo.
    ///
    /// Barajar cambia lo que hay en todas las tarjetas; quedarse a medio
    /// scroll sería mirar la quinta de una baraja que acaba de cambiar entera.
    private func shuffle() {
        withAnimation(WKAnimation.content) {
            feed.shuffle()
            scrolled = feed.looks.first?.id
        }
    }

    /// Monta la siguiente tanda y lleva la vista al primero de los nuevos.
    ///
    /// Los nuevos entran **antes** de la tarjeta del final, así que quedarse
    /// donde estabas sería quedarse mirando la misma tarjeta de "más" con ocho
    /// conjuntos recién hechos por encima.
    private func generateMore() {
        guard !isGenerating else { return }
        isGenerating = true
        let before = Set(feed.looks.map(\.id))
        withAnimation(WKAnimation.content) { feed.extend() }
        let fresh = feed.looks.first { !before.contains($0.id) }

        guard let fresh else {
            isGenerating = false
            return
        }
        // Solo cuando de verdad ha llegado algo: si el armario ya no da para
        // más combinaciones distintas, un golpecito diría que sí.
        batches += 1

        // **Y la vista se lleva al primero de los nuevos después, no ahora.**
        //
        // Esto se dispara con el dedo todavía tirando de la tarjeta del final:
        // mover el scroll en ese momento pelea con el gesto que lo ha pedido y
        // se ve como un corte. Un suspiro más tarde el scroll ya ha parado y
        // el movimiento se lee como la respuesta a lo que pediste.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(WKAnimation.content) { scrolled = fresh.id }
            isGenerating = false
        }
    }

    /// Tirado a la izquierda: fuera, y sus prendas pesan menos a partir de
    /// ahora. Ver `InspoFeed.dislike`.
    private func dislike(_ look: StylistLook) {
        moveAnchor(off: look)
        feed.dislike(look)
    }

    /// El conjunto propuesto, hecho outfit de verdad.
    private func materialise(_ look: StylistLook, isFavorite: Bool) -> Outfit? {
        let pieces = look.garmentIDs.compactMap { byID[$0] }
        guard !pieces.isEmpty else { return nil }
        return OutfitAssembly.make(
            from: pieces,
            name: look.headline,
            origin: .inspo,
            isFavorite: isFavorite,
            // El papel que estabas viendo se guarda con él: abrir lo guardado
            // y encontrárselo en otro color sería otra prenda más que no
            // pediste.
            backdropRaw: InspoPalette.backdrop(for: look).rawValue,
            context: modelContext,
            seed: InspoPalette.seed(for: look)
        )
    }
}

/// Una propuesta a pantalla completa, con lo que se puede hacer con ella.
struct InspoLookCard: View {
    let look: StylistLook
    let garments: [Garment]
    /// El outfit de verdad, si esta propuesta ya se convirtió en uno.
    let outfit: Outfit?
    let store: ImageStore
    /// El color del papel. En la inspiración lo pone la paleta —ver
    /// `InspoPalette`—; dentro de una maleta lo pone la maleta, que es lo que
    /// la identifica entre varias.
    let backdrop: Color
    let isSaved: Bool
    let onSave: () -> Void
    let onPlan: () -> Void
    let onRegenerate: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void
    /// Descartar **y que cuente**: tirado a la izquierda.
    let onDislike: () -> Void
    /// Dónde se apunta el arrastre para que lo lea la píldora. La tarjeta
    /// **escribe** aquí y no lo lee: así apuntarlo no la reevalúa a ella.
    let swipe: InspoSwipe
    /// Si esta tarjeta tiene que enseñar el gesto la primera vez.
    var showsHint = false
    var onHintShown: () -> Void = {}

    /// Lo que se ha arrastrado de lado ahora mismo.
    @State private var drag: CGFloat = 0
    /// Si el arrastre ya ha pasado del punto de no retorno. Cambia una vez por
    /// cruce, que es lo que dispara el golpecito.
    @State private var isCommitted = false
    // **Hacia dónde va el gesto ya no se decide aquí.** Se decidía mirando
    // el primer aviso de arrastre y guardándolo en un `Axis?`, que es tarde:
    // para entonces el gesto ya le había quitado el dedo al scroll. Ahora lo
    // contesta UIKit antes de empezar. Ver `SideSwipeGesture`.
    // @State private var axis: Axis?

    /// Cuánto hay que tirar para que cuente.
    ///
    /// Ciento veinte puntos: lo bastante para que no pase al pasar tarjetas
    /// con el pulgar, lo bastante poco para hacerlo sin recolocar la mano.
    private static let threshold: CGFloat = 120

    /// El recorrido de la tarjeta para un arrastre dado.
    ///
    /// **Punto por punto con el dedo** mientras se decide: cualquier freno
    /// ahí se nota como que la tarjeta se resiste y no la llevas tú. Solo
    /// frena pasado el doble del umbral, cuando ya está medio fuera y lo único
    /// que queda por decir es que está decidido.
    static func tracked(_ value: CGFloat) -> CGFloat {
        let limit = threshold * 2
        let sign: CGFloat = value < 0 ? -1 : 1
        let magnitude = abs(value)
        guard magnitude > limit else { return value }
        return sign * (limit + (magnitude - limit) * 0.4)
    }

    var body: some View {
        LookCanvasView(
            garments: garments,
            store: store,
            backdrop: backdrop,
            outfit: outfit,
            showsBorder: true
        )
        // **La ropa se cambia, la tarjeta se queda.** Con la identidad puesta
        // en lo que hay dentro, al barajar se funde el contenido y el marco ni
        // se entera; sin ella, SwiftUI actualizaría las imágenes a saltos según
        // fueran cargando.
        .id(look.garmentIDs)
        .transition(.opacity)
            .overlay(alignment: .topTrailing) { actions }
            .offset(x: drag)
            .rotationEffect(.degrees(drag / 60))
            .scaleEffect(1 - min(0.03, abs(drag) / 3000))
            .contentShape(.rect)
            // **Y el gesto de lado lo arbitra UIKit.** Un `DragGesture` de
            // SwiftUI aquí se quedaba con el dedo aunque no hiciera nada, y el
            // scroll solo funcionaba arrastrando por fuera de la tarjeta. Ver
            // `SideSwipeGesture`.
            .gesture(
                SideSwipeGesture(
                    onChange: { track($0) },
                    onEnd: { distance, velocity in finish(distance, velocity: velocity) }
                )
            )
            // El golpecito al cruzar el umbral, en los dos sentidos: es cómo
            // se sabe que ya vale sin mirar cuánto llevas arrastrado.
            .sensoryFeedback(.impact(weight: .medium), trigger: isCommitted) { _, new in new }
            // **El gesto, enseñado una vez.**
            //
            // Arrastrar a los lados no se ve: no hay botón que lo insinúe y
            // quien no lo pruebe no lo descubre nunca. La primera vez, la
            // tarjeta se asoma sola a un lado y al otro —con su icono— y se
            // queda quieta. Es lo que haría alguien enseñándotelo.
            .task {
                guard showsHint else { return }
                await demonstrate()
                onHintShown()
            }
            // **Doble toque o pulsación larga para editarlo**, los mismos dos
            // gestos que abren cualquier otro lienzo de la app. Un toque
            // simple no: pasando conjuntos con el pulgar se toca sin querer, y
            // abrir el editor por error saca de la pantalla en la que estabas.
            .onTapGesture(count: 2, perform: onEdit)
            .onLongPressGesture(perform: onEdit)
    }

    /// Enseña el gesto: a la derecha y a la izquierda, sin llegar a decidir.
    @MainActor
    private func demonstrate() async {
        try? await Task.sleep(for: .milliseconds(700))
        for step in [Self.threshold * 0.8, 0, -Self.threshold * 0.8, 0] {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                drag = step
                swipe.amount = step
            }
            try? await Task.sleep(for: .milliseconds(650))
        }
        swipe.amount = 0
    }

    /// El dedo, mientras arrastra.
    private func track(_ amount: CGFloat) {
        drag = Self.tracked(amount)
        // Lo que lee la píldora, que vive fuera de la tarjeta.
        swipe.amount = drag
        let crossed = abs(drag) >= Self.threshold
        if crossed != isCommitted { isCommitted = crossed }
    }

    /// Al soltar: **a la derecha se queda, a la izquierda se va.**
    ///
    /// ## Por qué no se van las dos
    ///
    /// Porque no pasa lo mismo con las dos. Descartar saca el conjunto de la
    /// lista, así que la tarjeta se va y detrás viene otra. Guardar no lo saca
    /// de ningún sitio —sigue ahí, ahora con el corazón lleno—, así que
    /// tirarla fuera de pantalla para volver a pintarla en el sitio era ese
    /// parpadeo: la tarjeta se iba, la lista no cambiaba y volvía de golpe.
    /// Un me gusta devuelve la tarjeta a su sitio con un muelle, que es lo que
    /// hace cualquier cosa que has empujado y no se ha caído.
    private func finish(_ distance: CGFloat, velocity: CGFloat) {
        isCommitted = false
        swipe.amount = 0

        // La velocidad cuenta: un arrastre corto pero rápido está tan decidido
        // como uno largo y lento.
        let projected = distance + velocity * 0.12

        guard abs(projected) >= Self.threshold else {
            // Vuelve a su sitio con un muelle: soltarla a medias tiene que
            // devolverla, no dejarla torcida.
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { drag = 0 }
            return
        }

        guard projected < 0 else {
            // Me gusta: vuelve al centro y se queda, con el corazón ya lleno.
            onSave()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { drag = 0 }
            return
        }

        // Y el descarte se va del todo. **Sin devolver el arrastre a cero**:
        // ponerlo a cero antes de que la lista cambie devolvía la tarjeta al
        // centro durante un fotograma —el parpadeo— y desde ahí se desvanecía.
        // La tarjeta sale de pantalla, y cuando ya no se ve, se va de la lista.
        withAnimation(.easeOut(duration: 0.24)) { drag = -900 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            onDislike()
        }
    }

    private var actions: some View {
        VStack(spacing: WK.Spacing.xs) {
            circle(isSaved ? "heart.fill" : "heart", action: onSave)
                .foregroundStyle(isSaved ? WK.Palette.accent : WK.Palette.primaryText)
            circle("calendar", action: onPlan)
            // **El lápiz hace lo mismo que el doble toque.** Los dos gestos
            // están bien para quien los conoce; el botón está para quien no.
            circle("pencil", action: onEdit)

            // **Y tres, no cinco.**
            //
            // Descartar y volver a montar estaban aquí además de en el gesto:
            // arrastrar a la izquierda descarta y tirar de arriba rehace la
            // tanda. Cinco botones en el borde de cada tarjeta son cinco
            // decisiones cada vez que pasas una, y tres de ellas repetidas.
            //
            // circle("arrow.triangle.2.circlepath", action: onRegenerate)
            // circle("xmark", action: onDismiss)
        }
        // Separados del canto: pegados al borde parecen a punto de salirse de
        // la tarjeta, y en una pantalla estrecha el pulgar los roza al pasar
        // de conjunto.
        .padding(WK.Spacing.m)
    }

    private func circle(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .frame(width: 34, height: 34)
                .contentShape(.circle)
        }
        .buttonStyle(WKPressStyle())
        .tint(WK.Palette.primaryText)
        .adaptiveGlassInteractive(in: .circle)
    }
}

/// Qué día te lo vas a poner.
///
/// Una hoja pequeña y un calendario: ponerlo hoy sin preguntar era lo de
/// antes, y la mitad de las veces lo que quieres es el sábado.
private struct InspoDayPicker: View {
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            DatePicker(
                "Día",
                selection: $date,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .padding(.horizontal, WK.Spacing.m)
            .navigationTitle("¿Qué día?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(WK.Palette.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onPick(date) } label: { Image(systemName: "checkmark") }
                        .tint(WK.Palette.primaryText)
                        .adaptiveProminentButton()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct InspoEmptyState: View {
    let hasGarments: Bool

    var body: some View {
        ContentUnavailableView {
            Label("Todavía no hay nada que proponer", systemImage: "sparkles")
        } description: {
            Text(
                hasGarments
                    ? "Hace falta al menos algo de arriba y algo de abajo para montar un conjunto."
                    : "Añade algunas prendas al armario y aquí aparecerán conjuntos hechos con ellas."
            )
        }
    }
}

/// El color del papel de cada propuesta, y la variante de reparto.
///
/// ## Por qué cada una el suyo
///
/// Porque ocho conjuntos sobre el mismo fondo gris se leen como ocho filas de
/// una tabla. Con el papel cambiando, cada uno es **una lámina**: al pasar se
/// nota que ha cambiado algo aunque las prendas se parezcan.
///
/// Sale del identificador del conjunto y no de un contador, así que el mismo
/// conjunto tiene siempre su color —al volver a la pestaña, al guardarlo— y no
/// baila al añadir otros por encima.
enum InspoPalette {

    static func seed(for look: StylistLook) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in look.id.uuidString.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01b3
        }
        return hash
    }

    static func backdrop(for look: StylistLook) -> OutfitBackdrop {
        let all = OutfitBackdrop.allCases
        return all[Int(seed(for: look) % UInt64(all.count))]
    }

    static func color(_ backdrop: OutfitBackdrop) -> Color {
        let components = backdrop.components
        return WK.Palette.canvasTint(
            red: components.red,
            green: components.green,
            blue: components.blue
        )
    }
}

/// Cuánto se está arrastrando la tarjeta de encima.
///
/// ## Por qué esto no es un `@State` de la pantalla
///
/// Porque se escribe en cada fotograma del arrastre, y un `@State` de la
/// pantalla reevaluaría el feed entero —lista, tarjetas, lienzos— sesenta
/// veces por segundo. Con un objeto observable aparte, lo único que se
/// reevalúa es quien lo lee: la píldora.
@MainActor
@Observable
final class InspoSwipe {
    /// Puntos arrastrados. Positivo a la derecha.
    var amount: CGFloat = 0
}

/// Lo que va a pasar si sueltas: guardar o descartar.
///
/// **Quieta en el centro de la pantalla**, no pegada a la tarjeta. Pegada se
/// iba con ella —y girada—, así que justo cuando más falta hace leerla era
/// cuando peor se leía.
struct InspoVerdictPill: View {
    let swipe: InspoSwipe

    /// Lo mismo que le cuesta a la tarjeta comprometerse. Ver
    /// `InspoLookCard.threshold`.
    private static let threshold: CGFloat = 120

    var body: some View {
        let progress = min(1, abs(swipe.amount) / Self.threshold)
        if progress > 0.05 {
            let goesRight = swipe.amount > 0
            // **Un icono y ya.** El cartel con letra tapaba el conjunto justo
            // cuando lo estás mirando para decidir, y a medio arrastre se leía
            // media palabra. Un corazón o un pulgar dicen lo mismo de un
            // vistazo y dejan ver la ropa por detrás.
            Image(systemName: goesRight ? "heart.fill" : "hand.thumbsdown.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(goesRight ? WK.Palette.accent : WK.Palette.primaryText)
                .frame(width: 76, height: 76)
                .adaptiveGlass(in: .circle)
                // Crece y se asienta con el arrastre: a medio camino se ve que
                // falta, y al llegar se planta.
                .opacity(0.25 + progress * 0.75)
                .scaleEffect(0.7 + progress * 0.3)
                .allowsHitTesting(false)
        }
    }
}

/// La última tarjeta del feed: la que trae ocho más.
///
/// Tiene la pinta de un conjunto vacío —el mismo papel, el mismo borde— para
/// que al subir se lea como "aquí va a haber algo", y no como un botón que
/// alguien dejó suelto al final de la lista.
struct InspoMoreCard: View {
    let count: Int
    let isWorking: Bool
    /// Cuando el armario —o la maleta— ya no da más combinaciones distintas.
    ///
    /// Decirlo es mejor que dejar la tarjeta prometiendo ocho más que no van
    /// a llegar: tirar de ella tres veces sin que pase nada parece roto, y lo
    /// que pasa es que ya están todas.
    var isExhausted = false

    var body: some View {
        RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
            .fill(WK.Palette.ink(0.03))
            .overlay {
                RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
                    .stroke(
                        WK.Palette.ink(0.12),
                        style: StrokeStyle(lineWidth: 1, dash: [8, 6])
                    )
            }
            .overlay {
                VStack(spacing: WK.Spacing.s) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Image(systemName: isExhausted ? "checkmark.circle" : "wand.and.stars")
                            .font(.system(size: 26))
                            .foregroundStyle(WK.Palette.secondaryText)
                    }
                    Text(headline)
                        .font(WK.Font.headline)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, WK.Spacing.l)
                }
            }
            .aspectRatio(CanvasSpace.width / CanvasSpace.height, contentMode: .fit)
    }

    private var headline: String {
        if isWorking { return "Montando…" }
        if isExhausted { return "Ya están todos los que salen con esto" }
        return "Generar \(count) más"
    }
}

/// El botón de barajar mientras se tira de la pantalla hacia abajo.
///
/// El aura es un círculo —el mismo que el botón— que crece desde el centro, y
/// **lo que queda dentro se pinta en blanco**: el icono no se mueve ni cambia
/// de tamaño, se enciende. Ver `WKAura`.
private struct ShuffleGlow: View {
    let pull: CGFloat

    var body: some View {
        Image(systemName: "shuffle")
            .foregroundStyle(WK.Palette.primaryText)
            .frame(width: 30, height: 30)
            .background {
                Circle()
                    .fill(WK.Palette.accent.opacity(0.9))
                    .frame(width: 46, height: 46)
                    .scaleEffect(pull)
                    .opacity(pull)
                    .blur(radius: 6)
            }
            .overlay {
                // El mismo icono en blanco, recortado por el aura: donde llega
                // el círculo, el símbolo ya es blanco.
                Image(systemName: "shuffle")
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .mask {
                        Circle()
                            .frame(width: 46, height: 46)
                            .scaleEffect(pull * 1.1)
                    }
            }
            .animation(.smooth(duration: 0.18), value: pull)
    }
}

/// Lo que mide una tarjeta, y cómo entra y sale, según por dónde se pasen.
///
/// De pie, once doceavas partes del alto: la siguiente asoma por abajo. En
/// horizontal manda el alto —una tarjeta es más alta que ancha— y el ancho
/// sale de su proporción, así que entran dos y pico y el resto asoma por el
/// lado. En los dos casos el enfocado se ve entero y el resto acompaña.
struct InspoCardSize: ViewModifier {
    let axis: Axis
    let page: CGSize
    /// Cuánto mide un hueco, si no lo pone el contenedor.
    ///
    /// Dentro de una maleta el contenedor del scroll es la pantalla entera
    /// —la maleta ignora el área segura— y `containerRelativeFrame` daría
    /// tarjetas más grandes que en la pestaña. Pasándole a mano lo que queda
    /// entre las dos barras, las dos pantallas miden igual.
    var stride: CGFloat?

    func body(content: Content) -> some View {
        switch axis {
        case .vertical:
            // El hueco mide una pantalla y la tarjeta respira dentro: así el
            // enganche cae siempre en el mismo sitio y el conjunto enfocado
            // queda centrado por construcción.
            let stride = stride ?? page.height
            content
                .padding(.vertical, max(WK.Spacing.xs, stride / 24))
                .modifier(InspoCardSlot(stride: self.stride))
                .scrollTransition(.interactive, axis: .vertical) { view, phase in
                    view
                        .opacity(phase.isIdentity ? 1 : 0.35)
                        .scaleEffect(phase.isIdentity ? 1 : 0.88)
                }
        case .horizontal:
            let height = max(240, page.height * 0.88)
            content
                .frame(
                    width: height * (CanvasSpace.width / CanvasSpace.height),
                    height: height
                )
                .scrollTransition(.interactive, axis: .horizontal) { view, phase in
                    view
                        .opacity(phase.isIdentity ? 1 : 0.35)
                        .scaleEffect(phase.isIdentity ? 1 : 0.88)
                }
        }
    }
}

/// El alto de un hueco: el del contenedor, o el que le digan.
private struct InspoCardSlot: ViewModifier {
    let stride: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let stride {
            content.frame(height: stride)
        } else {
            content.containerRelativeFrame(.vertical)
        }
    }
}

/// Tirar hacia abajo desde arriba para barajar.
///
/// ## Por qué no `overscrollAction`
///
/// Porque aquel dibuja su propia píldora abajo, y aquí lo que tiene que
/// encenderse es el botón que ya existe: el de barajar. Lo que se comparte es
/// lo que importa —medir el desbordamiento, armar el gesto al empezar a
/// arrastrar y disparar al soltar— y el aura, que es la misma (ver `WKAura`).
///
/// Las tres reglas son las de siempre: solo cuenta el arrastre que **empieza**
/// arriba —si no, llegar al principio con inercia dispararía solo—, se decide
/// al soltar, y una vez por gesto.
private struct PullToShuffle: ViewModifier {
    @Binding var pull: CGFloat
    @Binding var isArmed: Bool
    let action: () -> Void

    /// Cuánto hay que tirar. Menos que el del final: arriba no hay nada que
    /// pueda dispararse sin querer.
    private static let threshold: CGFloat = 96

    @State private var offset: CGFloat = 0
    @State private var isTouching = false
    @State private var hasFired = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Negativo cuando se desborda por arriba.
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, new in
                offset = new
                let overscroll = max(0, -new)
                pull = isArmed ? min(1, overscroll / Self.threshold) : 0
                if overscroll <= 2 { hasFired = false }
            }
            .onScrollPhaseChange { _, phase in
                let touching = phase == .tracking || phase == .interacting
                if touching, !isTouching {
                    // Solo si el arrastre empieza ya arriba del todo.
                    isArmed = offset >= -4
                }
                if !touching, isTouching {
                    fireIfDue()
                }
                isTouching = touching
            }
    }

    private func fireIfDue() {
        defer { pull = 0 }
        guard isArmed, !hasFired, pull >= 1 else { return }
        hasFired = true
        action()
    }
}
