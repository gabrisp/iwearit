import PhotosUI
import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// El editor del outfit, a pantalla completa.
///
/// No es el modo por defecto: montar un outfit suele ser "esta camiseta con
/// estos pantalones", y para eso está el compositor. Esto es para colocar al
/// milímetro — y edita el mismo outfit, así que se puede ir y volver sin
/// perder nada.
struct AdvancedCanvasScreen: View {
    /// `@Bindable` y no `let`: es lo que garantiza que esta vista observe al
    /// objeto. Con un `let`, el color de fondo se escribía en el modelo pero
    /// el editor no se reevaluaba, así que el cambio solo se veía al salir y
    /// volver a entrar.
    @Bindable var outfit: Outfit
    let store: ImageStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    /// La selección vive aquí y no dentro del canvas: es lo que decide si
    /// abajo va la bandeja o las herramientas del elemento cogido.
    @State private var selection = CanvasSelection()
    /// Si la bandeja está puesta.
    ///
    /// Sigue siendo un `Bool` propio y no un caso de `Sheet`: la bandeja
    /// convive con el lienzo —no lo bloquea— y las demás hojas no, así que
    /// mezclarlas en el mismo enum obligaría a que cerrar la bandeja y abrir
    /// "más" fueran el mismo cambio de estado.
    /// Qué hay puesto en la tarjeta de abajo, si hay algo.
    ///
    /// **Una sola hoja para las dos cosas.** El color del fondo se presentaba
    /// como una hoja normal —con su panel opaco, su tamaño y sin levantar el
    /// layout— y la bandeja como tarjeta de cristal. Eran dos comportamientos
    /// distintos para dos botones que están uno al lado del otro. Ahora
    /// comparten la misma presentación y solo cambia lo que enseñan dentro.
    @State private var trayKind: TrayKind?

    /// Qué hay puesto en la bandeja.
    ///
    /// **Un caso por botón**, y no "la bandeja" con pestañas dentro: cada uno
    /// de los cuatro iconos de abajo abre lo suyo directamente. Con pestañas
    /// había que tocar dos veces —abrir la bandeja y luego cambiar de
    /// pestaña— para algo que es una sola decisión.
    private enum TrayKind: String, Identifiable, CaseIterable {
        case garments, stickers, drawing, backdrop
        var id: String { rawValue }

        /// El icono de su botón. Sin círculo propio: los cuatro comparten una
        /// sola superficie de cristal y se leen como un control, no como
        /// cuatro botones sueltos que casualmente están juntos.
        var symbol: String {
            switch self {
            case .garments: "tshirt"
            case .stickers: "face.smiling"
            case .drawing: "pencil.tip"
            // El color no usa icono: su botón **es** el color.
            case .backdrop: "paintpalette"
            }
        }
    }

    /// Lo pintado encima del outfit.
    ///
    /// Vive aquí y no dentro del lienzo: la bandeja de pintar necesita el mismo
    /// objeto para saber qué color y qué grosor están puestos, y si viviera
    /// dentro del canvas nadie de fuera podría tocarlo.
    @State private var drawing = CanvasDrawing()

    private var isTrayOpen: Bool { trayKind != nil }
    /// Lo que mide la bandeja. Lo rellena la propia hoja al medirse, y sirve
    /// para reservarle el hueco aquí fuera.
    @State private var trayHeight: CGFloat = CanvasTray.initialHeight
    @State private var editingText: TextSticker?
    /// Qué elemento del lienzo es el texto que se está editando.
    ///
    /// Aparte del sticker porque el id de un `TextSticker` sale de lo que pone
    /// —cambiaría con cada tecla— y lo que hace falta aquí es una identidad
    /// estable para no dibujarlo mientras el editor está abierto.
    @State private var editingTextItemID: PersistentIdentifier?
    @State private var photoItem: PhotosPickerItem?

