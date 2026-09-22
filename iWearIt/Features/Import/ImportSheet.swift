import CoreGraphics
import PhotosUI
import SwiftUI
import WKCore
import WKDesign
import WKVision

/// Hoja de importación: procesa una foto y deja revisar el resultado.
struct ImportSheet: View {
    /// Las fotos a revisar. Varias: ver `ImportPhotoStrip`.
    let images: [CGImage]

    init(images: [CGImage]) { self.images = images }
    /// Una sola, que es de donde vienen la cámara y la web.
    init(image: CGImage) { self.images = [image] }

    /// **Retomar** una importación que se cerró sin guardar.
    init(restoring model: ImportModel) {
        self.images = model.photos
        _model = State(initialValue: model)
        _hasRevealed = State(initialValue: true)
    }

    /// Si se guardó: entonces no hay nada que retomar al cerrar.
    @State private var didSave = false

    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(WKToastCenter.self) private var toasts
    @State private var model: ImportModel?
    /// La revelación se ha visto ya. Vive aquí y no en el modelo: es estado de
    /// presentación, y meterlo en el modelo obligaría a reejecutarla si el
    /// modelo se reconstruyera.
    @State private var hasRevealed = false
    /// "Agregar más": la galería otra vez, sobre la misma importación.
    @State private var isAddingMore = false
    @State private var extraItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    ImportPhaseContent(
                        model: model,
                        photos: images,
                        hasRevealed: $hasRevealed,
                        onAddMore: { await model.addPhotos($0) },
                        onSave: { await save(model) }
                    )
                } else {
                    // La foto con su barrido, no una ruedecita.
                    //
                    // El modelo tarda en construirse porque antes hay que
                    // esperar al segmentador, y enseñar un `ProgressView`
                    // desnudo durante esos segundos hacía parecer que la app se
                    // había quedado colgada. Es el mismo sitio de la pantalla y
                    // la misma animación que luego continúa: no hay salto.
                    VStack(spacing: WK.Spacing.m) {
                        ImportPhotoStrip(
                            photos: images,
                            candidates: [],
                            analysed: 0,
                            onFinished: {}
                        )

                        // **Qué está pasando, con palabras.** "Buscando
                        // prendas…" mientras en realidad se descargan 34 MB es
                        // una animación mintiendo: el usuario espera un segundo
                        // y decide que está roto.
                        Text(appEnvironment.modelState.description)
                            .font(WK.Font.callout)
                            .foregroundStyle(WK.Palette.secondaryText)
                            .contentTransition(.opacity)

                        // **El registro, apagado.** Se queda comentado y no
                        // se borra: sigue escribiéndose en `DiagnosticsLog` y
                        // se puede leer entero desde Perfil → Diagnóstico. Lo
                        // que no hace falta es tener cuarenta líneas de traza
                        // debajo de la foto mientras se importa ropa.
                        //
                        // DiagnosticsLogView(
                        //     lines: Array(DiagnosticsLog.shared.lines.suffix(40)),
                        //     maximumHeight: 140
                        // )
                    }
                    .padding(WK.Spacing.screenInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WK.Palette.canvas)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // **Solo cerrar.** Guardar vive abajo, junto a "Agregar más",
                // donde está la mano; un "Añadir" arriba repetía ese mismo
                // botón y un "Cancelar" en texto hacía lo que hace la X.
                //
                // ToolbarItem(placement: .cancellationAction) {
                //     Button("Cancelar") { dismiss() }
                // }
                // ToolbarItem(placement: .confirmationAction) {
                //     ImportSaveButton(model: model) { if let model { await save(model) } }
                // }
                // **Mientras analiza, ni X.** No un botón apagado: el hueco
                // entero fuera. Cerrar a medias tiraba el análisis, y no hay
                // nada que decidir hasta que acabe.
                if isAnalyzing {
                    // El sitio del título, vacío pero ocupado: así la barra no
                    // se recoloca cuando aparece "Revisar prendas".
                    ToolbarItem(placement: .principal) {
                        Color.clear.frame(width: 1, height: 1)
                    }
                }
                if !isAnalyzing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(WK.Font.headline)
                                .contentShape(.rect)
                        }
                        .tint(WK.Palette.primaryText)
                    }
                }
            }
        }
        // Y tampoco arrastrando hacia abajo.
        .interactiveDismissDisabled(isAnalyzing)
        // La galería de "Agregar más" vive ahora en el propio botón: ver
        // `ImportReviewStack`. Colgada aquí no llegaba a abrirse.
        // .photosPicker(
        //     isPresented: $isAddingMore,
        //     selection: $extraItems,
        //     maxSelectionCount: 10,
        //     matching: .images
        // )
        // .task(id: extraItems.count) { await addPicked() }
        // **Cerrar no es tirar.** Lo analizado y lo corregido se queda para
        // retomarlo desde el "+". Ver `ImportSessionStore`.
        .onDisappear {
            guard !didSave, let model else { return }
            appEnvironment.importSession.stash(model)
        }
        .task {
            // Retomada: ya está todo hecho, no hay nada que analizar.
            guard model == nil else { return }
            // **Esperar al segmentador antes de analizar.** Construido con
            // `segmenter == nil` —y la descarga tarda decenas de segundos— el
            // pipeline cae a la ruta degradada, que necesita una persona en la
            // foto y corta por articulaciones. Para la foto de una prenda
            // suelta eso no da nada, y parecía que el reconocimiento no
            // funcionaba cuando lo que pasaba es que aún no había llegado.
            await waitForModels()

            // El modelo se construye aquí y no en un `@State` inicial porque
            // necesita el segmentador, que depende del entorno.
            let created = ImportModel(
                segmenter: appEnvironment.segmenter,
                embedder: appEnvironment.embedder,
                promptBank: appEnvironment.promptBank,
                resolver: appEnvironment.resolver,
                wardrobe: appEnvironment.wardrobe
            )
            model = created
            await created.start(images)
        }
    }

    /// El título según por dónde va: mientras mira, qué está haciendo; al
    /// acabar, qué se espera de ti.
    private var title: String {
        if case .review = model?.phase { return "Revisar prendas" }
        // Sin título mientras analiza. Con un espacio como título, la barra
        // lo pintaba entre comillas —“ ”—, así que el hueco lo ocupa una
        // vista transparente: ver la barra de arriba.
        return ""
    }

    /// Si se está analizando: sin modelo todavía, o con él trabajando.
    private var isAnalyzing: Bool {
        guard let model else { return true }
        switch model.phase {
        case .idle, .processing, .generating: return true
        default: return false
        }
    }

    /// Espera al modelo **solo si le queda poco**.
    ///
    /// Bloquear la importación un minuto entero mientras se descargan 50 MB es
    /// una pantalla parada sin nada que enseñar, y para el caso más común
    /// —una foto de la prenda sola— el modelo **no hace falta**: la recorta la
    /// máscara de sujeto, que es nativa y ya está aquí.
    ///
    /// Así que se espera un margen corto, el que tarda el modelo en terminar
    /// si ya estaba compilando, y si no se sigue sin él. Peor una prenda
    /// recortada con la ruta barata que una rueda dando vueltas.
    private func waitForModels() async {
        guard !appEnvironment.hasSettledModels else { return }

        // **Tres segundos no eran una espera, eran un sorteo.**
        //
        // El razonamiento original —"para una prenda suelta el modelo no hace
        // falta, la recorta la máscara de sujeto"— resultó ser falso justo
        // cuando importa: cargar el modelo **ocupa la ANE**, y con la ANE
        // ocupada la máscara de sujeto tampoco responde. Así que empezar sin
        // esperar no daba el camino barato, daba tres topes seguidos y un
        // "está tardando demasiado".
        //
        // Ahora se espera de verdad, y mientras tanto la pantalla dice en qué
        // paso va y cuánto lleva descargado. Esperar sabiendo a qué se espera
        // no es lo mismo que esperar delante de una animación.
        let deadline = ContinuousClock.now.advanced(by: .seconds(90))
        DiagnosticsLog.record("IMPORT", "esperando a los modelos: \(appEnvironment.modelState)")
        while !appEnvironment.hasSettledModels, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(150))
        }
        DiagnosticsLog.record(
            "IMPORT",
            appEnvironment.hasSettledModels
                ? "modelos listos, empieza el análisis"
                : "los modelos no llegaron a tiempo; se analiza igual",
            isProblem: !appEnvironment.hasSettledModels
        )
    }

    /// Las fotos añadidas, derechas y analizadas sin tirar lo que ya había.
    private func addPicked() async {
        guard !extraItems.isEmpty, let model else { return }
        let picked = extraItems
        defer { extraItems = [] }

        var images: [CGImage] = []
        for item in picked {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UprightImage.cgImage(from: data)
            else { continue }
            images.append(image)
        }
        await model.addPhotos(images)
    }

    private func save(_ model: ImportModel) async {
        let saved = (try? await model.save(
            imageStore: appEnvironment.imageStore,
            wardrobe: appEnvironment.wardrobe
        )) ?? 0
        didSave = true
        appEnvironment.importSession.clear()
        dismiss()

        // El aviso se pide **después** de cerrar, y lo pinta la raíz: si lo
        // enseñara esta hoja, se iría con ella antes de poder leerse.
        guard saved > 0 else { return }
        toasts.show(WKToast(saved == 1 ? "Prenda guardada" : "\(saved) prendas guardadas"))
    }
}

