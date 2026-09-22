import PhotosUI
import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// El editor del outfit, a pantalla completa.
///
/// **Edita en vivo pero no guarda hasta que confirmas.**
///
/// Las dos cosas a la vez, que parecían incompatibles y no lo son. Antes esto
/// abría un `ModelContext` aparte: nada se guardaba hasta el check —bien— pero
/// el plan y la rejilla no se enteraban de nada hasta mucho después, porque la
/// copia que tenían en memoria seguía siendo la de antes.
///
/// La forma correcta es más simple: **el mismo contexto de siempre, con el
/// autoguardado apagado**. Todo lo que pasa aquí se ve al instante en toda la
/// app —es literalmente el mismo objeto— y no toca el almacén, ni por tanto
/// iCloud, hasta que se llama a `save()`. Y descartar es `rollback()`, que es
/// exactamente para lo que existe.
struct AdvancedCanvasScreen: View {
    let outfit: Outfit
    let store: ImageStore
    /// El outfit **se acaba de crear para esto**.
    ///
    /// Importa al descartar: si venías de "crear outfit", descartar los
    /// cambios tiene que llevarse también el outfit. Si solo estabas editando
    /// uno que ya existía, descartar deja las cosas como estaban y el outfit
    /// sigue ahí.
    var isNew = false

    @Environment(\.modelContext) private var modelContext
    @State private var session: CanvasEditingSession?

    var body: some View {
        Group {
            if let session {
                CanvasEditorScreen(outfit: outfit, store: store, session: session)
            } else {
                // Un instante, mientras se prepara la sesión. Del color del
                // lienzo para que no se vea un parpadeo blanco al entrar.
                WK.Palette.canvas.ignoresSafeArea()
            }
        }
        .task {
            guard session == nil else { return }
            session = CanvasEditingSession(
                holding: modelContext,
                outfit: outfit,
                isNew: isNew
            )
        }
    }
}

/// Mientras el editor está abierto, el contexto no se guarda solo.
///
/// Un objeto y no un par de llamadas sueltas porque lo que importa es que el
/// autoguardado **vuelva a encenderse** pase lo que pase: al confirmar, al
/// descartar y al soltarse la pantalla. Dejarlo apagado por un camino olvidado
/// sería perder cambios de otra pantalla sin que nadie sepa por qué.
@MainActor
final class CanvasEditingSession {
    private let context: ModelContext
    private let outfit: Outfit
    private let isNew: Bool

    init(holding context: ModelContext, outfit: Outfit, isNew: Bool) {
        // **Sin guardar al entrar.** Lo hacía para que un contexto aparte
        // pudiera ver el outfit recién creado, y ese contexto ya no existe.
        // Lo que sí hacía era volver permanente el outfit vacío que acababa de
        // crear "crear outfit": después, descartar no tenía nada que tirar y
        // el outfit se quedaba.
        context.autosaveEnabled = false
        self.context = context
        self.outfit = outfit
        self.isNew = isNew
    }

    deinit {
        // Se ejecuta en el `MainActor` porque la clase entera lo es.
        MainActor.assumeIsolated { context.autosaveEnabled = true }
    }

    /// Si hay algo que perder. Es lo que decide si la X pregunta o se limita
    /// a cerrar: un "¿seguro?" cuando no has tocado nada enseña a confirmar
    /// sin leer.
    ///
    /// Un outfit recién creado cuenta **siempre** como algo que perder: aunque
    /// no hayas movido nada, salir sin querer lo dejaría puesto en el día.
    var hasChanges: Bool { isNew || context.hasChanges }

    /// Lo hecho aquí pasa a ser lo que hay. **Una escritura, no cincuenta.**
    func commit() {
        try? context.save()
        context.autosaveEnabled = true
    }

    /// Descartar.
    ///
    /// Si el outfit venía de antes, basta con tirar lo que no se ha guardado.
    /// Si se creó para esta sesión, **se borra**: descartar los cambios de algo
    /// que no existía hace un minuto es que no exista.
    ///
    /// El borrado explícito y no confiando en que `rollback()` se lleve lo
    /// insertado: entre crear el outfit y abrir el editor pasa un turno con el
    /// autoguardado todavía encendido, así que puede haberse guardado ya. Un
    /// `delete` funciona en los dos casos.
    func discard() {
        if isNew {
            context.delete(outfit)
            try? context.save()
        } else {
            context.rollback()
        }
        context.autosaveEnabled = true
    }
}