    /// Qué hoja está puesta, en **un solo sitio**.
    ///
    /// Con un `.sheet(isPresented:)` por cada hoja apiladas en la misma vista,
    /// SwiftUI solo atiende a uno: el resto se quedan mudos. Por eso el color
    /// de fondo no abría nada — su `.sheet` estaba detrás del de "más".
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable {
        // `backdrop` ya no está aquí: el color del fondo se presenta en la
        // misma tarjeta de cristal que la bandeja, con `trayKind`.
        case more, place
        var id: String { rawValue }
    }

    /// El color del día lo pone el outfit, y se elige **aquí dentro**: es una
    /// decisión de cómo queda el outfit, no un ajuste de la pantalla de
    /// planificar, y tenerlo fuera obligaba a salir del editor para cambiarlo.
    /// El fondo del lienzo.
    ///
    /// En una maleta lo pone **la maleta**: es lo que la identifica entre
    /// varias, y dejar además un color por outfit daría cinco colores a un
    /// mismo viaje.
    private var backdropColor: Color {
        if let raw = outfit.suitcase?.colorRaw, let tint = SuitcaseTint(rawValue: raw) {
            return Color(
                red: tint.components.red,
                green: tint.components.green,
                blue: tint.components.blue
            )
            .opacity(0.35)
        }
        guard let components = OutfitBackdrop(rawValue: outfit.backdropRaw ?? "")?.components else {
            return WK.Palette.canvas
        }
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    private func close() {
        if trayKind != nil {
            withAnimation(WKAnimation.arrival) { trayKind = nil }
        } else {
            dismiss()
        }
    }

    private var selectedItem: CanvasItem? {
        guard let id = selection.selectedID else { return nil }
        return outfit.items.first { $0.id == id }
    }

    var body: some View {
        editor
    }

    private var editor: some View {
        ZStack {
            FreeformCanvas(
                outfit: outfit,
                store: store,
                selection: selection,
                drawing: drawing
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Fondo del contenedor, no una capa con `ignoresSafeArea` dentro del
        // `ZStack`: ver `DayPage`.
        .background(backdropColor.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        // En barra de verdad y no en una fila puesta a mano: así iOS 26 les da
        // su cristal y su difuminado del contenido que pasa por debajo, que es
        // exactamente lo que una fila propia tendría que imitar a mano.
        // Sin deshacer/rehacer.
        //
        // Nunca llegaron a hacer nada: el `undoManager` del contexto no está
        // configurado, así que los dos botones salían siempre apagados. Y
        // aunque lo estuviera, en un lienzo lo que se deshace se deshace
        // moviendo la prenda de vuelta, que es más directo que buscar una
        // flecha arriba. Si algún día hace falta, se hace con agrupación por
        // gesto —un arrastre es un paso, no sesenta— o no sirve para nada.
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { close() } label: { Image(systemName: "xmark") }
                    .tint(WK.Palette.primaryText)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: { Image(systemName: "checkmark") }
                    .tint(WK.Palette.primaryText)
                    .adaptiveProminentButton()
            }
        }
        .adaptiveSafeAreaBar(edge: .bottom) { bottom }
        // Sin gesto de volver: el editor está lleno de arrastres, y el
        // deslizamiento desde el borde izquierdo compite con colocar una
        // prenda pegada a ese borde.
        //
        // Esconder el botón **no basta**: UIKit deja el gesto activo igual.
        .navigationBarBackButtonHidden()
        .interactivePopDisabled()
        // Y los de la transición de zoom, que son **otros tres distintos** y
        // cuelgan de la vista de esta pantalla, no de la de la pila. Ver
        // `zoomDismissDisabled`: arrastrar una prenda hacia abajo cerraba el
        // editor, y el pellizco de escalar competía con el de cerrar.
        .zoomDismissDisabled()
        .interactiveDismissDisabled()
        .toolbarVisibility(.hidden, for: .tabBar)
        .animation(WKAnimation.arrival, value: selection.selectedID)
        .animation(WKAnimation.arrival, value: isTrayOpen)
        .onChange(of: selection.selectedID) { _, id in
            if id != nil { trayKind = nil }
        }
        // La pintura se carga una vez y se guarda sola en cada trazo.
        .task {
            drawing.load(from: outfit.drawingData)
            drawing.onCommit = { data in outfit.drawingData = data }
        }
        // **Pintar es un modo.** Mientras la bandeja del lápiz está puesta, el
        // dedo pinta y las prendas no se mueven; al cerrarla, al revés. Sin
        // esto, el mismo arrastre haría las dos cosas.
        .onChange(of: trayKind) { _, kind in
            drawing.isActive = kind == .drawing
            // **El hueco reservado se devuelve al cerrar.** Si no, la barra de
            // abajo se queda a la altura que tenía la bandeja más alta que se
            // abrió, y parece que se ha ido hacia abajo sola.
            if kind == nil {
                withAnimation(WKAnimation.arrival) { trayHeight = CanvasTray.initialHeight }
            }
        }
        .fullScreenCover(item: $editingText) { sticker in
            TextStickerEditor(sticker: sticker) { edited in
                commit(edited)
            }
            .presentationBackground(.clear)
            // Vuelve a su sitio al cerrarse, venga de "Listo" o de cerrar sin
            // guardar: el elemento tiene que reaparecer en los dos casos.
            .onDisappear { editingTextItemID = nil }
        }
        // **Mientras se edita un texto, el del lienzo no se dibuja.**
        //
        // El editor se presenta con el fondo transparente, así que el lienzo
        // sigue viéndose detrás — y con él, el mismo texto en su sitio. Se
        // veían dos: el de abajo quieto y el de arriba cambiando mientras
        // escribías. Ahora el texto **sale** del lienzo al abrirse el editor y
        // vuelve a su posición al cerrarse.
        .environment(\.canvasHiddenItemID, editingTextItemID.map(AnyHashable.init))
        // **Las hojas del editor, sin panel.**
        //
        // Aquí dentro todo flota sobre el lienzo: la bandeja es una tarjeta de
        // cristal, y una hoja del sistema al lado —con su superficie opaca de
        // punta a punta— se leía como si perteneciera a otra pantalla. El
        // contenido ya trae sus propias tarjetas, así que lo único que sobra es
        // el fondo.
        .sheet(item: $sheet) { which in
            editorSheet(for: which)
                .presentationBackground(.clear)
        }
        // **La bandeja, en su propia hoja y no en la de `$sheet`.**
        //
        // Dos `.sheet` en la misma vista dejan mudo a uno —es el fallo que ya
        // nos costó que el color de fondo no abriera nada—, pero este no lo es:
        // `canvasTraySheet` no es otro `.sheet` puesto al lado, es el único que
        // puede estar a la vez porque la bandeja **no bloquea el fondo**. Con
        // `presentationBackgroundInteraction` el lienzo sigue vivo debajo, así
        // que abrir "más" con la bandeja puesta cierra la bandeja primero.
        .canvasTraySheet(
            isPresented: isTrayBinding,
            height: $trayHeight,
            // **Solo las prendas se pueden subir.** Es lo único que tiene más
            // de lo que cabe; los stickers son cuatro y la pintura son tres
            // controles, y estirarlos deja un palmo de vacío debajo.
            isExpandable: trayKind == .garments
        ) {
            CanvasTray(fills: trayKind == .garments) { trayContent }
        }
        .photosPicker(isPresented: photoPickerBinding, selection: $photoItem, matching: .images)
        .task(id: photoItem) { await insertPickedPhoto() }
    }

    /// Lo que va dentro de la hoja del editor.
    ///
    /// Función aparte y no un `switch` dentro del `@ViewBuilder` del `.sheet`:
    /// así el fondo transparente se aplica **una vez**, a lo que salga, y no
    /// hay forma de añadir un caso nuevo y olvidarse de ponérselo.
    @ViewBuilder
    private func editorSheet(for which: Sheet) -> some View {
        switch which {
        case .more:
            moreSheet
        case .place:
            PlaceSearchSheet(title: "¿Dónde?") { picked in
                appEnvironment.weather.use(picked)
                // Encadenado: has dicho dónde para poner el sticker, así que se
                // pone. Obligar a volver a tocar "Tiempo" sería hacer repetir
                // el paso que acabas de completar.
                Task { await addWeather() }
            }
        }
    }

    /// Cerrar la bandeja es **también** deseleccionar nada: se cierra sola
    /// cuando se coge una prenda, y el enlace tiene que reflejar las dos vías.
    private var isTrayBinding: Binding<Bool> {
        Binding(get: { trayKind != nil }, set: { if !$0 { trayKind = nil } })
    }

    // MARK: Abajo

    /// Bandeja o herramientas, nunca las dos.
    ///
    /// Cuando tienes algo cogido, lo que quieres hacer es con **eso**; ofrecer
    /// a la vez "añade otra prenda" es ofrecer la acción equivocada en el
    /// momento exacto en que no la quieres.
    @ViewBuilder
    private var bottom: some View {
        if let item = selectedItem {
            CanvasToolbar(
                onDelete: {
                    selection.clear()
                    CanvasEditing.delete(item, in: modelContext)
                },
                onDuplicate: {
                    let copy = CanvasEditing.duplicate(item, in: outfit, context: modelContext)
                    // La copia queda **seleccionada**, y por eso se selecciona
                    // en el mismo turno y no dentro de una animación: el id
                    // cambiaba antes de que la copia existiera en la vista, y
                    // se quedaba la barra de herramientas puesta sin nada
                    // marcado debajo.
                    selection.select(copy.id)
                },
                onFlip: { CanvasEditing.flip(item) },
                onSendBackward: { CanvasEditing.restack(item, in: outfit, toFront: false) },
                onBringForward: { CanvasEditing.restack(item, in: outfit, toFront: true) },
                onMore: { openMore(for: item) }
            )
            .padding(.bottom, WK.Spacing.m)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if isTrayOpen {
            // **El mismo hueco de siempre, ahora vacío.**
            //
            // Aquí se dibujaba la bandeja. Su contenido se ha mudado a una
            // hoja —que trae el arrastre del sistema y su física—, pero el
            // sitio se sigue reservando en el mismo punto del layout: una hoja
            // se pone *encima* y no empuja nada, así que sin este hueco los
            // botones del editor se quedarían debajo de ella.
            //
            // El alto lo mide la propia hoja y llega por `trayHeight`, de modo
            // que el hueco es exactamente el que ocupa y no un número a mano.
            Color.clear
                .frame(height: trayHeight)
        } else {
            // **Cuatro iconos y el color, en una sola pieza.**
            //
            // Antes era "Agregar" con pestañas dentro, y para poner un sticker
            // había que abrir la bandeja y cambiar de pestaña: dos toques para
            // una decisión. Aquí cada icono abre lo suyo.
            AdaptiveGlassContainer(spacing: WK.Spacing.s) {
                HStack(spacing: WK.Spacing.l) {
                    ForEach([TrayKind.drawing, .garments, .stickers], id: \.self) { kind in
                        Button {
                            withAnimation(WKAnimation.arrival) { trayKind = kind }
                        } label: {
                            Image(systemName: kind.symbol)
                                .font(WK.Font.headline)
                                .foregroundStyle(
                                    trayKind == kind
                                        ? WK.Palette.accent
                                        : WK.Palette.primaryText
                                )
                                .frame(height: CanvasTray.controlHeight)
                                .contentShape(.rect)
                        }
                        .buttonStyle(WKPressStyle())
                    }

                    // El color, un círculo **con el color puesto**. Un icono de
                    // paleta obliga a abrir la hoja para saber cuál está
                    // elegido; la muestra ya lo dice.
                    //
                    // No aparece si el outfit es de una maleta: allí el color
                    // lo pone la maleta y es lo que la identifica.
                    if outfit.suitcase == nil {
                        Button {
                            withAnimation(WKAnimation.arrival) { trayKind = .backdrop }
                        } label: {
                            Circle()
                                .fill(backdropColor)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(WK.Palette.ink(0.18), lineWidth: 1))
                                .frame(height: CanvasTray.controlHeight)
                                .contentShape(.rect)
                        }
                        .buttonStyle(WKPressStyle())
                    }
                }
                .padding(.horizontal, WK.Spacing.l)
                .adaptiveGlassInteractive(in: .capsule)
            }
            .padding(.bottom, WK.Spacing.m)
            // **Sin deslizar.** Con `.move(edge: .bottom)`, al cerrar la
            // bandeja los botones entraban desde abajo: se leía como si se
            // fueran hacia abajo de más en vez de quedarse donde estaban.
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var trayContent: some View {
        switch trayKind {
        case .garments, nil:
            CanvasGarmentTray(store: store) { garment in
                CanvasEditing.insert(garment: garment, in: outfit, context: modelContext)
                withAnimation(WKAnimation.arrival) { trayKind = nil }
            }
        case .stickers:
            StickerPicker { kind in
                add(kind)
                withAnimation(WKAnimation.arrival) { trayKind = nil }
            }
        case .drawing:
            DrawingPicker(drawing: drawing)
        case .backdrop:
            BackdropPicker(outfit: outfit)
        }
    }

    // MARK: Acciones

    /// El tamaño de arranque por tipo.
    ///
    /// Una fecha y un texto no nacen del mismo tamaño: el sticker de fecha es
    /// un cuadrado pequeño y un texto necesita ancho para no partirse en la
    /// primera palabra.
    private func add(_ kind: CanvasSticker.Kind) {
        switch kind {
        case .date:
            CanvasEditing.insert(
                sticker: .date(Date()),
                size: CGSize(width: 240, height: 260),
                in: outfit,
                context: modelContext
            )
        case .text:
            editingText = TextSticker()
        case .photo:
            photoItem = nil
            isPickingPhoto = true
        case .weather:
            Task { await addWeather() }
        }
    }

    /// El tiempo del día que se está editando, en el sitio que toque.
    ///
    /// Se pide **al pegar el sticker**, no al abrir el editor: consultar el
    /// tiempo por si acaso, cada vez que alguien abre un outfit, es gastar red
    /// y batería en un dato que casi nunca se usa.
    private func addWeather() async {
        // El destino del viaje manda sobre la ciudad guardada: si esta maleta
        // va a Lisboa, el tiempo de un outfit suyo es el de Lisboa, no el de
        // casa. Es justo el caso en que la ubicación del dispositivo habría
        // dado la respuesta equivocada.
        let place = outfit.suitcase?.destination
        guard place != nil || appEnvironment.weather.place != nil else {
            sheet = .place
            return
        }
        guard let snapshot = await appEnvironment.weather.snapshot(for: outfitDate, at: place) else {
            return
        }
        CanvasEditing.insert(
            sticker: .weather(snapshot),
            size: CGSize(width: 260, height: 300),
            in: outfit,
            context: modelContext
        )
        withAnimation(WKAnimation.arrival) { trayKind = nil }
    }

    /// El día del outfit: el del calendario si está planificado, si no hoy.
    private var outfitDate: Date {
        outfit.plannedDay?.dayStart ?? Date()
    }

    private func commit(_ sticker: TextSticker) {
        // Si ya había un texto seleccionado, se edita; si no, entra uno nuevo.
        if let item = selectedItem, item.sticker?.kind == .text {
            item.apply(.text(sticker))
            return
        }
        CanvasEditing.insert(
            sticker: .text(sticker),
            size: CGSize(width: 520, height: 260),
            in: outfit,
            context: modelContext
        )
    }

    private func openMore(for item: CanvasItem) {
        // Editar un texto es lo que se quiere el 90% de las veces que se toca
        // un texto: va directo, no escondido tras el menú.
        if case let .text(sticker) = item.sticker {
            editingTextItemID = item.persistentModelID
            editingText = sticker
            return
        }
        sheet = .more
    }

    @ViewBuilder
    private var moreSheet: some View {
        WKMenuSheet(title: "Elemento", items: [
            WKMenuItem(id: "center", title: "Centrar", systemImage: "scope") {
                if let item = selectedItem { CanvasEditing.center(item) }
            },
            WKMenuItem(id: "upright", title: "Enderezar", systemImage: "arrow.counterclockwise") {
                if let item = selectedItem { CanvasEditing.straighten(item) }
            },
            WKMenuItem(id: "reset", title: "Restablecer tamaño", systemImage: "arrow.up.left.and.arrow.down.right") {
                if let item = selectedItem { CanvasEditing.resetScale(item) }
            },
        ])
    }

    // MARK: Foto

    @State private var isPickingPhoto = false

    private var photoPickerBinding: Binding<Bool> {
        Binding(get: { isPickingPhoto }, set: { isPickingPhoto = $0 })
    }

    private func insertPickedPhoto() async {
        guard let photoItem else { return }
        defer { self.photoItem = nil }
        guard
            let data = try? await photoItem.loadTransferable(type: Data.self),
            let image = UprightImage.cgImage(from: data),
            // A disco, como todo lo demás: en la base de datos solo viaja la
            // clave. Meter bytes de imagen en SwiftData infla el store y hace
            // lento cualquier fetch.
            let key = try? await store.store(image)
        else { return }

        let ratio = Double(image.height) / Double(image.width)
        CanvasEditing.insert(
            sticker: .photo(key: key),
            size: CGSize(width: 420, height: 420 * ratio),
            in: outfit,
            context: modelContext
        )
    }
}

/// Una pestaña de la bandeja sin nada dentro.
private struct CanvasTrayEmpty: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: WK.Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(WK.Palette.secondaryText)
            Text(title)
                .font(WK.Font.headline)
                .foregroundStyle(WK.Palette.primaryText)
            Text(message)
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, WK.Spacing.xl)
        .padding(.vertical, WK.Spacing.l)
    }
}

/// El armario dentro de la bandeja, **con filtros**.
///
/// ## Por qué hacen falta aquí y no en el armario
///
/// En el armario se busca mirando: las baldas ya separan, y el scroll es el
/// filtro. Aquí no cabe ninguna balda —la bandeja mide lo que mide— y montar
/// un outfit es justo lo contrario de pasear: ya sabes que quieres *unos
/// vaqueros*, y con cuarenta prendas en una rejilla de cuatro columnas eso son
/// tres pantallas de scroll para encontrar la que tienes en la cabeza.
///
/// ## Qué se filtra
///
/// Por **balda** y por **estilo**, en la misma fila y con la misma pinta,
/// porque desde donde se mira son la misma pregunta: "enséñame solo estas". La
/// balda sale de las categorías del usuario —las suyas, no una lista fija— y
/// el estilo de las etiquetas que de verdad tienen sus prendas: una lista de
/// estilos con nueve que no usa nadie estorba más que ayuda.
///
/// Selección **única**. Con filtros combinables hay que explicar qué pasa al
/// marcar dos, y en una bandeja de cuatro centímetros no hay sitio para
/// explicar nada.
private struct CanvasGarmentTray: View {
    let store: ImageStore
    let onPick: (Garment) -> Void

