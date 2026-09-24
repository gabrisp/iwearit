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
        /// Qué prenda es esa: la has tocado en el lienzo.
        case garment(Garment)
        /// A qué maleta se lo llevas.
        case suitcase(StylistLook)

        var id: String {
            switch self {
            case .filters: "filters"
            case let .day(look): "day-\(look.id)"
            case .place: "place"
            case let .garment(garment): "garment-\(garment.id)"
            case let .suitcase(look): "suitcase-\(look.id)"
            }
        }
    }
    /// Lo que mide el feed: para centrar el conjunto enfocado y para saber si
    /// la pantalla está tumbada.
    @State private var pageSize: CGSize = .zero
    /// Mientras se montan los siguientes.
    @State private var isGenerating = false
    /// Si el armario ya no da más combinaciones distintas. Lo dice la última
    /// tanda que no trajo nada: la tarjeta del final deja de prometer ocho
    /// más y dice que se acabó.
    @State private var isExhausted = false
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
                            onShelvesChanged: {
                                isExhausted = false
                                withAnimation(WKAnimation.content) { feed.wardrobeChanged() }
                            },
                            anchors: Binding(
                                get: { feed.anchors },
                                set: { picked in
                                    withAnimation(WKAnimation.content) {
                                        isExhausted = false
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
                    case let .suitcase(look):
                        // **A la maleta desde aquí.**
                        //
                        // Lo que se propone en octubre para un fin de semana
                        // en Lisboa no es un favorito ni es del jueves: es de
                        // ese viaje. Sin esto había que guardarlo, ir al
                        // armario, abrir la maleta y montarlo otra vez.
                        SuitcasePickerSheet { suitcase, dayIndex in
                            pack(look, into: suitcase, on: dayIndex)
                        }
                    case let .garment(garment):
                        // La misma hoja que al tocar la prenda colgada en su
                        // balda. Aquí no hay nada que saber que allí no: es la
                        // prenda, y desde ella se llega a todo lo suyo.
                        GarmentSheet(garment: garment)
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
            // `registeredModel` solo devuelve lo que este contexto ya tenga
            // en la mano, y un outfit recién creado dentro de la hoja puede no
            // estarlo: entonces devolvía nada y el lápiz del estilista no
            // hacía nada. `model(for:)` lo trae igualmente.
            editingOutfit = modelContext.registeredModel(for: request.persistentID)
                ?? modelContext.model(for: request.persistentID) as? Outfit
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
                    // **El icono del tiempo, en color.** Un sol y una nube
                    // en negro sobre cristal son dos manchas iguales; en
                    // multicolor el sol es amarillo y la lluvia azul, y el
                    // parte se lee sin leer. El texto sigue en tinta: ahí lo
                    // que importa es el número.
                    Image(systemName: weatherSymbol)
                        .symbolRenderingMode(.multicolor)
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
                .padding(.vertical, WK.Spacing.s)
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
            // **El icono no cambia; cambia el botón.** Con prendas puestas
            // pasaba a la versión rellena del símbolo, y un icono que se
            // transforma se lee como otro botón distinto. Lo que dice que hay
            // algo puesto es el propio botón: de cristal a cristal destacado.
            Button { sheet = .filters } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .tint(WK.Palette.primaryText)
            .modifier(ProminentWhenActive(isActive: !feed.anchors.isEmpty))
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
            LazyHStack(spacing: InspoCardSize.wideSpacing) {
                cards(axis: .horizontal)
            }
            .scrollTargetLayout()
        }
        // **El hueco de los lados es el que centra.** Sin él, la primera
        // tarjeta no puede llegar al medio de la pantalla —no hay nada que
        // poner a su izquierda— y el scroll la deja pegada al borde por mucho
        // que el ancla diga centro. Con él, la enfocada cae en el centro y
        // queda una entera a cada lado.
        .safeAreaPadding(.horizontal, InspoCardSize.wideInset(page: pageSize))
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
                backdrop: InspoPalette.color(
                    InspoPalette.backdrop(for: look, garments: look.garmentIDs.compactMap { byID[$0] })
                ),
                isSaved: saved.contains(look.id),
                onSave: { save(look) },
                onPlan: { sheet = .day(look) },
                onRegenerate: { regenerate(look) },
                onEdit: { edit(look) },
                onDismiss: { withAnimation(WKAnimation.content) { discard(look) } },
                onDislike: { withAnimation(WKAnimation.content) { dislike(look) } },
                swipe: swipe,
                showsHint: look.id == shown.first?.id && !hasHintedSwipe,
                onHintShown: { appEnvironment.tips.complete(.swipeLook) },
                // De lado solo cuando de lado no significa ya otra cosa.
                isSwipeEnabled: axis == .vertical,
                onSelectGarment: { sheet = .garment($0) },
                onPack: { sheet = .suitcase(look) }
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
        InspoMoreCard(
            count: InspoFeed.capacity,
            isWorking: isGenerating,
            isExhausted: isExhausted
        )
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
    /// El corazón es un interruptor: volver a tocarlo lo quita.
    ///
    /// Antes solo sabía encenderse, así que un toque sin querer —o cambiar de
    /// opinión— dejaba el conjunto en favoritos para siempre y había que ir al
    /// armario a quitarlo. El conjunto **no se borra** al quitarle el corazón:
    /// sigue siendo un outfit tuyo si lo habías editado o planeado; lo único
    /// que se va es el favorito.
    private func save(_ look: StylistLook) {
        if saved.contains(look.id) {
            saved.remove(look.id)
            if let outfit = outfit(for: look) {
                outfit.isFavorite = false
                try? modelContext.save()
            }
            return
        }

        let outfit = outfit(for: look) ?? materialise(look, isFavorite: true)
        guard let outfit else { return }
        outfit.isFavorite = true
        try? modelContext.save()
        feed.remember(outfit, for: look)
        feed.record(.liked, for: look)
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
        // Ponerle fecha es la señal más fuerte que hay: no es "me gusta", es
        // "me lo pongo". Ver `StyleVerdict.Kind`.
        feed.record(.planned, for: look)
    }

    /// A la maleta: el conjunto se hace outfit **de ese viaje**, con su día si
    /// se ha elegido uno.
    private func pack(_ look: StylistLook, into suitcase: Suitcase, on dayIndex: Int?) {
        let outfit = outfit(for: look) ?? materialise(look, isFavorite: false)
        guard let outfit else { return }
        outfit.suitcase = suitcase
        outfit.suitcaseDayIndex = dayIndex
        try? modelContext.save()
        feed.remember(outfit, for: look)
        // Llevárselo de viaje pesa como ponérselo: has decidido con qué vas a
        // andar por ahí una semana. Ver `StyleVerdict.Kind`.
        feed.record(.packed, for: look)
        saved.insert(look.id)
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
            isExhausted = false
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
            // No ha llegado nada: no es que haya fallado, es que ya están
            // todas. La tarjeta lo dice a partir de ahora.
            isExhausted = true
            isGenerating = false
            return
        }
        isExhausted = false
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
            backdropRaw: InspoPalette.backdrop(for: look, garments: pieces).rawValue,
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
    /// **Qué significa guardar aquí.**
    ///
    /// En la inspiración del armario, el corazón: pasa a favoritos y es tuyo.
    /// Dentro de una maleta eso no es lo que quieres —favorito es de tu
    /// armario, no del viaje—, así que ahí es un "+" que lo mete en los
    /// outfits de esa maleta.
    var keep: Keep = .favourite
    /// Si se puede poner fecha. En una maleta sin fechas no hay días a los que
    /// asignar nada, y un calendario que abre una lista vacía es un botón que
    /// no lleva a ninguna parte.
    var showsPlan = true
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
    /// Si el arrastre a los lados es de la tarjeta.
    ///
    /// **En horizontal no.** Tumbado —un iPad en apaisado— los conjuntos se
    /// pasan de lado, así que el mismo gesto significaría dos cosas a la vez:
    /// el dedo cruzando la pantalla sería pasar de conjunto y descartarlo. Ahí
    /// el gesto se apaga y las dos decisiones se toman con sus botones, que
    /// están siempre.
    var isSwipeEnabled = true
    /// Tocar una prenda del conjunto para ver cuál es. Ver `LookCanvasView`.
    var onSelectGarment: ((Garment) -> Void)?
    /// A la maleta. `nil` cuando ya estás dentro de una: ver
    /// `SuitcaseInspoTab`.
    var onPack: (() -> Void)?


    enum Keep {
        /// A favoritos.
        case favourite
        /// A los outfits de esta maleta.
        case trip

        var symbol: String { self == .favourite ? "heart" : "plus" }
        var doneSymbol: String { self == .favourite ? "heart.fill" : "checkmark" }
        /// De qué se llena: el corazón, de rojo; el "+" de la maleta, de tinta.
        var fill: Color { self == .favourite ? .red : WK.Palette.primaryText }
    }

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
            showsBorder: true,
            // La misma semilla con la que se guardará: ver `LookCanvasView`.
            seed: InspoPalette.seed(for: look),
            onSelectGarment: onSelectGarment,
            // El doble toque tiene que bajar hasta la prenda: en cuanto ella
            // escucha el toque simple, el de la tarjeta solo llega al papel.
            onDoubleTap: onEdit
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
            .modifier(
                SideSwipeArbitration(isOn: isSwipeEnabled) { phase in
                    switch phase {
                    case let .change(amount): track(amount)
                    case let .end(distance, velocity): finish(distance, velocity: velocity)
                    }
                }
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
                // Y sin gesto no hay nada que enseñar.
                guard showsHint, isSwipeEnabled else { return }
                await demonstrate()
                onHintShown()
            }
            // **Doble toque o pulsación larga para editarlo**, los mismos dos
            // gestos que abren cualquier otro lienzo de la app. Un toque
            // simple no: pasando conjuntos con el pulgar se toca sin querer, y
            // abrir el editor por error saca de la pantalla en la que estabas.
            // **El doble toque, de vuelta.** El lápiz de la esquina sigue
            // ahí para quien no lo conozca. La pulsación larga no vuelve: esa
            // sí se disparaba sola al apoyar el dedo pasando tarjetas.
            .onTapGesture(count: 2, perform: onEdit)
            // .onLongPressGesture(perform: onEdit)
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

        dislikeAway()
    }

    /// Descartar: la tarjeta se va por la izquierda y, cuando ya no se ve, se
    /// va de la lista.
    ///
    /// **Sin devolver el arrastre a cero**: ponerlo a cero antes de que la
    /// lista cambie devolvía la tarjeta al centro durante un fotograma —el
    /// parpadeo— y desde ahí se desvanecía.
    private func dislikeAway() {
        withAnimation(.easeOut(duration: 0.24)) { drag = -900 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            onDislike()
        }
    }

    /// Los cinco de siempre, en columna. Ver `LookActions`.
    private var actions: some View {
        LookActions(
            keep: keep,
            isSaved: isSaved,
            keepProgress: keepProgress,
            showsPlan: showsPlan,
            onSave: onSave,
            onPlan: onPlan,
            onPack: onPack,
            onEdit: onEdit,
            // Hace lo mismo que tirar a la izquierda, animación incluida.
            onDislike: dislikeAway,
            layout: .column
        )
        // Separados del canto: pegados al borde parecen a punto de salirse de
        // la tarjeta, y en una pantalla estrecha el pulgar los roza al pasar
        // de conjunto.
        .padding(WK.Spacing.m)
    }

    /// El botón redondo de siempre, con la medida de siempre. Ver
    /// `WKCircleButton`: antes cada sitio lo ponía a mano con su `frame`, y no
    /// había dos iguales.
    /// Cuánto le falta al arrastre para contar como me gusta, de 0 a 1. Solo
    /// hacia la derecha: a la izquierda lo que se está diciendo es lo otro.
    private var keepProgress: CGFloat {
        guard drag > 0 else { return 0 }
        return min(1, drag / Self.threshold)
    }

    private func circle(_ symbol: String, action: @escaping () -> Void) -> some View {
        WKCircleButton(symbol, size: .compact, action: action)
            .tint(WK.Palette.primaryText)
    }
}