/// El lienzo y sus controles.
///
/// No es el modo por defecto: montar un outfit suele ser "esta camiseta con
/// estos pantalones", y para eso está el compositor. Esto es para colocar al
/// milímetro.
private struct CanvasEditorScreen: View {
    /// `@Bindable` y no `let`: es lo que garantiza que esta vista observe al
    /// objeto. Con un `let`, el color de fondo se escribía en el modelo pero
    /// el editor no se reevaluaba, así que el cambio solo se veía al salir y
    /// volver a entrar.
    @Bindable var outfit: Outfit
    let store: ImageStore
    /// Quién guarda y quién sabe si hay algo que guardar.
    let session: CanvasEditingSession

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
    @State private var isConfirmingDiscard = false
    @State private var history = CanvasHistory()

    /// Cómo está el lienzo ahora mismo.
    private var snapshot: CanvasSnapshot { CanvasSnapshot(outfit) }

    private var isTrayOpen: Bool { trayKind != nil }

    /// El lado de cada botón redondo de abajo.
    ///
    /// El mismo que la barra de pestañas —su alto más su margen— porque son
    /// la misma clase de cosa en el mismo sitio de la pantalla.
    private static var controlSide: CGFloat {
        WKTabBarMetrics.barHeight + 2 * WK.Spacing.xs
    }
    /// Lo que mide la bandeja.
    ///
    /// Solo para decirle su alto a la hoja. **Ya no reserva hueco en el
    /// editor**: reservarlo era lo que movía los botones de abajo cada vez que
    /// se abría o cerraba algo, y al cerrarse dejaba la barra colocada donde
    /// estaba la bandeja más alta —fuera de la pantalla y sin responder—.
    /// Ahora los controles no se mueven nunca: la bandeja se pone encima.
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

    private func undo() {
        guard let previous = history.undo(from: snapshot) else { return }
        apply(previous)
    }

    private func redo() {
        guard let next = history.redo(from: snapshot) else { return }
        apply(next)
    }

    /// Escribe una instantánea en el lienzo **sin que cuente como un paso
    /// nuevo**: es el propio deshacer, y apuntarlo dejaría un bucle del que no
    /// se sale.
    private func apply(_ state: CanvasSnapshot) {
        selection.clear()
        history.willApply(state)
        withAnimation(WKAnimation.content) {
            state.restore(into: outfit, context: modelContext)
        }
        // La pintura vive además en memoria, en su propio objeto: sin esto, el
        // lienzo volvía atrás y los trazos se quedaban donde estaban.
        drawing.load(from: outfit.drawingData)
    }

    /// Guardar y salir.
    private func finish() {
        session.commit()
        closeEverything()
        dismiss()
    }

    /// **Todo lo que esté abierto encima, cerrado.**
    ///
    /// Al salir, una hoja que sigue puesta se lleva por delante la animación
    /// de vuelta: la pantalla se va y la bandeja se queda un instante flotando
    /// sobre el plan, o peor, se cierra después y parece que algo ha vuelto a
    /// abrirse. Se cierran aquí, en el mismo turno en que se decide salir.
    private func closeEverything() {
        trayKind = nil
        sheet = nil
        editingText = nil
        editingTextItemID = nil
        photoItem = nil
        selection.clear()
    }