    // Las consultas traen el filtro de eliminadas puesto: ver
    // `FetchDescriptor.visibleGarments()` en `SoftDeletion.swift`.
    @Query(FetchDescriptor<Garment>.visibleGarments())
    private var garments: [Garment]

    @Query(FetchDescriptor<GarmentCategory>.visibleCategories())
    private var categories: [GarmentCategory]

    @State private var filter: TrayFilter = .all

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: WK.Spacing.m)]

    /// Las prendas que pasan el filtro.
    private var visible: [Garment] {
        switch filter {
        case .all:
            garments
        case let .category(slug, _):
            garments.filter { $0.category?.slug == slug }
        case let .tag(tag):
            garments.filter { $0.tags.contains(tag) }
        }
    }

    /// Solo las baldas que tienen algo. Una balda vacía en el filtro es un
    /// chip que solo sabe enseñar una rejilla en blanco.
    private var shelves: [TrayFilter] {
        categories
            .filter { !$0.isHidden && !$0.garments.isEmpty }
            .map { .category(slug: $0.slug, name: $0.name) }
    }

    /// Y los estilos que de verdad aparecen en el armario, por frecuencia.
    ///
    /// Por frecuencia y no alfabético: el estilo que más llevas es el que más
    /// veces vas a querer filtrar, y en una fila que se desplaza lo que está
    /// al final no existe.
    private var styles: [TrayFilter] {
        var counts: [String: Int] = [:]
        for garment in garments {
            for tag in garment.tags { counts[tag, default: 0] += 1 }
        }
        return counts
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(12)
            .map { .tag($0.key) }
    }

    var body: some View {
        VStack(spacing: WK.Spacing.s) {
            TrayFilterBar(
                filters: [.all] + shelves + styles,
                selection: $filter
            )

            ScrollView {
                LazyVGrid(columns: columns, spacing: WK.Spacing.m) {
                    ForEach(visible) { garment in
                        Button { onPick(garment) } label: {
                            StoredImage(
                                key: garment.normalizedImageKey,
                                variant: .thumb,
                                store: store,
                                shadow: .init(opacity: 0.5, radius: 6, y: 3)
                            )
                            .frame(height: 96)
                            .contentShape(.rect)
                        }
                        .buttonStyle(WKPressStyle())
                    }
                }
                .padding(.horizontal, WK.Spacing.m)
            }
            .scrollIndicators(.hidden)
            // **Sin el fondo del sistema.** Un `ScrollView` dentro de una hoja
            // trae su propia superficie, y sobre el cristal de la bandeja se
            // veía como un panel opaco pegado por dentro — el "background
            // interno" que no había forma de quitar desde fuera.
            .scrollContentBackground(.hidden)
            // **Sin alto forzado.** Lo tenía clavado a 220 puntos, así que
            // subir la hoja no enseñaba ni una prenda más: crecía la hoja y la
            // rejilla se quedaba igual con un hueco debajo. Ahora ocupa lo que
            // haya, que es lo que hace que subirla sirva para algo.
            .frame(maxHeight: .infinity)
            .overlay {
                if visible.isEmpty {
                    Text("Nada con este filtro")
                        .font(WK.Font.caption)
                        .foregroundStyle(WK.Palette.secondaryText)
                }
            }
        }
        // Si la balda filtrada se queda sin prendas —las has usado todas— el
        // filtro vuelve solo a "Todo" en vez de dejar una rejilla vacía que
        // parece una app rota.
        .onChange(of: visible.isEmpty) { _, isEmpty in
            if isEmpty, filter != .all { filter = .all }
        }
    }
}