/// Un símbolo que se llena de rojo desde abajo según avanza un gesto.
///
/// Lo usan el botón de la tarjeta y el indicador del centro de la pantalla:
/// dicen lo mismo, así que se dibujan igual.
struct FillingSymbol: View {
    let empty: String
    let full: String
    /// De 0 a 1. A 1, lleno.
    let progress: CGFloat
    var fill: Color = .red

    var body: some View {
        ZStack {
            // **El contorno se va mientras se llena.** Con el contorno negro
            // entero hasta el final, el corazón rojo quedaba enmarcado en una
            // raya negra que en el lleno no existe: se veían dos corazones, uno
            // dentro del otro. Desvaneciéndose con el progreso, al llegar
            // arriba solo queda el lleno.
            Image(systemName: empty)
                .foregroundStyle(WK.Palette.primaryText)
                .opacity(1 - progress)

            // **Desde el centro.** Un círculo que crece en el medio del
            // símbolo, no una cortina que sube: se lee como que el corazón se
            // enciende, no como que se va llenando un vaso. A 1,6 el círculo
            // ya cubre las esquinas del símbolo —la diagonal es √2—.
            Image(systemName: full)
                .foregroundStyle(fill)
                .mask {
                    Circle().scaleEffect(progress * 1.6)
                }
        }
        // Sin animación propia **ni anulada**: mientras arrastras, el progreso
        // llega sin animar y va pegado al dedo; al tocar el botón llega
        // animado y el corazón se enciende creciendo desde el centro. Quien
        // cambia el progreso decide cómo.
    }
}