    private func close() {
        if trayKind != nil {
            withAnimation(WKAnimation.arrival) { trayKind = nil }
            return
        }
        // **Preguntar solo si hay algo que perder.** Un "¿seguro?" cuando no
        // has tocado nada no protege de nada: enseña a confirmar sin leer, y
        // el día que sí haya cambios el aviso ya no dice nada.
        if session.hasChanges {
            isConfirmingDiscard = true
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { close() } label: { Image(systemName: "xmark") }
                    .tint(WK.Palette.primaryText)
            }
            // **Deshacer y rehacer, arriba y en el centro.**
            //
            // Ahora sí: el historial es el del contexto de la sesión, que no
            // sincroniza nada hasta el check. Puesto en el contexto de la app
            // —que es lo que probamos antes— el editor ni se abría.
            ToolbarItem(placement: .principal) {
                HStack(spacing: WK.Spacing.l) {
                    Button { undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!history.canUndo)

                    Button { redo() } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!history.canRedo)
                }
                .tint(WK.Palette.primaryText)
            }
            ToolbarItem(placement: .topBarTrailing) {
                // **Aquí es donde se guarda.** Hasta este toque, nada de lo
                // hecho existe fuera del editor.
                Button { finish() } label: {
                    Image(systemName: "checkmark")
                }
                .tint(WK.Palette.primaryText)
                .adaptiveProminentButton()
            }
        }
        // **Sin `UndoManager` en el contexto.** Ponerlo aquí —aunque fuera
        // solo mientras el editor está abierto— tiraba la pantalla al
        // aparecer: el contexto es el mismo que respalda la sincronización con
        // iCloud, y registrar cada cambio para deshacerlo por encima de eso no
        // sale gratis. El editor dejó de abrirse, en revista y en rejilla.
        //
        // Los dos botones siguen ahí y siguen apagados, que es lo honesto
        // hasta que el historial sea del lienzo y no de la base de datos: una
        // pila de transformaciones propia, que es lo único que se puede
        // deshacer sin tocar el contexto compartido.
        // **El historial se apunta solo.**
        //
        // En vez de enganchar cada acción —mover, borrar, pintar, cambiar el
        // color del fondo, que además se escribe desde otra vista— se mira el
        // lienzo entero: cuando cambia, lo de antes pasa a la pila. Así no hay
        // forma de que una acción nueva se quede sin registrar, que es
        // exactamente lo que deja un deshacer a medias.
        .onChange(of: snapshot) { previous, current in
            history.record(previous, current: current)
        }
        // Descartar es **no guardar**: el contexto de la sesión se va con la
        // pantalla y se lleva los cambios con él. Por eso la pregunta puede
        // prometer lo que promete.
        .alert("¿Descartar los cambios?", isPresented: $isConfirmingDiscard) {
            Button("Descartar", role: .destructive) {
                session.discard()
                closeEverything()
                dismiss()
            }
            Button("Seguir editando", role: .cancel) {}
        } message: {
            Text("Se perderá todo lo que hayas hecho desde que abriste el editor.")
        }
        // **Con la bandeja puesta, la barra se apaga y deja su hueco.**
        //
        // Las dos mitades importan. Apagarla porque debajo de la bandeja no
        // hace nada: se ve un borde de cristal asomando bajo otro cristal, y
        // los botones que asoman no se pueden tocar. Y **dejar el hueco**
        // porque quitarla del árbol devuelve al lienzo los puntos que ocupaba,
        // así que el contenido daba un salto al abrir la bandeja y otro al
        // cerrarla — que es justo por lo que los controles acababan en otro
        // sitio del que estaban.
        //
        // Sigue siendo la misma vista, con el mismo alto: lo único que cambia
        // es que no se ve y no recibe toques. Un `Color.clear` medido a mano
        // sería lo mismo con una medida que puede quedarse desfasada.
        .adaptiveSafeAreaBar(edge: .bottom) {
            bottom
                .opacity(isTrayOpen ? 0 : 1)
                .allowsHitTesting(!isTrayOpen)
                .animation(WKAnimation.selection, value: isTrayOpen)
        }
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
        Binding(get: { isTrayOpen }, set: { if !$0 { trayKind = nil } })
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
        } else {
            // **Cuatro iconos y el color, en una sola pieza.**
            //
            // Antes era "Agregar" con pestañas dentro, y para poner un sticker
            // había que abrir la bandeja y cambiar de pestaña: dos toques para
            // una decisión. Aquí cada icono abre lo suyo.
            // **Un botón, un círculo.**
            //
            // Antes los cuatro compartían una sola cápsula, y eso los
            // convertía en un control segmentado: parecía que elegías una de
            // cuatro opciones excluyentes de lo mismo. No lo son — pintar,
            // añadir prendas, poner un sticker y cambiar el color son cuatro
            // acciones distintas que da la casualidad de que están juntas.
            //
            // Sueltos y sin contenedor de cristal compartido, además, no se
            // funden entre ellos: el contenedor une las superficies vecinas, y
            // eso es justo lo que hacía que el relleno de una pareciera
            // derramarse sobre la de al lado.
            HStack(spacing: WK.Spacing.s) {
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
                            // **El mismo alto que la barra de pestañas.** Los
                            // dos son la fila de controles de su pantalla y
                            // están a la misma altura de la mano: con medidas
                            // distintas, pasar de una a otra se nota como un
                            // salto.
                            .frame(width: Self.controlSide, height: Self.controlSide)
                            .contentShape(.circle)
                    }
                    .buttonStyle(WKPressStyle())
                    .adaptiveGlassInteractive(in: .circle)
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
                            .frame(width: Self.controlSide, height: Self.controlSide)
                            .contentShape(.circle)
                    }
                    .buttonStyle(WKPressStyle())
                    .adaptiveGlassInteractive(in: .circle)
                }
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
                // **El día que estás editando, no hoy.** Pegabas la fecha en
                // el outfit del jueves y salía la de hoy, que es justo el dato
                // que el sticker existe para decir.
                sticker: .date(editedDate),
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

    /// Qué día es este outfit.
    ///
    /// El del plan si cuelga de un día. En una maleta no hay día que sacar del
    /// propio outfit —el viaje sabe qué día ocupa cada uno, pero el outfit no
    /// sabe su índice—, así que ahí se queda la fecha de hoy hasta que haga
    /// falta lo contrario.
    private var editedDate: Date {
        outfit.plannedDay?.dayStart ?? Date()
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

    /// **Varios a la vez.** Vacío = todo el armario.
    ///
    /// Antes era uno solo, y eso convertía cada filtro en un callejón:
    /// elegías "camisetas" y dejabas de ver todo lo demás, cuando lo normal
    /// es querer camisetas **y** pantalones para montar el conjunto.
    @State private var filters: Set<TrayFilter> = []

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: WK.Spacing.m)]

    /// Las prendas que pasan el filtro.
    private var visible: [Garment] {
        // **O dentro de cada sección, Y entre secciones.**
        //
        // "Camisetas o pantalones" es una lista; "camisetas y negro" es un
        // cruce. Es como funciona cualquier filtro de tienda y es lo que la
        // gente espera sin que nadie se lo explique.
        let shelfSlugs = Set(filters.compactMap { filter -> String? in
            if case let .category(slug, _) = filter { return slug }
            return nil
        })
        let parts = Set(filters.compactMap { filter -> GarmentKind? in
            if case let .part(kind) = filter { return kind }
            return nil
        })
        let colorKeys = Set(filters.compactMap(\.colorKey))
        let tags = Set(filters.compactMap { filter -> String? in
            if case let .tag(tag) = filter { return tag }
            return nil
        })

        var result = garments
        if !parts.isEmpty {
            result = result.filter { parts.contains($0.kind) }
        }
        if !shelfSlugs.isEmpty {
            result = result.filter { shelfSlugs.contains($0.category?.slug ?? "") }
        }
        if !colorKeys.isEmpty {
            result = result.filter { garment in
                garment.colors.contains { colorKeys.contains($0.nameKey) }
            }
        }
        if !tags.isEmpty {
            result = result.filter { !tags.isDisjoint(with: $0.tags) }
        }
        if filters.contains(.recent) {
            // Por lo último que pasó con ella: puesta o metida. Doce, que es
            // lo que cabe en dos filas sin tener que desplazarse.
            result = result
                .sorted { Self.lastTouched($0) > Self.lastTouched($1) }
                .prefix(12)
                .map { $0 }
        }
        return result
    }

    /// Lo último que pasó con una prenda: habérsela puesto, o haberla metido.
    private static func lastTouched(_ garment: Garment) -> Date {
        max(garment.lastWornAt ?? garment.dateAdded, garment.dateAdded)
    }

    /// La muestra de cada color que aparece en la fila.
    ///
    /// Sale del armario y no de una tabla: el nombre lo puso el propio
    /// análisis de la prenda, así que el color exacto que representa está en
    /// la prenda y no hay que volver a adivinarlo.
    private var swatches: [String: NamedColor] {
        var table: [String: NamedColor] = [:]
        for garment in garments {
            guard let dominant = garment.colors.first else { continue }
            if table[dominant.nameKey] == nil { table[dominant.nameKey] = dominant }
        }
        return table
    }

    /// Los colores que de verdad hay en el armario, por frecuencia y solo el
    /// dominante de cada prenda.
    ///
    /// El dominante y no todos: una camiseta negra con una raya roja no es una
    /// prenda roja, y contarla como tal llena la fila de colores que luego no
    /// devuelven lo que esperas.
    private var colors: [TrayFilter] {
        var counts: [String: Int] = [:]
        for garment in garments {
            guard let dominant = garment.colors.first else { continue }
            counts[dominant.nameKey, default: 0] += 1
        }
        return counts
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(8)
            .map { .color($0.key) }
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
        // Rejilla de recortes: en una hoja que se abre para coger **una**
        // prenda y se cierra, lo que importa es ver muchas a la vez. Las
        // baldas del armario se leen mejor para recorrer, pero aquí no vienes
        // a recorrer.
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
            .padding(.top, WK.Spacing.s)
        }
        .scrollIndicators(.hidden)
        // **Sin el fondo del sistema.** Un `ScrollView` dentro de una hoja
        // trae su propia superficie, y sobre el cristal de la bandeja se veía
        // como un panel opaco pegado por dentro.
        .scrollContentBackground(.hidden)
        // **Sin alto forzado.** Lo tenía clavado a 220 puntos, así que subir
        // la hoja no enseñaba ni una prenda más. Ahora ocupa lo que haya.
        .frame(maxHeight: .infinity)
        .overlay {
            if visible.isEmpty {
                Text("Nada con este filtro")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
            }
        }
        // **Los filtros arriba, por secciones y con su nombre.**
        //
        // Con nombre porque tres filas de píldoras sin etiqueta son tres
        // filas de palabras sueltas: "negro" y "deporte" no dicen por sí solas
        // que una es un color y la otra un estilo.
        .safeAreaInset(edge: .top) {
            TrayFilterBars(
                sections: [
                    .init(title: "Atajos", filters: [.recent]),
                    // Solo las partes que de verdad hay en el armario.
                    .init(title: "Parte", filters: GarmentKind.allCases
                        .filter { kind in garments.contains { $0.kind == kind } }
                        .map { .part($0) }),
                    .init(title: "Baldas", filters: shelves),
                    .init(title: "Color", filters: colors),
                    .init(title: "Estilo", filters: styles),
                ],
                swatches: swatches,
                selection: $filters
            )
        }
        // Si la balda filtrada se queda sin prendas —las has usado todas— el
        // filtro vuelve solo a "Todo" en vez de dejar una rejilla vacía que
        // parece una app rota.
        .onChange(of: visible.isEmpty) { _, isEmpty in
            if isEmpty, !filters.isEmpty { filters.removeAll() }
        }
    }
}