/// Contenido según la fase. Vista aparte para que `ImportSheet` no lleve el
/// `switch` dentro de su `@ViewBuilder`.
private struct ImportPhaseContent: View {
    let model: ImportModel
    let photos: [CGImage]
    @Binding var hasRevealed: Bool
    /// Añadir más fotos a esta misma importación, y guardarlo todo.
    let onAddMore: ([CGImage]) async -> Void
    let onSave: () async -> Void

    var body: some View {
        switch model.phase {
        case .idle, .processing:
            reveal(isScanning: true, status: "Buscando prendas…")
        case let .generating(done, total):
            // El mismo barrido, con el paso nombrado. Lo que no puede pasar es
            // que se quede la animación sin decir qué está esperando.
            reveal(
                isScanning: true,
                status: total > 1
                    ? "Redibujando prendas… \(done) de \(total)"
                    : "Redibujando la prenda…"
            )
        case .detected:
            // **El paso nuevo.** Se enseña lo detectado y se decide ahí qué
            // es una prenda; solo después se reconstruye. Ver
            // `ImportDetectedStep`.
            if hasRevealed {
                ImportDetectedStep(model: model, photos: photos)
                    .transition(AnyTransition(.blurReplace))
            } else {
                reveal(isScanning: false, status: "Recortando")
                    .transition(AnyTransition(.blurReplace))
            }
        case .review:
            if hasRevealed {
                // **La misma ficha en los dos casos.** Con una sola, ella
                // sola; con varias, paginadas y con una tira arriba para saber
                // en cuál estás y cuáles entran. Tener dos calidades de
                // revisión según cuántas prendas trajera la foto era lo que
                // dejaba el caso de varias sin poder editar nada.
                Group {
                    if model.candidates.count == 1, let only = model.candidates.first {
                        ImportSingleCard(
                            candidate: only,
                            photo: model.photo(for: only) ?? photos[0],
                            onChangeKind: { model.setKind($0, forCandidateWithID: only.id) },
                            onChangeName: { model.setName($0, forCandidateWithID: only.id) },
                            onChangeColor: { model.setColorName($0, forCandidateWithID: only.id) },
                            onPickColor: { picked in
                                let rgb = UIColor(picked).rgb
                                model.setColor(
                                    red: rgb.red, green: rgb.green, blue: rgb.blue,
                                    forCandidateWithID: only.id
                                )
                            },
                            onChangeTags: { model.setTags($0, forCandidateWithID: only.id) },
                            onChangeCut: { model.setCut($0, forCandidateWithID: only.id) },
                            onChangeCategory: { model.setCategory($0, forCandidateWithID: only.id) },
                            onChangeSeasons: { model.setSeasons($0, forCandidateWithID: only.id) },
                            onChangeSubcategory: { model.setSubcategory($0, forCandidateWithID: only.id) },
                            onChangeMaterial: { model.setMaterial($0, forCandidateWithID: only.id) },
                            onManualCrop: { model.setManualCrop($0, forCandidateWithID: only.id) },
                            onRestyle: { await model.restyle(candidateWithID: only.id) },
                            onImprove: { model.improve(candidateWithID: only.id) }
                        )
                    } else {
                        // **Una tarjeta por prenda, en vertical.**
                        //
                        // El pager sigue existiendo y no se borra —ver
                        // `ImportReviewPager`—, pero ya no se llama: con
                        // varias prendas eran dos scrolls cruzados, uno
                        // horizontal de fichas y otro vertical dentro de cada
                        // una, y no se sabía cuántas había sin pasarlas todas.
                        //
                        // ImportReviewPager(model: model, photos: photos)
                        ImportReviewStack(
                            model: model,
                            photos: model.photos.isEmpty ? photos : model.photos,
                            onAddMore: onAddMore,
                            onSave: onSave
                        )
                    }
                }
                    .transition(AnyTransition(.blurReplace))
            } else {
                reveal(isScanning: false, status: "Recortando")
                    .transition(AnyTransition(.blurReplace))
            }
        case let .nothingFound(reason):
            failure(title: reason.title, symbol: reason.symbol, message: reason.message)
        case let .failed(message):
            failure(
                title: "No se pudo procesar",
                symbol: "exclamationmark.triangle",
                message: message
            )
        }
    }
}