// `KeepButton` se fue a `LookActions`, que es donde viven ahora los cinco.
// /// El botón de guardar, que se llena mientras tiras.
// ///
// /// El relleno va **dentro del símbolo**, no detrás: un círculo rojo creciendo
// /// bajo un corazón negro son dos cosas moviéndose, y lo que tiene que pasar es
// /// que el corazón se encienda. Se dibuja el símbolo lleno recortado por abajo
// /// a la altura del progreso, encima del vacío.
// private struct KeepButton: View {
//     let symbol: String
//     let doneSymbol: String
//     let isSaved: Bool
//     /// De 0 a 1. A 1 es justo cuando el gesto ya cuenta.
//     let progress: CGFloat
//     let action: () -> Void
//
//     var body: some View {
//         WKCircleButton(size: .compact, action: action) {
//             ZStack {
//                 Image(systemName: isSaved ? doneSymbol : symbol)
//                     .foregroundStyle(isSaved ? .red : WK.Palette.primaryText)
//                 if !isSaved, progress > 0 {
//                     Image(systemName: doneSymbol)
//                         .foregroundStyle(.red)
//                         .mask(alignment: .bottom) {
//                             GeometryReader { proxy in
//                                 Rectangle()
//                                     .frame(height: proxy.size.height * progress)
//                                     .frame(
//                                         maxWidth: .infinity,
//                                         maxHeight: .infinity,
//                                         alignment: .bottom
//                                     )
//                             }
//                         }
//                 }
//             }
//             // Sin animación propia: el progreso viene del dedo y ya se mueve
//             // con él. Animarlo aquí lo dejaría siempre un poco por detrás.
//             .animation(nil, value: progress)
//         }
//     }
// }

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
        // **Una tarjeta a medio hacer, no un cartel.**
        //
        // Lo de antes era un `ContentUnavailableView` con su título y su
        // explicación, y aparecía también en el medio segundo que tarda la
        // primera tanda en montarse: la pantalla se abría con un aviso de que
        // no hay nada, y acto seguido había ocho. Ver `InspoPlaceholderCard`.
        //
        // ContentUnavailableView {
        //     Label("Todavía no hay nada que proponer", systemImage: "sparkles")
        // } description: {
        //     Text(
        //         hasGarments
        //             ? "Hace falta al menos algo de arriba y algo de abajo para montar un conjunto."
        //             : "Añade algunas prendas al armario y aquí aparecerán conjuntos hechos con ellas."
        //     )
        // }
        InspoPlaceholderCard()
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.vertical, WK.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// El papel de un conjunto: **al azar, pero que pegue**.
    ///
    /// ## Por qué no vale el azar a secas
    ///
    /// Porque un conjunto verde oliva sobre papel oliva desaparece, y uno
    /// beige sobre papel crema es una mancha clara dentro de otra. El azar
    /// puro acierta la mayoría de las veces y falla estrepitosamente la que
    /// no, que es justo la que se recuerda.
    ///
    /// Así que se puntúa cada papel contra la ropa que lleva el conjunto:
    ///
    /// 1. **Contraste de claridad.** Ni poco —la ropa se pierde— ni
    ///    exagerado, que un papel oscuro bajo ropa clara convierte la tarjeta
    ///    en un cartel. El punto dulce está a media distancia.
    /// 2. **Distancia de tono.** Dos verdes distintos siguen siendo dos
    ///    verdes; separarse del tono dominante es lo que hace que la prenda
    ///    se lea como prenda y el papel como papel.
    /// 3. **Sin pasarse de color.** Entre dos papeles que empatan, gana el
    ///    más tranquilo: el papel no compite con lo que sostiene.
    ///
    /// De los mejores se elige con la semilla del conjunto, que es lo que
    /// mantiene el azar —dos conjuntos parecidos no salen iguales— sin perder
    /// que el mismo conjunto tenga siempre su color.
    static func backdrop(for look: StylistLook, garments: [Garment] = []) -> OutfitBackdrop {
        let all = OutfitBackdrop.allCases
        let seed = seed(for: look)
        let colors = garments.compactMap(\.colors.first)
        guard !colors.isEmpty else { return all[Int(seed % UInt64(all.count))] }

        let total = colors.reduce(0.0) { $0 + max($1.weight, 0.001) }
        let mixed = colors.reduce(into: (red: 0.0, green: 0.0, blue: 0.0)) { sum, color in
            let weight = max(color.weight, 0.001) / total
            sum.red += color.red * weight
            sum.green += color.green * weight
            sum.blue += color.blue * weight
        }
        let clothesLuminance = 0.2126 * mixed.red + 0.7152 * mixed.green + 0.0722 * mixed.blue
        let clothesHue = hue(red: mixed.red, green: mixed.green, blue: mixed.blue)

        let ranked = all.sorted { first, second in
            score(first, luminance: clothesLuminance, hue: clothesHue)
                > score(second, luminance: clothesLuminance, hue: clothesHue)
        }
        // Los cinco mejores y no el mejor: con uno solo, todos los conjuntos
        // de tonos parecidos saldrían sobre el mismo papel y la pantalla se
        // volvería monocroma.
        let best = Array(ranked.prefix(5))
        return best[Int(seed % UInt64(best.count))]
    }

    private static func score(_ backdrop: OutfitBackdrop, luminance: Double, hue: Double) -> Double {
        // A 0,35 de diferencia de claridad se lee perfecto; más allá empieza a
        // ser un cartel. La campana premia acercarse a ese punto.
        let contrast = 1 - min(1, abs(abs(backdrop.luminance - luminance) - 0.35) / 0.35)
        // Distancia de tono por el lado corto del círculo, normalizada.
        let raw = abs(backdrop.hue - hue)
        let distance = min(raw, 1 - raw) * 2
        // Y un empate lo rompe el más tranquilo.
        return contrast * 0.6 + distance * 0.3 + (1 - backdrop.saturation) * 0.1
    }

    private static func hue(red: Double, green: Double, blue: Double) -> Double {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        guard delta > 0.0001 else { return 0 }
        let hue: Double
        switch maximum {
        case red: hue = (green - blue) / delta
        case green: hue = 2 + (blue - red) / delta
        default: hue = 4 + (red - green) / delta
        }
        let normalised = (hue / 6).truncatingRemainder(dividingBy: 1)
        return normalised < 0 ? normalised + 1 : normalised
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
    /// Qué pasa al tirar a la derecha: un corazón en la inspiración, un "+"
    /// dentro de una maleta.
    /// Qué significa guardar aquí. Ver `InspoLookCard.Keep`.
    var keep: InspoLookCard.Keep = .favourite

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
            Group {
                if goesRight {
                    // **El mismo relleno que el botón de la tarjeta.** El
                    // símbolo vacío, y encima el lleno en rojo recortado desde
                    // abajo a la altura del arrastre: lleno justo cuando el
                    // gesto ya cuenta, que es el golpecito. Lo que dice el
                    // botón y lo que dice el centro de la pantalla es lo mismo,
                    // así que se tiene que ver igual. Ver `KeepButton`.
                    FillingSymbol(
                        empty: keep.symbol,
                        full: keep.doneSymbol,
                        progress: progress,
                        fill: keep.fill
                    )
                } else {
                    Image(systemName: "hand.thumbsdown.fill")
                        .foregroundStyle(WK.Palette.primaryText)
                }
            }
                .font(.system(size: 30, weight: .semibold))
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
        if isExhausted { return "Has llegado al final :)" }
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

    /// Lo que mide el aura del todo. Igual que el botón: lo que crece dentro
    /// de un botón redondo tiene que ser redondo.
    private static let size: CGFloat = 34

    var body: some View {
        // **El mismo relleno que el resto.** Tirar para barajar, tirar para
        // crear un outfit y esperar a que una prenda se reconstruya son el
        // mismo "va por aquí", así que se cuentan igual: de izquierda a
        // derecha, con el símbolo invirtiéndose por donde ya ha pasado. Ver
        // `WKProgressFill`.
        WKProgressFill(progress: pull) { color in
            Image(systemName: "shuffle")
                .foregroundStyle(color)
                .frame(width: Self.size, height: Self.size)
        }
        .clipShape(.circle)
        .animation(.smooth(duration: 0.18), value: pull)
    }
}