/// Un filtro de la bandeja.
///
/// Un solo tipo para balda y estilo, y no dos enums paralelos: la fila los
/// pinta igual, el chip los compara igual y añadir un tercer criterio —color,
/// temporada— es un caso más aquí y nada más.
enum TrayFilter: Hashable {
    case all
    case category(slug: String, name: String)
    case tag(String)

    var label: String {
        switch self {
        case .all: "Todo"
        case let .category(_, name): name
        case let .tag(tag): tag.capitalized
        }
    }
}

/// La fila de chips. Vista propia: cambiar de filtro no tiene por qué
/// reevaluar la rejilla entera de prendas.
private struct TrayFilterBar: View {
    let filters: [TrayFilter]
    @Binding var selection: TrayFilter

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.xs) {
                ForEach(filters, id: \.self) { filter in
                    TrayFilterChip(
                        label: filter.label,
                        isSelected: filter == selection
                    ) {
                        withAnimation(WKAnimation.selection) { selection = filter }
                    }
                }
            }
            .padding(.horizontal, WK.Spacing.m)
        }
        .scrollIndicators(.hidden)
        // Con el scroll pegado al borde de la tarjeta, el primer chip parece
        // cortado; y el alto fijo evita que la bandeja cambie de tamaño al
        // aparecer o desaparecer un estilo.
        .frame(height: 36)
    }
}

private struct TrayFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(WK.Font.caption)
                .foregroundStyle(isSelected ? WK.Palette.onAccent : WK.Palette.primaryText)
                .lineLimit(1)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.xs)
                .background(
                    isSelected ? WK.Palette.accent : WK.Palette.ink(0.08),
                    in: .capsule
                )
                .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
    }
}

extension TextSticker: Identifiable {
    public var id: String { "\(string)-\(colorHex)-\(backgroundHex ?? "")-\(alignment.rawValue)" }
}