/// Un filtro de la bandeja.
///
/// Un solo tipo para balda y estilo, y no dos enums paralelos: la fila los
/// pinta igual, el chip los compara igual y añadir un tercer criterio —color,
/// temporada— es un caso más aquí y nada más.
enum TrayFilter: Hashable {
    /// Lo último que has metido o puesto. Es el filtro que más se usa sin
    /// saberlo: casi siempre quieres la camiseta de la semana pasada, no la
    /// del año pasado.
    case recent
    /// **Parte del cuerpo.** No es una balda: agrupa varias. "Partes de
    /// arriba" son las camisetas, las camisas y los polos a la vez, que es lo
    /// que se busca cuando falta la parte de arriba del conjunto.
    case part(GarmentKind)
    case category(slug: String, name: String)
    case tag(String)
    case color(String)

    var label: String {
        switch self {
        case .recent: "Reciente"
        case let .part(kind): TrayFilter.partLabel(kind)
        case let .category(_, name): name
        case let .tag(tag): tag.capitalized
        case let .color(name): name.capitalized
        }
    }

    static func partLabel(_ kind: GarmentKind) -> String {
        switch kind {
        case .upperBody: "Parte de arriba"
        case .outerLayer: "Abrigo"
        case .lowerBody: "Parte de abajo"
        case .wholeBody: "Cuerpo entero"
        case .feet: "Calzado"
        case .head: "Cabeza"
        case .bag: "Bolsos"
        case .other: "Otros"
        }
    }

