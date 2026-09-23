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
/// que ves se puede guardar y editar como cualquier outfit tuyo. Y el chat no
/// habla con ningún servidor — el estilista es local y se explica: cada
/// propuesta dice por qué (ver `Stylist`).
struct InspoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    let feed: InspoFeed

    /// Todo el armario, para resolver los conjuntos a prendas de verdad.
    ///
    /// El motor trabaja con identificadores —no puede tocar SwiftData desde
    /// donde corre— y la vista necesita los modelos para pintar sus imágenes.
    /// Esta consulta es el puente, y se hace **una vez** por pantalla.
    @Query(FetchDescriptor<Garment>.visibleGarments())
    private var garments: [Garment]

    /// Lo hablado. Vacío al abrir: la pantalla empieza por los conjuntos, no
    /// por un chat en blanco pidiendo que escribas algo.
    @State private var thread: [InspoMessage] = []
    @State private var draft = ""
    /// Los conjuntos de la última petición. `nil` = los de la inspiración.
    @State private var results: [StylistLook]?
    /// El encargo vivo: cada frase se apila sobre la anterior, para que "y sin
    /// negro" siga valiendo cuando la siguiente diga "algo más abrigado".
    @State private var brief: StylistBrief?
    @State private var saved: Set<UUID> = []
    @State private var isThinking = false
    @FocusState private var isWriting: Bool

    private var shown: [StylistLook] { results ?? feed.looks }

    private var byID: [UUID: Garment] {
        Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Inspiración")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .tint(WK.Palette.primaryText)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(WKAnimation.content) {
                                results = nil
                                feed.shuffle()
                            }
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .tint(WK.Palette.primaryText)
                    }
                }
                .adaptiveSafeAreaBar(edge: .bottom) { composer }
        }
        .task {
            await feed.loadWeather()
            feed.start()
        }
    }

    @ViewBuilder
    private var content: some View {
        if shown.isEmpty {
            InspoEmptyState(hasGarments: !garments.isEmpty)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: WK.Spacing.l) {
                    carousel

                    if results != nil {
                        Button {
                            withAnimation(WKAnimation.content) { results = nil }
                        } label: {
                            Label("Volver a la inspiración", systemImage: "arrow.uturn.backward")
                                .font(WK.Font.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .padding(.horizontal, WK.Spacing.screenInset)
                    }

                    ForEach(thread) { message in
                        InspoBubble(message: message)
                            .padding(.horizontal, WK.Spacing.screenInset)
                    }

                    if isThinking {
                        ProgressView()
                            .padding(.horizontal, WK.Spacing.screenInset)
                    }
                }
                .padding(.vertical, WK.Spacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    /// Los conjuntos, uno por pantalla y deslizando de lado.
    private var carousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: WK.Spacing.m) {
                ForEach(shown) { look in
                    InspoLookCard(
                        look: look,
                        garments: look.garmentIDs.compactMap { byID[$0] },
                        store: appEnvironment.imageStore,
                        isSaved: saved.contains(look.id),
                        onSave: { save(look) },
                        onPlan: { plan(look) },
                        onDismiss: { withAnimation(WKAnimation.content) { discard(look) } }
                    )
                    .containerRelativeFrame(.horizontal, count: 1, spacing: WK.Spacing.m)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        // **El margen, como inserción del scroll y no como relleno del
        // contenido.** `containerRelativeFrame` mide el contenedor, así que
        // con el relleno por dentro cada tarjeta medía el ancho entero y se
        // salía por la derecha: los botones quedaban cortados por el borde.
        .safeAreaPadding(.horizontal, WK.Spacing.screenInset)
    }

    /// Donde se escribe. Pegado al teclado, como cualquier chat.
    private var composer: some View {
        HStack(spacing: WK.Spacing.s) {
            TextField("Pídeme un look…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($isWriting)
                .submitLabel(.send)
                .onSubmit { send() }
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .adaptiveGlass(in: .capsule)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(WK.Font.headline)
                    .foregroundStyle(WK.Palette.primaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())
            .adaptiveGlassInteractive(in: .circle)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.xs)
    }

    // MARK: Acciones

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        isWriting = false
        thread.append(InspoMessage(role: .user, text: text))

        let reading = StylistPhrase.read(
            text,
            wardrobe: feed.wardrobe(),
            base: brief ?? feed.baseBrief()
        )
        brief = reading.brief

        isThinking = true
        // Un turno de respiro: el motor tarda milisegundos, y contestar en el
        // mismo fotograma en que escribes se lee como si no hubiera mirado
        // nada. Tampoco se finge un retardo largo — no hay nada que esperar.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            let fresh = feed.looks(for: reading.brief, count: 6)
            withAnimation(WKAnimation.content) {
                results = fresh
                thread.append(
                    InspoMessage(
                        role: .stylist,
                        text: StylistPhrase.acknowledgement(reading, lookCount: fresh.count)
                    )
                )
                isThinking = false
            }
        }
    }

    /// Guardar es **hacerlo tuyo**: deja de ser una propuesta y pasa a
    /// favoritos, donde se edita como cualquier outfit.
    private func save(_ look: StylistLook) {
        let pieces = look.garmentIDs.compactMap { byID[$0] }
        guard !pieces.isEmpty else { return }
        _ = OutfitAssembly.make(
            from: pieces,
            name: look.headline,
            origin: .inspo,
            isFavorite: true,
            backdropRaw: nil,
            context: modelContext
        )
        try? modelContext.save()
        saved.insert(look.id)
    }

    /// Y además puede ir al plan de hoy, que es lo que se suele querer
    /// después de que te guste algo.
    private func plan(_ look: StylistLook) {
        let pieces = look.garmentIDs.compactMap { byID[$0] }
        guard !pieces.isEmpty else { return }
        let outfit = OutfitAssembly.make(
            from: pieces,
            name: look.headline,
            origin: .inspo,
            isFavorite: false,
            backdropRaw: nil,
            context: modelContext
        )
        let today = Calendar.current.startOfDay(for: Date())
        let existing = try? modelContext.fetch(
            FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.dayStart == today })
        )
        let day = existing?.first ?? {
            let new = PlannedDay(dayStart: today)
            modelContext.insert(new)
            return new
        }()
        outfit.plannedDay = day
        try? modelContext.save()
        saved.insert(look.id)
    }

    private func discard(_ look: StylistLook) {
        if results != nil {
            results?.removeAll { $0.id == look.id }
        } else {
            feed.dismiss(look)
        }
    }
}

