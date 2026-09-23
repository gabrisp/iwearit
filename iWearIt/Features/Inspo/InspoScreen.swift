import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

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
    /// Si está puesta la hoja de qué baldas entran en la inspiración.
    @State private var isChoosingShelves = false
    /// Lo que mide el feed, para poder centrar el conjunto enfocado.
    @State private var pageHeight: CGFloat = 0
    /// El conjunto que se está abriendo en el editor.
    @State private var editingOutfit: Outfit?
    /// El conjunto al que se le está eligiendo día.
    @State private var datingLook: StylistLook?
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

    private var byID: [UUID: Garment] {
        Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            feedView
                .background(WK.Palette.canvas.ignoresSafeArea())
                .navigationTitle("Inspiración")
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
                .sheet(item: $datingLook) { look in
                    InspoDayPicker { date in
                        plan(look, on: date)
                        datingLook = nil
                    }
                }
                .sheet(isPresented: $isChoosingShelves) {
                    InspoShelvesSheet()
                }
        }
        .task {
            await feed.loadWeather()
            feed.start()
        }
        // Al volver del editor: si el outfit sigue existiendo, se quedó lo
        // editado y la tarjeta lo enseña; si no —descartaste— se olvida y
        // vuelve la propuesta.
        .onChange(of: editingOutfit) { previous, current in
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
        ToolbarItem(placement: .topBarLeading) {
            // Qué baldas entran. La ropa de disfraces sigue en el armario,
            // pero no tiene por qué salir propuesta para un martes.
            Button { isChoosingShelves = true } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .tint(WK.Palette.primaryText)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(WKAnimation.content) {
                    feed.shuffle()
                    // **Y arriba del todo.** Barajar cambia lo que hay en
                    // todas las tarjetas; quedarse a medio scroll sería mirar
                    // la quinta de una baraja que acaba de cambiar entera.
                    scrolled = feed.looks.first?.id
                }
            } label: {
                Image(systemName: "shuffle")
            }
            .tint(WK.Palette.primaryText)
        }
    }

    @ViewBuilder
    private var feedView: some View {
        if shown.isEmpty {
            InspoEmptyState(hasGarments: !garments.isEmpty)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: WK.Spacing.m) {
                    ForEach(shown) { look in
                        InspoLookCard(
                            look: look,
                            garments: look.garmentIDs.compactMap { byID[$0] },
                            outfit: outfit(for: look),
                            store: appEnvironment.imageStore,
                            backdrop: InspoPalette.backdrop(for: look),
                            isSaved: saved.contains(look.id),
                            onSave: { save(look) },
                            onPlan: { datingLook = look },
                            onRegenerate: { regenerate(look) },
                            onEdit: { edit(look) },
                            onDismiss: { withAnimation(WKAnimation.content) { discard(look) } },
                            onDislike: { withAnimation(WKAnimation.content) { dislike(look) } },
                            swipe: swipe
                        )
                        .adaptiveZoomSource(id: AnyHashable(look.id), in: zoom)
                        // Once doceavos del alto: el conjunto manda en la
                        // pantalla y el siguiente asoma lo justo para contar
                        // que hay más, sin gastar ni un punto en decirlo.
                        .containerRelativeFrame(
                            .vertical, count: 12, span: 11, spacing: WK.Spacing.m
                        )
                        // El del centro, entero. Los de los lados, atrás.
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.35)
                                .scaleEffect(phase.isIdentity ? 1 : 0.88)
                        }

                    }
                }
                // **El aire de centrado, por dentro.**
                //
                // Como `safeAreaPadding` del scroll, además de centrar las
                // tarjetas subía todo lo que se dibuje encima del scroll —la
                // píldora del tirón entre ello—, que es por lo que quedaba a
                // media pantalla en vez de justo encima de la barra.
                .padding(.vertical, pageHeight / 24)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolled)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always, axes: .vertical)
            // **Más, cuando lo pidas.** Se montan solos cada rato y se
            // rehacen al barajar, pero llegar al final y que aparezcan ocho
            // más sin haberlos pedido convierte la pantalla en un pozo: ni se
            // acaba nunca ni se sabe cuándo has visto todo. Con el tirón, el
            // final es un final y seguir es una decisión.
            .overlay { InspoVerdictPill(swipe: swipe) }
            .overscrollAction(
                threshold: 84,
                symbol: "wand.and.stars",
                label: "Generar \(InspoFeed.capacity) más",
                // El mismo respiro que "Crear nuevo outfit" en el armario: el
                // hueco de la barra ya lo reserva ella, así que sumarle su
                // alto otra vez subía la píldora media pantalla.
                bottomInset: WK.Spacing.m
            ) {
                withAnimation(WKAnimation.content) { feed.extend() }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
        }
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
        feed.dismiss(look)
    }

    /// Tirado a la izquierda: fuera, y sus prendas pesan menos a partir de
    /// ahora. Ver `InspoFeed.dislike`.
    private func dislike(_ look: StylistLook) {
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
private struct InspoLookCard: View {
    let look: StylistLook
    let garments: [Garment]
    /// El outfit de verdad, si esta propuesta ya se convirtió en uno.
    let outfit: Outfit?
    let store: ImageStore
    /// El color del papel. Ver `InspoPalette`.
    let backdrop: OutfitBackdrop
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

    /// Lo que se ha arrastrado de lado ahora mismo.
    @State private var drag: CGFloat = 0
    /// Si el arrastre ya ha pasado del punto de no retorno. Cambia una vez por
    /// cruce, que es lo que dispara el golpecito.
    @State private var isCommitted = false
    /// **Hacia dónde va este gesto, decidido una sola vez.**
    ///
    /// Mirar en cada aviso si el movimiento es más horizontal que vertical
    /// dejaba la tarjeta a medias: bastaba que el dedo subiera un poco para
    /// que el aviso se ignorara y se quedara clavada donde estuviera, sin
    /// volver y sin irse. Se decide al empezar y se respeta hasta que se
    /// levanta el dedo.
    @State private var axis: Axis?

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
            backdrop: InspoPalette.color(backdrop),
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
            // **Simultáneo con el scroll y no por encima.** Con un gesto
            // propio que se lo comía, cada arrastre tenía que ganarle primero
            // la partida al scroll: eso era el tirón que se notaba al empezar
            // a mover, tanto de lado como al pasar de conjunto.
            .simultaneousGesture(sideSwipe)
            // El golpecito al cruzar el umbral, en los dos sentidos: es cómo
            // se sabe que ya vale sin mirar cuánto llevas arrastrado.
            .sensoryFeedback(.impact(weight: .medium), trigger: isCommitted) { _, new in new }
            // **Doble toque o pulsación larga para editarlo**, los mismos dos
            // gestos que abren cualquier otro lienzo de la app. Un toque
            // simple no: pasando conjuntos con el pulgar se toca sin querer, y
            // abrir el editor por error saca de la pantalla en la que estabas.
            .onTapGesture(count: 2, perform: onEdit)
            .onLongPressGesture(perform: onEdit)
    }

    /// El arrastre: a la derecha se guarda, a la izquierda se descarta.
    private var sideSwipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if axis == nil {
                    // La primera dirección manda: si el gesto empezó subiendo,
                    // es scroll y esta tarjeta no se entera.
                    axis = abs(value.translation.width) > abs(value.translation.height)
                        ? .horizontal
                        : .vertical
                }
                guard axis == .horizontal else { return }

                drag = Self.tracked(value.translation.width)
                // Lo que lee la píldora, que vive fuera de la tarjeta.
                swipe.amount = drag
                let crossed = abs(drag) >= Self.threshold
                if crossed != isCommitted { isCommitted = crossed }
            }
            .onEnded { value in
                // **Pase lo que pase, la tarjeta vuelve o se va.** El gesto
                // termina aquí incluso si acabó siendo vertical, así que aquí
                // es donde se garantiza que no se queda a medias.
                let wasHorizontal = axis == .horizontal
                axis = nil
                isCommitted = false
                swipe.amount = 0
                guard wasHorizontal else {
                    if drag != 0 {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { drag = 0 }
                    }
                    return
                }

                let distance = value.translation.width
                // **Y cuánta fuerza llevaba.** Un arrastre corto pero rápido
                // es tan decidido como uno largo y lento; medir solo la
                // distancia obliga a arrastrar media pantalla para algo que ya
                // habías decidido.
                let projected = distance + value.predictedEndTranslation.width * 0.35

                guard abs(projected) >= Self.threshold else {
                    // Vuelve a su sitio con un muelle: soltarla a medias tiene
                    // que devolverla, no dejarla torcida.
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { drag = 0 }
                    return
                }
                let goesRight = projected > 0
                withAnimation(.easeOut(duration: 0.22)) {
                    drag = goesRight ? 900 : -900
                }
                // Después de irse, no antes: la tarjeta sale de pantalla y
                // entonces cambia la lista.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    drag = 0
                    if goesRight { onSave() } else { onDislike() }
                }
            }
    }

    private var actions: some View {
        VStack(spacing: WK.Spacing.xs) {
            circle(isSaved ? "heart.fill" : "heart", action: onSave)
                .foregroundStyle(isSaved ? WK.Palette.accent : WK.Palette.primaryText)
            circle("calendar", action: onPlan)
            circle("arrow.triangle.2.circlepath", action: onRegenerate)
            circle("xmark", action: onDismiss)
        }
        .padding(WK.Spacing.s)
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
private struct InspoVerdictPill: View {
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