    /// El nombre del color, si es un filtro de color. Lo usa la fila para
    /// buscar su muestra: el nombre solo —"topo", "teja"— no dice cuál es, y
    /// con la muestra delante no hace falta saberlo.
    var colorKey: String? {
        guard case let .color(name) = self else { return nil }
        return name
    }
}

/// Las secciones de filtros. Vista propia: cambiar de filtro no tiene por qué
/// reevaluar la rejilla entera de prendas.
private struct TrayFilterBars: View {
    struct Section: Identifiable {
        let title: String
        let filters: [TrayFilter]
        var id: String { title }
    }

    /// Una sección por criterio. Las vacías no se dibujan: un armario sin
    /// estilos puestos no necesita una franja de aire donde iría la fila.
    let sections: [Section]
    /// La muestra de cada color, sacada del propio armario.
    let swatches: [String: NamedColor]
    @Binding var selection: Set<TrayFilter>

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            ForEach(sections) { section in
                if !section.filters.isEmpty {
                    VStack(alignment: .leading, spacing: WK.Spacing.xs) {
                        Text(section.title)
                            .font(WK.Font.caption)
                            .foregroundStyle(WK.Palette.tertiaryText)
                            .padding(.horizontal, WK.Spacing.m)

                        TrayFilterRow(
                            filters: section.filters,
                            swatches: swatches,
                            selection: $selection
                        )
                    }
                }
            }
        }
        .padding(.vertical, WK.Spacing.s)
    }
}

