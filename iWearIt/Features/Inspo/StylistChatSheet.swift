import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// Pedirle un conjunto al estilista **con palabras**.
///
/// ## Por qué es una hoja y la inspiración no
///
/// Porque son dos cosas distintas: la inspiración se pasa —está ahí, se
/// rehace sola, se mira— y esto se abre para pedir algo concreto y se cierra
/// cuando ya lo tienes. Una pestaña para lo primero y una hoja para lo
/// segundo es exactamente la diferencia entre mirar el escaparate y preguntar
/// en el mostrador.
///
/// ## Y no habla con ningún servidor
///
/// El estilista es local: reconoce colores, ocasiones, el frío que hace y las
/// prendas de tu armario que nombres, y monta con lo que tienes (ver
/// `StylistPhrase` y `Stylist`). Cuando no entiende algo lo dice, en vez de
/// contestar algo convincente.
struct StylistChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    let feed: InspoFeed

    @Query(FetchDescriptor<Garment>.visibleGarments())
    private var garments: [Garment]

    @State private var thread: [StylistMessage] = []
    @State private var draft = ""
    /// Los conjuntos de la última petición.
    @State private var results: [StylistLook] = []
    /// El encargo vivo: cada frase se apila sobre la anterior, para que "y sin
    /// negro" siga valiendo cuando la siguiente diga "algo más abrigado".
    @State private var brief: StylistBrief?
    @State private var saved: Set<UUID> = []
    @State private var isThinking = false
    @State private var datingLook: StylistLook?
    @FocusState private var isWriting: Bool

    private var byID: [UUID: Garment] {
        Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Estilista")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .tint(WK.Palette.primaryText)
                    }
                }
                .adaptiveSafeAreaBar(edge: .bottom) { composer }
                .sheet(item: $datingLook) { look in
                    StylistDayPicker { date in
                        plan(look, on: date)
                        datingLook = nil
                    }
                }
        }
    }

    private var content: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: WK.Spacing.l) {
                if thread.isEmpty {
                    // **El ejemplo se envía tal cual, sin pasar por el
                    // campo.** Escribirlo en `draft` y llamar a `send()` en el
                    // mismo turno no funciona: el estado todavía no se ha
                    // escrito cuando se lee, así que se enviaba una frase
                    // vacía y el chip parecía roto.
                    StylistPrompts { example in ask(example) }
                }

                ForEach(thread) { message in
                    StylistBubble(message: message)
                        .padding(.horizontal, WK.Spacing.screenInset)
                }

                if isThinking {
                    ProgressView()
                        .padding(.horizontal, WK.Spacing.screenInset)
                }

                if !results.isEmpty {
                    resultsStrip
                }
            }
            .padding(.vertical, WK.Spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Lo que ha propuesto, para mirarlo de lado.
    private var resultsStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.m) {
                ForEach(results) { look in
                    StylistResultCard(
                        garments: look.garmentIDs.compactMap { byID[$0] },
                        store: appEnvironment.imageStore,
                        reason: look.reason,
                        isSaved: saved.contains(look.id),
                        onSave: { save(look) },
                        onPlan: { datingLook = look }
                    )
                    .containerRelativeFrame(.horizontal, count: 3, span: 2, spacing: WK.Spacing.m)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .safeAreaPadding(.horizontal, WK.Spacing.screenInset)
    }

    private var composer: some View {
        HStack(spacing: WK.Spacing.s) {
            TextField("Pídeme un look…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($isWriting)
                .submitLabel(.send)
                .onSubmit {
                    isWriting = false
                    send()
                }
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .adaptiveGlass(in: .capsule)

            Button {
                isWriting = false
                send()
            } label: {
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
        ask(draft)
    }

    private func ask(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        thread.append(StylistMessage(role: .user, text: text))

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
                    StylistMessage(
                        role: .stylist,
                        text: StylistPhrase.acknowledgement(reading, lookCount: fresh.count)
                    )
                )
                isThinking = false
            }
        }
    }

    private func save(_ look: StylistLook) {
        guard let outfit = materialise(look, isFavorite: true) else { return }
        _ = outfit
        try? modelContext.save()
        saved.insert(look.id)
    }

    private func plan(_ look: StylistLook, on date: Date) {
        guard let outfit = materialise(look, isFavorite: false) else { return }
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
        saved.insert(look.id)
    }

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

/// Un mensaje del hilo.
struct StylistMessage: Identifiable, Hashable {
    enum Role { case user, stylist }
    let id = UUID()
    let role: Role
    let text: String
}

private struct StylistBubble: View {
    let message: StylistMessage

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

/// Qué se le puede pedir, cuando todavía no se le ha pedido nada.
///
/// Un chat en blanco no dice qué entiende, y aquí entiende cosas concretas:
/// colores, ocasiones, frío y prendas tuyas. Cuatro ejemplos ahorran la
/// primera pregunta que no lleva a ninguna parte.
private struct StylistPrompts: View {
    let onPick: (String) -> Void

    private let examples = [
        "Algo para el trabajo",
        "Sin negro",
        "Algo más abrigado",
        "Otro pantalón",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            Text("Pídeme por color, por ocasión o por una prenda tuya.")
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)

            ScrollView(.horizontal) {
                HStack(spacing: WK.Spacing.s) {
                    ForEach(examples, id: \.self) { example in
                        Button { onPick(example) } label: {
                            Text(example)
                                .font(WK.Font.caption)
                                .foregroundStyle(WK.Palette.primaryText)
                                .padding(.horizontal, WK.Spacing.m)
                                .padding(.vertical, WK.Spacing.s)
                                .adaptiveGlass(in: .capsule)
                        }
                        .buttonStyle(WKPressStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
    }
}

/// Un conjunto propuesto en el chat: se mira, se guarda o se le pone día.
private struct StylistResultCard: View {
    let garments: [Garment]
    let store: ImageStore
    let reason: String
    let isSaved: Bool
    let onSave: () -> Void
    let onPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.xs) {
            LookCanvasView(garments: garments, store: store)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: WK.Spacing.xs) {
                        circle(isSaved ? "heart.fill" : "heart", action: onSave)
                            .foregroundStyle(isSaved ? WK.Palette.accent : WK.Palette.primaryText)
                        circle("calendar", action: onPlan)
                    }
                    .padding(WK.Spacing.xs)
                }

            // Aquí sí se cuenta el porqué: has preguntado tú.
            Text(reason)
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
                .lineLimit(2)
        }
    }

    private func circle(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 30, height: 30)
                .contentShape(.circle)
        }
        .buttonStyle(WKPressStyle())
        .tint(WK.Palette.primaryText)
        .adaptiveGlassInteractive(in: .circle)
    }
}

/// Qué día te lo vas a poner.
struct StylistDayPicker: View {
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            DatePicker("Día", selection: $date, displayedComponents: [.date])
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