private extension ImportPhaseContent {
    /// El fallo, **con el registro debajo**.
    ///
    /// Un `ContentUnavailableView` a secas dice que no hay nada y se queda tan
    /// ancho. Lo que hace falta saber en ese momento es en qué paso se cayó, y
    /// eso estaba solo en la consola de Xcode — es decir, en ningún sitio
    /// cuando el fallo ocurre con el iPhone en la mano.
    @ViewBuilder
    func failure(title: String, symbol: String, message: String) -> some View {
        VStack(spacing: WK.Spacing.m) {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text(message)
            }

            // **Aquí sí.** En el fallo el registro es la única forma de
            // saber en qué paso se cayó, y es donde se pidió que estuviera.
            DiagnosticsLogView(
                lines: Array(DiagnosticsLog.shared.lines(since: model.logMarker)),
                maximumHeight: 200
            )
            .padding(.horizontal, WK.Spacing.screenInset)

            Button("Copiar registro") {
                UIPasteboard.general.string = DiagnosticsLog.shared.transcript
            }
            .font(WK.Font.callout)
            .foregroundStyle(WK.Palette.accent)
            .padding(.bottom, WK.Spacing.m)
        }
    }

    /// La foto con su barrido, y las prendas saliendo de ella.
    func reveal(isScanning: Bool, status: String) -> some View {
        VStack(spacing: WK.Spacing.m) {
            // El mismo carrete con una foto o con seis: con una no enseña
            // contador ni deja arrastrar, así que no hay dos pantallas que
            // mantener por lo mismo.
            ImportPhotoStrip(
                photos: photos,
                candidates: model.candidates,
                analysed: isScanning ? model.analysedCount : photos.count
            ) {
                withAnimation(WKAnimation.content) { hasRevealed = true }
            }

            // **Que se note que sigue trabajando.** Analizar una foto tarda
            // lo que tarda, y una sola frase quieta durante quince segundos se
            // lee como colgado. El texto va cambiando por los pasos reales del
            // embudo, así que además dice en qué anda.
            ImportStatusTicker(base: status, isRunning: isScanning)

            // El registro va comentado, no borrado: ver arriba.
            //
            // if isScanning {
            //     DiagnosticsLogView(
            //         lines: Array(DiagnosticsLog.shared.lines(since: model.logMarker)),
            //         maximumHeight: 140
            //     )
            // }
        }
        .padding(WK.Spacing.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WK.Palette.canvas)
    }
}