/// Destacado cuando hay algo puesto, de cristal cuando no.
private struct ProminentWhenActive: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.adaptiveProminentButton()
        } else {
            content
        }
    }
}

/// Lo que mide una tarjeta, y cómo entra y sale, según por dónde se pasen.
///
/// De pie, once doceavas partes del alto: la siguiente asoma por abajo. En
/// horizontal manda el alto —una tarjeta es más alta que ancha— y el ancho
/// sale de su proporción, así que entran dos y pico y el resto asoma por el
/// lado. En los dos casos el enfocado se ve entero y el resto acompaña.
struct InspoCardSize: ViewModifier {
    /// El aire entre tarjetas tumbadas. Aquí y no suelto en la pila: el ancho
    /// de una tarjeta depende de él, así que tienen que ser el mismo número.
    static let wideSpacing = WK.Spacing.m

    /// Lo que mide una tarjeta tumbada: **tres a lo ancho**.
    ///
    /// Antes el ancho salía del alto —la tarjeta ocupaba casi toda la pantalla
    /// de arriba abajo y el ancho lo ponía su proporción—, y entraban dos y
    /// pico: la enfocada en el centro, una entera a un lado y media al otro.
    /// Tres es lo que hace que el centro sea de verdad el centro, con una a
    /// cada lado.
    ///
    /// Se coge el menor de dos: lo que dan tres huecos a lo ancho, y lo que
    /// cabe de alto. Sin lo segundo, en una ventana baja —el iPad partido— la
    /// tarjeta pediría más alto del que hay y se saldría por abajo.
    static func wideWidth(page: CGSize) -> CGFloat {
        let ratio = CanvasSpace.width / CanvasSpace.height
        let byWidth = (page.width - 2 * wideSpacing) / 3
        let byHeight = max(240, page.height * 0.92) * ratio
        return max(200, min(byWidth, byHeight))
    }

    /// Lo que hay que dejar a los lados para que la tarjeta enfocada caiga en
    /// el centro **y** las de al lado se vean enteras.
    static func wideInset(page: CGSize) -> CGFloat {
        max(WK.Spacing.screenInset, (page.width - wideWidth(page: page)) / 2)
    }

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
            let width = Self.wideWidth(page: page)
            content
                .frame(
                    width: width,
                    height: width / (CanvasSpace.width / CanvasSpace.height)
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
