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

    private var shown: [StylistLook] { feed.looks }

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
                .rootTabBar(.inspo, selection: $tab)
                .navigationDestination(item: $editingOutfit) { outfit in
                    AdvancedCanvasScreen(
                        outfit: outfit,
                        store: appEnvironment.imageStore,
                        // Descartar en el editor se lleva el outfit: lo que
                        // había antes de entrar era una propuesta, no algo
                        // tuyo. Y la tarjeta vuelve a enseñar la propuesta.
                        isNew: true
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
                withAnimation(WKAnimation.content) { feed.shuffle() }
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
                            isSaved: saved.contains(look.id),
                            onSave: { save(look) },
                            onPlan: { datingLook = look },
                            onRegenerate: { regenerate(look) },
                            onEdit: { edit(look) },
                            onDismiss: { withAnimation(WKAnimation.content) { discard(look) } }
                        )
                        // Siete octavos del alto: el siguiente asoma por abajo
                        // y el anterior por arriba, que es lo que cuenta que
                        // hay más sin gastar ni un punto en decirlo.
                        .containerRelativeFrame(
                            .vertical, count: 8, span: 7, spacing: WK.Spacing.m
                        )
                        // El del centro, entero. Los de los lados, atrás.
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.35)
                                .scaleEffect(phase.isIdentity ? 1 : 0.88)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            // El octavo que sobra, repartido arriba y abajo: así el conjunto
            // enfocado queda **centrado de verdad** y no pegado al borde.
            .safeAreaPadding(.vertical, pageHeight / 16)
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

    /// El conjunto propuesto, hecho outfit de verdad.
    private func materialise(_ look: StylistLook, isFavorite: Bool) -> Outfit? {
        let pieces = look.garmentIDs.compactMap { byID[$0] }
        guard !pieces.isEmpty else { return nil }
        return OutfitAssembly.make(
            from: pieces,
            name: look.headline,
            origin: .inspo,
            isFavorite: isFavorite,
            backdropRaw: nil,
            context: modelContext
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
    let isSaved: Bool
    let onSave: () -> Void
    let onPlan: () -> Void
    let onRegenerate: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        LookCanvasView(garments: garments, store: store, outfit: outfit)
            .overlay(alignment: .topTrailing) { actions }
            .contentShape(.rect)
            // **Doble toque o pulsación larga para editarlo**, los mismos dos
            // gestos que abren cualquier otro lienzo de la app. Un toque
            // simple no: pasando conjuntos con el pulgar se toca sin querer, y
            // abrir el editor por error saca de la pantalla en la que estabas.
            .onTapGesture(count: 2, perform: onEdit)
            .onLongPressGesture(perform: onEdit)
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