/// El texto de espera, que va pasando por los pasos.
///
/// Los pasos son **los de verdad** y en su orden: primero se mira si hay
/// alguien, luego se separa la prenda del fondo, luego se repasa el contorno y
/// al final se miden los colores. Inventar frases de relleno haría lo mismo a
/// la vista y mentiría; estas, además, sitúan el fallo cuando algo se atasca.
private struct ImportStatusTicker: View {
    let base: String
    let isRunning: Bool

    @State private var step = 0

    private static let steps = [
        "Mirando la foto…",
        "Buscando la prenda…",
        "Separándola del fondo…",
        "Repasando el contorno…",
        "Midiendo los colores…",
        "Casi está…",
    ]

    /// Cuánto dura cada frase.
    ///
    /// Dos segundos y pico: menos parece nervioso —y da la impresión de que
    /// cada paso dura eso, que no es verdad— y más vuelve a parecer quieto.
    private static let interval = Duration.milliseconds(2200)

    var body: some View {
        Text(isRunning ? Self.steps[step] : base)
            .font(WK.Font.callout)
            .foregroundStyle(WK.Palette.secondaryText)
            .contentTransition(.numericText())
            .animation(WKAnimation.content, value: step)
            .animation(WKAnimation.content, value: isRunning)
            .task(id: isRunning) {
                guard isRunning else { return }
                // La última se queda puesta: seguir rotando después de "casi
                // está" convertiría la espera en un carrusel y quitaría la
                // única señal de que esto ya va a acabar.
                while !Task.isCancelled, step < Self.steps.count - 1 {
                    try? await Task.sleep(for: Self.interval)
                    guard !Task.isCancelled else { return }
                    step += 1
                }
            }
    }
}

private struct ImportSaveButton: View {
    let model: ImportModel?
    let action: () async -> Void
    @State private var isSaving = false

    var body: some View {
        Button(title) {
            isSaving = true
            Task { await action() }
        }
        .disabled(!isReviewing || model?.keptCount == 0 || isSaving)
        // Se atenúa, no se va: ocupar el sitio desde el principio es lo que
        // mantiene quieta la barra.
        .opacity(isReviewing ? 1 : 0)
    }

    private var title: String { "Añadir \(model?.keptCount ?? 0)" }

    private var isReviewing: Bool {
        if case .review = model?.phase { return true }
        return false
    }
}