private struct TrayFilterRow: View {
    let filters: [TrayFilter]
    let swatches: [String: NamedColor]
    @Binding var selection: Set<TrayFilter>

    var body: some View {
        ScrollView(.horizontal) {
            // **Sin contenedor de cristal compartido.** El contenedor funde
            // las superficies vecinas —para eso está— y aquí eso se leía como
            // que el relleno de la elegida se derramaba sobre las de al lado.
            // Son botones independientes, no un control segmentado.
            HStack(spacing: WK.Spacing.s) {
                ForEach(filters, id: \.self) { filter in
                    TrayFilterChip(
                        label: filter.label,
                        swatch: filter.colorKey.flatMap { swatches[$0] },
                        isSelected: selection.contains(filter)
                    ) {
                        withAnimation(WKAnimation.selection) {
                            if selection.contains(filter) {
                                selection.remove(filter)
                            } else {
                                selection.insert(filter)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, WK.Spacing.m)
        }
        .scrollIndicators(.hidden)
        // Sin recortar: la píldora elegida crece un poco y al primero y al
        // último se les cortaría el borde.
        .scrollClipDisabled()
    }
}

private struct TrayFilterChip: View {
    let label: String
    /// Si el filtro es un color, su muestra. El nombre solo —"topo", "teja"—
    /// no dice cuál es; con el punto delante no hace falta saberlo.
    var swatch: NamedColor?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WK.Spacing.xs) {
                if let swatch {
                    Circle()
                        .fill(Color(red: swatch.red, green: swatch.green, blue: swatch.blue))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(WK.Palette.ink(0.18), lineWidth: 0.5))
                }
                Text(label)
                    .font(WK.Font.captionMedium)
                    .lineLimit(1)
            }
            .padding(.horizontal, WK.Spacing.m)
            .padding(.vertical, WK.Spacing.s)
            .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
        .modifier(TrayChipSurface(isSelected: isSelected))
    }
}

/// El relleno de la píldora, elegido en un sitio.
///
/// Elegida va en acento sólido y el resto en cristal. Separado en su propio
/// modificador porque el color de la etiqueta y el del fondo **se deciden
/// juntos** o acaban el uno encima del otro.
private struct TrayChipSurface: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content
                .foregroundStyle(WK.Palette.onAccent)
                .adaptiveGlassProminent(tint: WK.Palette.accent, in: .capsule)
        } else {
            content
                .foregroundStyle(WK.Palette.primaryText)
                .adaptiveGlassInteractive(in: .capsule)
        }
    }
}

extension TextSticker: Identifiable {
    public var id: String { "\(string)-\(colorHex)-\(backgroundHex ?? "")-\(alignment.rawValue)" }
}
