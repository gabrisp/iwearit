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
    /// Quien sabe empujar el editor: esto es una hoja y no tiene pila. Ver
    /// `AppRouter.editFromStylist`.
    @Environment(AppRouter.self) private var router: AppRouter?

    let feed: InspoFeed

    @Query(FetchDescriptor<Garment>.visibleGarments())
    private var garments: [Garment]

    /// **Lo hablado no vive en esta hoja.**
    ///
    /// Vivía aquí, y cerrar el estilista lo borraba entero: lo que habías
    /// pedido, lo que te había propuesto y las prendas que habías adjuntado.
    /// Abrir y cerrar una hoja no es terminar una conversación. Ahora el hilo
    /// es de la app y la hoja solo lo enseña. Ver `StylistChat`.
    @Bindable var chat: StylistChat

    /// **Quién abre el editor.**
    ///
    /// Lo pide quien presenta esta hoja, en vez de buscarlo en el entorno: el
    /// lápiz de una propuesta no hacía nada, y era esto —dentro de la hoja, el
    /// router no siempre llega—. Quien la presenta sí lo tiene en la mano.
    var onEdit: ((Outfit) -> Void)?

    /// **Una sola hoja encima de esta**, con un enum: tres `.sheet` en la
    /// misma vista dejan mudos a dos. Ver `AppRouter`.
    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        /// Qué prendas se adjuntan.
        case picker
        /// Qué día te pones este conjunto.
        case day(StylistLook)
        // **El archivo ya no es una hoja.** Era una tercera capa encima de la
        // hoja del estilista, y una conversación abierta desde ahí se veía a
        // dos alturas de donde se escribe. Ahora se empuja en la pila de esta
        // misma hoja, que es lo que hace cualquier archivo: entras y vuelves.
        // case archive

        var id: String {
            switch self {
            case .picker: "picker"
            case let .day(look): "day-\(look.id)"
            }
        }
    }
    @FocusState private var isWriting: Bool
    /// Si está abierto el archivo, **en esta misma pila**.
    @State private var isShowingArchive = false

    /// Lo adjuntado, resuelto a prendas y en un orden estable.
    private var attachedGarments: [Garment] {
        chat.attached.compactMap { byID[$0] }.sorted { $0.name < $1.name }
    }

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
                    // **Otra conversación.** Sin esto el estilista es un
                    // hilo infinito: lo de la semana pasada sigue arriba y lo
                    // que pediste para hoy va detrás de todo.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(WKAnimation.content) { chat.startNew() }
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .tint(WK.Palette.primaryText)
                        .disabled(chat.isEmpty)
                    }
                    // **El archivo son los chats.** Lo hablado con el
                    // estilista no se pierde al cerrar ni al empezar otro: se
                    // queda aquí, con los conjuntos que propuso dentro.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isShowingArchive = true } label: {
                            Image(systemName: "archivebox")
                        }
                        .tint(WK.Palette.primaryText)
                    }
                }
                .navigationDestination(isPresented: $isShowingArchive) {
                    StylistArchiveScreen(chat: chat)
                }
                .adaptiveSafeAreaBar(edge: .bottom) { bottom }
                .sheet(item: $sheet) { which in
                    switch which {
                    case .picker:
                        // El armario por baldas, como al crear un outfit: ver
                        // `OutfitPickerSheet`.
                        OutfitPickerSheet(
                            mode: .many,
                            title: "Añadir prendas",
                            // Cuatro: con cinco ya está el conjunto puesto y no
                            // queda nada que proponer.
                            subtitle: "Hasta cuatro: el look se monta con ellas",
                            store: appEnvironment.imageStore,
                            limit: 4,
                            preselectedIDs: attachedGarments.map(\.persistentModelID)
                        ) { garments in
                            withAnimation(WKAnimation.content) {
                                chat.attached = Set(garments.map(\.id))
                            }
                        }
                    case let .day(look):
                        StylistDayPicker { date in
                            plan(look, on: date)
                            sheet = nil
                        }
                    }
                }
        }
    }

    private var content: some View {
        // **El índice del armario, una sola vez por pasada.**
        //
        // `byID` es una propiedad calculada: construye un diccionario con
        // todas las prendas cada vez que se lee, y se leía una vez por mensaje
        // **y otra por cada conjunto propuesto**. Con tres preguntas en el
        // hilo eso son veinte diccionarios del armario entero en cada
        // fotograma de scroll, y de ahí venía el tirón. Aquí se construye uno
        // y lo usan todos.
        let wardrobe = byID
        return ScrollView(.vertical) {
            // Perezoso: lo que no se ve no se monta. El hilo crece sin tope y
            // cada respuesta trae seis lienzos.
            LazyVStack(alignment: .leading, spacing: WK.Spacing.l) {
                if chat.thread.isEmpty {
                    // **El ejemplo se envía tal cual, sin pasar por el
                    // campo.** Escribirlo en `draft` y llamar a `send()` en el
                    // mismo turno no funciona: el estado todavía no se ha
                    // escrito cuando se lee, así que se enviaba una frase
                    // vacía y el chip parecía roto.
                    StylistPrompts { example in ask(example) }
                }

                ForEach(chat.thread) { message in
                    StylistBubble(
                        message: message,
                        garments: message.attachments.compactMap { wardrobe[$0] },
                        store: appEnvironment.imageStore
                    )
                    .padding(.horizontal, WK.Spacing.screenInset)
                    .id(message.id)

                    // **Y los conjuntos, ahí mismo.** Debajo de la respuesta
                    // que los trajo y encima de lo que preguntaste después:
                    // seis tarjetas que se pasan de lado y se quedan en el
                    // hilo para siempre. Antes vivían en una tira al final que
                    // se vaciaba con cada pregunta, así que pedir otra cosa
                    // borraba lo anterior aunque todavía lo estuvieras
                    // mirando.
                    if !message.looks.isEmpty {
                        looksStrip(message.looks, wardrobe: wardrobe)
                    }
                }

                if chat.isThinking {
                    // Sin el identificador del final: dos vistas con el mismo
                    // `id` dentro del mismo contenedor se pisan.
                    ProgressView()
                        .padding(.horizontal, WK.Spacing.screenInset)
                }

                Color.clear
                    .frame(height: 1)
                    .id(Self.bottomID)
            }
            .padding(.vertical, WK.Spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        // Lo último, a la vista: una respuesta que llega debajo del borde es
        // una respuesta que no ha llegado.
        .defaultScrollAnchor(.bottom)
    }

    /// El identificador del final del hilo, para bajar hasta ahí.
    private static let bottomID = "bottom"

    /// Lo que propuso en una respuesta, para mirarlo de lado.
    private func looksStrip(_ looks: [StylistLook], wardrobe: [UUID: Garment]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.m) {
                ForEach(looks) { look in
                    StylistResultCard(
                        garments: look.garmentIDs.compactMap { wardrobe[$0] },
                        // **Lo editado se queda en su tarjeta.** Si abriste
                        // esta propuesta en el editor y moviste cosas, lo que
                        // se ve aquí es eso, no la propuesta de antes. Igual
                        // que en la pestaña de inspiración.
                        outfit: outfit(for: look),
                        store: appEnvironment.imageStore,
                        reason: look.reason,
                        isSaved: chat.saved.contains(look.id),
                        onSave: { save(look) },
                        onPlan: { sheet = .day(look) },
                        onEdit: { edit(look) },
                        onDislike: { dislike(look) }
                    )
                    .containerRelativeFrame(.horizontal, count: 3, span: 2, spacing: WK.Spacing.m)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .safeAreaPadding(.horizontal, WK.Spacing.screenInset)
        .scrollClipDisabled()
    }

    /// Abajo: lo adjuntado y el campo.
    private var bottom: some View {
        VStack(spacing: WK.Spacing.s) {
            if !chat.attached.isEmpty { attachments }
            composer
        }
        .animation(WKAnimation.content, value: chat.attached)
    }

    /// Las prendas adjuntas, en píldoras y con su recorte dentro.
    private var attachments: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.s) {
                ForEach(attachedGarments, id: \.persistentModelID) { garment in
                    Button { detach(garment) } label: {
                        HStack(spacing: WK.Spacing.xs) {
                            StoredImage(
                                key: garment.normalizedImageKey,
                                variant: .thumb,
                                store: appEnvironment.imageStore
                            )
                            .frame(width: 26, height: 26)

                            Text(garment.name)
                                .font(WK.Font.caption)
                                .foregroundStyle(WK.Palette.primaryText)
                                .lineLimit(1)

                            // La equis dentro de la propia píldora: quitar una
                            // prenda es tocarla, no volver al selector.
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(WK.Palette.secondaryText)
                        }
                        .padding(.leading, WK.Spacing.xs)
                        .padding(.trailing, WK.Spacing.s)
                        .padding(.vertical, WK.Spacing.xs)
                        .adaptiveGlass(in: .capsule)
                        .fixedSize()
                    }
                    .buttonStyle(WKPressStyle())
                }
            }
        }
        .scrollIndicators(.hidden)
        .safeAreaPadding(.horizontal, WK.Spacing.screenInset)
        .scrollClipDisabled()
    }

    private var composer: some View {
        // **Lo que escribes no repinta el hilo.**
        //
        // El campo estaba atado a `chat.draft`, así que cada tecla cambiaba el
        // objeto observado y con él la hoja entera: las burbujas, los lienzos
        // de cada propuesta, todo. Ahora el texto vive en el campo y solo sale
        // de él al enviar —o al cerrar, para no perder lo empezado—.
        StylistComposer(
            initialText: chat.draft,
            hasAttachments: !chat.attached.isEmpty,
            isWriting: $isWriting,
            onPlus: { sheet = .picker },
            onSend: { text in ask(text) },
            onStash: { text in chat.draft = text }
        )
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.xs)
    }

    // MARK: Acciones

    /// Quita una prenda de las adjuntas.
    ///
    /// En su propio método y no dentro del botón: `Set.remove` devuelve lo que
    /// quitó, así que dentro de un `withAnimation` el cierre deja de ser
    /// `Void` y el compilador se pierde en la vista entera.
    private func detach(_ garment: Garment) {
        withAnimation(WKAnimation.content) {
            _ = chat.attached.remove(garment.id)
        }
    }

    private func ask(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chat.draft = ""
        let sent = Array(chat.attached)
        chat.append(StylistMessage(role: .user, text: text, attachments: sent))

        var base = chat.brief ?? feed.baseBrief()
        // Lo adjuntado **manda**: son las prendas que has señalado, y van
        // puestas en todo lo que se proponga.
        base.pinned = chat.attached
        let reading = StylistPhrase.read(text, wardrobe: feed.wardrobe(), base: base)
        chat.brief = reading.brief
        chat.isThinking = true
        // **El campo se queda limpio.** Lo adjuntado ya viaja en el mensaje y
        // en el encargo; dejarlo puesto hace que la siguiente pregunta arrastre
        // prendas que creías haber soltado al enviar.
        withAnimation(WKAnimation.content) { chat.attached.removeAll() }

        // Un turno de respiro: el motor tarda milisegundos, y contestar en el
        // mismo fotograma en que escribes se lee como si no hubiera mirado
        // nada. Tampoco se finge un retardo largo — no hay nada que esperar.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            let fresh = feed.looks(for: reading.brief, count: 6)
            let reply = StylistMessage(
                role: .stylist,
                text: StylistPhrase.acknowledgement(reading, lookCount: fresh.count),
                looks: fresh
            )
            withAnimation(WKAnimation.content) {
                chat.append(reply)
                chat.isThinking = false
            }
        }
    }

    private func save(_ look: StylistLook) {
        // El de siempre si ya existe —lo editaste y lo estás guardando—, y uno
        // nuevo si no. Crear otro dejaría dos: el que tocaste y el que se
        // guarda.
        let outfit = outfit(for: look) ?? materialise(look, isFavorite: true)
        guard let outfit else { return }
        outfit.isFavorite = true
        try? modelContext.save()
        feed.remember(outfit, for: look)
        chat.saved.insert(look.id)
    }

    private func plan(_ look: StylistLook, on date: Date) {
        let existingOutfit = outfit(for: look) ?? materialise(look, isFavorite: false)
        guard let outfit = existingOutfit else { return }
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
        chat.saved.insert(look.id)
    }

    /// Abre el conjunto en el editor: se cierra el estilista, se empuja el
    /// editor y al volver la conversación sigue donde estaba.
    private func edit(_ look: StylistLook) {
        let existing = outfit(for: look) ?? materialise(look, isFavorite: false)
        guard let outfit = existing else { return }
        try? modelContext.save()
        // **Se apunta cuál es el suyo.** Sin esto, lo que hicieras en el
        // editor no volvía a ninguna parte: la tarjeta seguía enseñando la
        // propuesta original y el outfit editado se quedaba sin sitio —ni en
        // favoritos, ni en un día, ni en el chat—. Ahora la tarjeta lo enseña,
        // y guardarlo o ponerle fecha guarda **ese**.
        feed.remember(outfit, for: look)
        if let onEdit {
            onEdit(outfit)
        } else {
            router?.editFromStylist(outfit)
        }
    }

    /// No me gusta: fuera de aquí y anotado para lo que venga.
    private func dislike(_ look: StylistLook) {
        feed.dislike(look)
        withAnimation(WKAnimation.content) { chat.removeLook(look.id) }
    }

    /// El outfit de verdad de una propuesta, si ya se hizo uno y sigue vivo.
    private func outfit(for look: StylistLook) -> Outfit? {
        guard let id = feed.outfitID(for: look) else { return nil }
        guard let outfit: Outfit = modelContext.registeredModel(for: id) else { return nil }
        // Descartado en el editor: vuelve a enseñarse la propuesta.
        guard outfit.deletedAt == nil, outfit.modelContext != nil else { return nil }
        return outfit
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

private struct StylistBubble: View {
    let message: StylistMessage
    /// Lo que iba adjunto, si iba algo.
    var garments: [Garment] = []
    var store: ImageStore?

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: WK.Spacing.xl) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: WK.Spacing.xs) {
                // Las prendas con las que se pidió, encima de lo que se dijo:
                // es el orden en que se hizo.
                if !garments.isEmpty, let store {
                    HStack(spacing: WK.Spacing.xs) {
                        ForEach(garments, id: \.persistentModelID) { garment in
                            StoredImage(
                                key: garment.normalizedImageKey,
                                variant: .thumb,
                                store: store
                            )
                            .frame(width: 36, height: 36)
                            .padding(WK.Spacing.xs)
                            .background(WK.Palette.ink(0.06), in: .circle)
                        }
                    }
                }

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
                .padding(.horizontal, WK.Spacing.screenInset)

            ScrollView(.horizontal) {
                HStack(spacing: WK.Spacing.s) {
                    ForEach(examples, id: \.self) { example in
                        Button { onPick(example) } label: {
                            Text(example)
                                .font(WK.Font.caption)
                                .foregroundStyle(WK.Palette.primaryText)
                                .fixedSize()
                                .padding(.horizontal, WK.Spacing.m)
                                .padding(.vertical, WK.Spacing.s)
                                .adaptiveGlass(in: .capsule)
                        }
                        .buttonStyle(WKPressStyle())
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            // **Sin recortar las píldoras.** El margen va como inserción del
            // scroll y no como relleno de fuera: puesto fuera, la fila medía
            // menos que la pantalla y la última píldora salía cortada por la
            // mitad, con su cristal partido.
            .safeAreaPadding(.horizontal, WK.Spacing.screenInset)
            .scrollClipDisabled()
        }
    }
}

/// Un conjunto propuesto en el chat: se mira, se guarda o se le pone día.
private struct StylistResultCard: View {
    let garments: [Garment]
    /// El outfit de verdad, si esta propuesta ya se convirtió en uno.
    var outfit: Outfit?
    let store: ImageStore
    let reason: String
    let isSaved: Bool
    let onSave: () -> Void
    let onPlan: () -> Void
    let onEdit: () -> Void
    let onDislike: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.xs) {
            LookCanvasView(garments: garments, store: store, outfit: outfit, showsBorder: true)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: WK.Spacing.xs) {
                        circle(isSaved ? "heart.fill" : "heart", action: onSave)
                            .foregroundStyle(isSaved ? WK.Palette.accent : WK.Palette.primaryText)
                        circle("calendar", action: onPlan)
                        // **El lápiz hace lo mismo que el doble toque.** Los
                        // dos gestos están bien para quien los conoce; el
                        // botón está para quien no.
                        circle("pencil", action: onEdit)
                    }
                    // El mismo aire que en la inspiración: pegados al canto se
                    // leen como si se salieran de la tarjeta.
                    .padding(WK.Spacing.s)
                }
                .contentShape(.rect)
                .onTapGesture(count: 2, perform: onEdit)
                // **Y mantener pulsado, las mismas acciones escritas.**
                //
                // Aquí sí y en la inspiración no: allí cada conjunto tiene sus
                // cuatro botones al lado y el arrastre a los lados, así que un
                // menú encima sería una tercera forma de hacer lo mismo. En el
                // chat las tarjetas son pequeñas y solo caben tres iconos.
                .contextMenu {
                    Button { onSave() } label: {
                        Label(isSaved ? "Guardado" : "Guardar en favoritos", systemImage: "heart")
                    }
                    Button { onPlan() } label: {
                        Label("Añadir a un día", systemImage: "calendar")
                    }
                    Button { onEdit() } label: {
                        Label("Editar", systemImage: "pencil")
                    }
                    Button(role: .destructive) { onDislike() } label: {
                        Label("No me gusta", systemImage: "hand.thumbsdown")
                    }
                }

            // Aquí sí se cuenta el porqué: has preguntado tú.
            Text(reason)
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
                .lineLimit(2)
        }
    }

    /// La misma medida que en la inspiración: ver `WKCircleButton`.
    private func circle(_ symbol: String, action: @escaping () -> Void) -> some View {
        WKCircleButton(symbol, size: .compact, action: action)
            .tint(WK.Palette.primaryText)
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


/// El campo de escribir, **con su propio texto**.
///
/// Vive aparte por rendimiento: mientras escribes, lo único que cambia es esta
/// vista. Lo escrito se devuelve al chat al enviar y al desaparecer, así que
/// cerrar la hoja a mitad de frase sigue sin perderla.
private struct StylistComposer: View {
    let initialText: String
    let hasAttachments: Bool
    @FocusState.Binding var isWriting: Bool
    let onPlus: () -> Void
    let onSend: (String) -> Void
    /// Para guardar lo empezado cuando la hoja se va.
    let onStash: (String) -> Void

    @State private var text: String = ""

    var body: some View {
        HStack(spacing: WK.Spacing.s) {
            // El "+" primero, como en cualquier chat: lo que se adjunta va
            // antes de lo que se escribe.
            // Siempre el mismo símbolo: un "+" que cambia de forma al adjuntar
            // se lee como otro botón. Lo que dice que hay algo puesto son las
            // píldoras de encima, que están para eso.
            WKCircleButton("plus", action: onPlus)
                .tint(hasAttachments ? WK.Palette.accent : WK.Palette.primaryText)

            TextField("Pídeme un look…", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .focused($isWriting)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .adaptiveGlass(in: .capsule)

            WKCircleButton("arrow.up", action: send)
                .tint(WK.Palette.primaryText)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { if text.isEmpty { text = initialText } }
        .onDisappear { onStash(text) }
    }

    private func send() {
        isWriting = false
        let outgoing = text
        text = ""
        onSend(outgoing)
    }
}