/// Un mensaje del hilo.
struct InspoMessage: Identifiable, Hashable {
    enum Role { case user, stylist }
    let id = UUID()
    let role: Role
    let text: String
}

private struct InspoBubble: View {
    let message: InspoMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: WK.Spacing.xl) }
            Text(message.text)
                .font(WK.Font.body)
                .foregroundStyle(
                    message.role == .user ? WK.Palette.primaryText : WK.Palette.secondaryText
                )
                .padding(.horizontal, message.role == .user ? WK.Spacing.m : 0)
                .padding(.vertical, message.role == .user ? WK.Spacing.s : 0)
                .background {
                    if message.role == .user {
                        Capsule().fill(WK.Palette.ink(0.08))
                    }
                }
            if message.role == .stylist { Spacer(minLength: WK.Spacing.xl) }
        }
    }
}

/// Una propuesta: el lienzo, el porqué y qué hacer con ella.
private struct InspoLookCard: View {
    let look: StylistLook
    let garments: [Garment]
    let store: ImageStore
    let isSaved: Bool
    let onSave: () -> Void
    let onPlan: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            // **Con tope de alto.** Un lienzo es alto —mil por mil
            // cuatrocientos— y a ancho completo se comía la pantalla entera:
            // el conjunto se veía, pero ni el motivo ni el chat cabían debajo,
            // y esta pantalla es las dos cosas.
            LookCanvasView(garments: garments, store: store)
                .frame(maxHeight: 420)
                .overlay(alignment: .topTrailing) { actions }

            Text(look.headline)
                .font(WK.Font.headline)
                .foregroundStyle(WK.Palette.primaryText)
            // El motivo, siempre visible: una propuesta sin porqué es ropa
            // sacada al azar.
            Text(look.reason)
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
                .lineLimit(2)
        }
    }

    private var actions: some View {
        VStack(spacing: WK.Spacing.xs) {
            circle(isSaved ? "heart.fill" : "heart", action: onSave)
                .foregroundStyle(isSaved ? WK.Palette.accent : WK.Palette.primaryText)
            circle("calendar", action: onPlan)
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
