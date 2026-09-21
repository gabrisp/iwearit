import Foundation
import Observation
import SwiftData
import WKCore
import WKPersistence
import WKServices
import WKVision

/// Raíz de composición: decide qué implementación de cada servicio corre.
///
/// Las vistas nunca construyen servicios ni saben si están hablando con
/// Appwrite, con ficheros locales o con un mock. Eso permite recorrer las tres
/// rutas (`-modelSource appwrite|local|none`) **sin recompilar**.
@MainActor
@Observable
public final class AppEnvironment {

    /// De dónde salen los modelos de Core ML.
    public enum ModelSource: String {
        /// Manifiesto y ficheros desde Appwrite. Producción.
        case appwrite
        /// `.mlpackage` empujados al simulador con `xcrun simctl`. Desarrollo.
        case local
        /// Sin modelos: fuerza el modo degradado que usa solo APIs de Vision.
        case none
    }

    public let modelSource: ModelSource
    public let container: ModelContainer
    public let imageStore: ImageStore
    public let modelStore: ModelStore
    /// Qué puede hacer el usuario. Lo único que sabe de suscripciones.
    public let gate: FeatureGate

    /// Estado de los modelos, para que Perfil pueda contarlo y la importación
    /// sepa si tiene segmentador.
    /// En qué punto está la preparación de modelos.
    ///
    /// Cada cambio se registra: sin esto, que el segmentador no llegue a
    /// cargarse se ve desde fuera **exactamente igual** que si no hubiera
    /// modelo — la app cae a las rutas nativas sin decir nada, y no hay forma
    /// de saber si CoreML está participando o no.
    public private(set) var modelState: ModelState = .idle {
        didSet {
            guard modelState != oldValue else { return }
            NSLog("MODELOS: %@", modelState.description)
        }
    }

    /// El segmentador ya está cargado y el pipeline puede recortar prendas de
    /// verdad. Si es `false`, cualquier análisis cae a la ruta degradada.
    public var isSegmenterReady: Bool { segmenter != nil }

    /// La preparación de modelos ha terminado, con o sin éxito.
    ///
    /// Lo que importa para decidir si **esperar**: mientras esto sea `false`
    /// todavía puede aparecer el segmentador.
    public var hasSettledModels: Bool {
        switch modelState {
        case .ready, .unavailable: true
        case .idle, .checking, .downloading, .compiling, .loading: false
        }
    }
    /// El segmentador, una vez el modelo está descargado y compilado.
    public private(set) var segmenter: ClothesSegmenter?
    /// A quién preguntar cuando el dispositivo no llega.
    ///
    /// Va a una Function de Appwrite, **nunca a OpenRouter directamente**: la
    /// clave vive en el servidor y no en el binario. Y solo se le manda el
    /// recorte normalizado, nunca la foto original.
    public private(set) var resolver: (any ClothingResolving)?

    /// Embedder y banco de prompts. Van **juntos**: el banco solo significa
    /// algo contra embeddings del mismo checkpoint, así que si falta uno no se
    /// usa el otro.
    public private(set) var embedder: GarmentEmbedder?
    public private(set) var promptBank: PromptBank?

    public enum ModelState: Equatable, CustomStringConvertible {
        public var description: String {
            switch self {
            case .idle: "sin empezar"
            case .checking: "consultando el manifiesto"
            case let .downloading(fraction): "descargando \(Int(fraction * 100))%"
            case .compiling: "compilando"
            case .loading: "cargando el modelo"
            case let .ready(version): "listo (v\(version))"
            case let .unavailable(reason): "NO DISPONIBLE — \(reason)"
            }
        }

        case idle
        case checking
        case downloading(fraction: Double)
        case compiling
        /// `MLModel(contentsOf:)` preparando el plan de cómputo. **Es el paso
        /// largo** con un modelo grande, y el que deja la ANE ocupada.
        case loading
        case ready(version: Int)
        case unavailable(String)
    }
    /// Escrituras de fondo. Los `@Model` no son `Sendable`, así que todo lo que
    /// cruce a este actor son DTOs; vuelven `PersistentIdentifier`.
    public let wardrobe: WardrobeActor

    /// El tiempo, para los stickers. Sin ubicación del dispositivo: el sitio
    /// se elige a mano, que para un viaje es además el correcto.
    public let weather = WeatherProvider()

    private init(
        modelSource: ModelSource,
        container: ModelContainer,
        imageStore: ImageStore,
        modelStore: ModelStore
    ) {
        self.modelSource = modelSource
        self.container = container
        self.imageStore = imageStore
        self.modelStore = modelStore
        self.wardrobe = WardrobeActor(modelContainer: container)
        // Con memoria: cada consulta cuesta dinero y segundo y medio, y la
        // misma prenda reimportada produce el mismo recorte byte a byte.
        if modelSource == .appwrite, let cache = try? ResolutionCache() {
            self.resolver = CachedClothingResolver(
                base: RemoteClothingResolver(
                    endpoint: AppConfiguration.appwriteEndpoint,
                    projectID: AppConfiguration.appwriteProjectID
                ),
                cache: cache
            )
        }
        self.gate = FeatureGate(
            entitlements: Self.makeEntitlements(),
            container: container
        )
    }

    /// Quién decide si el usuario es Pro.
    ///
    /// En Debug, un interruptor en Perfil: recorrer las dos ramas sin comprar
    /// nada ni pelearse con el sandbox es lo que hace que el gating se pruebe
    /// de verdad. En Release, el servicio real.
    private static func makeEntitlements() -> EntitlementsService {
        #if DEBUG
        DebugEntitlementsService()
        #else
        RevenueCatEntitlementsService(apiKey: AppConfiguration.revenueCatAPIKey)
        #endif
    }

    /// El repositorio que toca según el origen elegido.
    private static func makeRepository(for source: ModelSource) -> ModelRepository {
        switch source {
        case .appwrite:
            AppwriteModelRepository(
                endpoint: AppConfiguration.appwriteEndpoint,
                projectID: AppConfiguration.appwriteProjectID
            )
        case .local, .none:
            // `.local` todavía no tiene implementación propia; cae en "sin
            // modelos", que es una degradación honesta y no un crash.
            UnavailableModelRepository()
        }
    }

    public static func live() -> AppEnvironment {
        let source = resolvedModelSource()
        do {
            return AppEnvironment(
                modelSource: source,
                container: try WardrobeStore.makeContainer(),
                imageStore: try ImageStore(),
                modelStore: try ModelStore(repository: makeRepository(for: source))
            )
        } catch {
            // Si el store en disco no abre (esquema incompatible, disco lleno),
            // arrancar en memoria es mejor que morir: el usuario ve la app,
            // puede llegar a Perfil y entender qué pasa.
            assertionFailure("No se pudo abrir el contenedor en disco: \(error)")
            return AppEnvironment(
                modelSource: .none,
                container: try! WardrobeStore.makeContainer(inMemory: true),
                imageStore: try! ImageStore(root: URL.temporaryDirectory.appending(path: "iWearIt-fallback")),
                modelStore: try! ModelStore(
                    repository: UnavailableModelRepository(),
                    root: URL.temporaryDirectory.appending(path: "iWearIt-models")
                )
            )
        }
    }

    /// Por defecto, Appwrite. La ruta degradada sigue existiendo y entra sola
    /// si la descarga falla o el usuario está sin red.
    private static func resolvedModelSource() -> ModelSource {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-modelSource"),
           i + 1 < args.count,
           let source = ModelSource(rawValue: args[i + 1]) {
            return source
        }
        #endif
        return .appwrite
    }

    /// Trabajo de arranque. Se lanza desde un `.task`, no desde `init`, para no
    /// retrasar la primera pintura.
    public func bootstrap() async {
        do {
            try await wardrobe.seedCategoriesIfNeeded()
            // Limpieza de imágenes huérfanas: sin esto, descartar prendas en la
            // revisión de stacks deja basura en disco para siempre.
            let live = try await wardrobe.liveImageKeys()
            try await imageStore.garbageCollect(keeping: live)
        } catch {
            assertionFailure("Bootstrap falló: \(error)")
        }

        await gate.refresh()
        await prepareModels()

        #if DEBUG
        // `seed` / `seed300` siembran el armario al arrancar, para poder
        // capturar y medir sin tocar la pantalla.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("seed") || args.contains("seed300") {
            let existing = (try? await wardrobe.garmentCount()) ?? 0
            if existing == 0 {
                _ = try? await DevSeed.populate(
                    wardrobe: wardrobe,
                    imageStore: imageStore,
                    count: args.contains("seed300") ? 300 : 30
                )
            }
        }

        if args.contains("probe-edit") {
            await runEditProbe()
        }
        if args.contains("probe-pipeline") {
            await PipelineProbe.run()
        }
        if args.contains("probe-backdrop") {
            Task {
                try? await Task.sleep(for: .seconds(6))
                try? await wardrobe.probeSetBackdrop("blush")
            }
        }
        if args.contains("probe-outfit") {
            try? await wardrobe.probeBuildTodayOutfit()
        }
        if args.contains("probe-nudge") {
            try? await Task.sleep(for: .seconds(5))
            NSLog("PROBE: antes de mover")
            try? await wardrobe.probeNudgeFirstCanvasItem()
            NSLog("PROBE: despues de mover")
        }
        if args.contains("probe-suitcases") {
            try? await wardrobe.probeBuildSuitcases()
        }
        if args.contains("probe-category") {
            try? await wardrobe.probeCreateCategory(named: "Gorras", movingKind: .head)
        }
        #endif
    }

    /// Descarga y compila los modelos si hace falta.
    ///
    /// No bloquea nada: mientras no esté listo, el pipeline usa la ruta
    /// degradada. Que la app sea usable desde el primer segundo importa más que
    /// tener el mejor recorte posible en el primero.
    public func prepareModels() async {
        guard modelSource == .appwrite else {
            modelState = .unavailable("Sin origen de modelos")
            return
        }
        // **Primero lo que ya está en disco.**
        //
        // Preguntar al servidor qué versión hay es una cortesía; tener el
        // modelo cargado es lo que hace que la app funcione. Con el orden al
        // revés —que es como estaba— una consulta lenta dejaba la importación
        // esperando por un JSON de tres líneas teniendo los 34 MB del modelo ya
        // en el teléfono. Ahora el segundo arranque es inmediato y la
        // comprobación de versión ocurre por detrás.
        await loadInstalled()

        modelState = segmenter == nil ? .checking : modelState
        DiagnosticsLog.record("MODELOS", "consultando el manifiesto")

        do {
            let entries = try await modelStore.installedOrFetch()
            DiagnosticsLog.record(
                "MODELOS",
                "manifiesto: " + entries.map { "\($0.modelID) v\($0.version)" }.joined(separator: ", ")
            )

            func install(_ modelID: String) async throws -> ModelStore.InstalledModel? {
                guard let entry = entries.first(where: { $0.modelID == modelID }) else { return nil }
                return try await modelStore.install(entry) { [weak self] progress in
                    Task { @MainActor in
                        switch progress {
                        case let .downloading(fraction):
                            self?.modelState = .downloading(fraction: fraction)
                        case .verifying, .compiling:
                            self?.modelState = .compiling
                        case .ready:
                            break
                        }
                    }
                }
            }

            // El segmentador es el imprescindible: sin él no hay recorte por
            // prenda y la app cae al modo degradado.
            guard let segmentation = try await install(AppConfiguration.ModelID.clothesSegmenter) else {
                modelState = .unavailable("El servidor no publica ningún segmentador")
                return
            }
            // **Cargar el modelo ocupa la ANE.**
            //
            // `MLModel(contentsOf:)` no solo mapea el fichero: prepara el plan
            // de cómputo, y para un modelo grande eso es la ANE trabajando
            // decenas de segundos la primera vez. Mientras dura, las peticiones
            // neuronales de Vision —pose, sujeto, saliencia— **no vuelven**. Si
            // el usuario importa una foto justo en esa ventana, ve tres topes
            // seguidos y un "está tardando demasiado" que no explica nada.
            //
            // Por eso se anota con su duración: es el dato que convierte ese
            // cuelgue en una frase que se entiende.
            modelState = .loading
            DiagnosticsLog.record(
                "MODELOS",
                "cargando el segmentador (entrada \(segmentation.inputWidth)px). "
                    + "Mientras dure, Vision no responde."
            )
            let clock = ContinuousClock.now
            segmenter = await Self.loadSegmenter(
                at: segmentation.compiledURL,
                inputSize: segmentation.inputWidth
            )
            guard segmenter != nil else {
                DiagnosticsLog.record(
                    "MODELOS", "el segmentador no se pudo cargar", isProblem: true
                )
                modelState = .unavailable("El segmentador descargado no se pudo cargar")
                return
            }
            DiagnosticsLog.record(
                "MODELOS", "segmentador cargado en \(clock.duration(to: .now))"
            )

            // Embedder y banco: o los dos, o ninguno. Un banco sin embedder no
            // tiene contra qué comparar, y un embedder sin banco no sabe cómo
            // se llama lo que ha medido.
            //
            // **Y ninguno de los dos puede tumbar al segmentador.** Antes
            // estaban en el mismo `do`, así que un fallo instalando el banco
            // abortaba todo y dejaba el estado en "no disponible" aunque el
            // recorte por píxel estuviera perfectamente cargado. Recortar sin
            // saber la subcategoría es mucho mejor que no recortar.
            let embedderModel = try? await install(AppConfiguration.ModelID.garmentEmbedder)
            let bankModel = try? await install(AppConfiguration.ModelID.promptBank)
            if let embedderModel, let bankModel {
                let loaded = await Self.loadEmbedder(
                    at: embedderModel.compiledURL,
                    inputSize: embedderModel.inputWidth,
                    bankAt: bankModel.compiledURL
                )
                embedder = loaded.embedder
                promptBank = loaded.bank
            }

            DiagnosticsLog.record(
                "MODELOS",
                "listo — segmentador sí · embedder \(embedder == nil ? "NO" : "sí")"
                    + " · banco \(promptBank == nil ? "NO" : "sí")"
            )
            // La ANE vuelve a estar libre: si alguna petición de Vision se dio
            // por muerta mientras cargábamos, que se vuelva a intentar ya y no
            // dentro de un minuto.
            VisionStages.resetNeuralAvailability()
            modelState = .ready(version: segmentation.version)
        } catch {
            // Sin modelo la app sigue funcionando: el mensaje es informativo,
            // no un error bloqueante.
            DiagnosticsLog.record("MODELOS", "falló: \(error.localizedDescription)", isProblem: true)
            modelState = .unavailable(error.localizedDescription)
        }
    }

    /// Carga lo que ya esté instalado, sin tocar la red.
    ///
    /// Si no hay nada, no hace nada y el estado se queda como estaba: entonces
    /// sí toca bajarlo, y esperar es lo correcto porque no hay alternativa.
    private func loadInstalled() async {
        let installed = await modelStore.installed()
        guard let segmentation = installed[AppConfiguration.ModelID.clothesSegmenter] else {
            DiagnosticsLog.record("MODELOS", "no hay nada instalado todavía")
            return
        }

        let clock = ContinuousClock.now
        modelState = .loading
        segmenter = await Self.loadSegmenter(
            at: segmentation.compiledURL,
            inputSize: segmentation.inputWidth
        )
        guard segmenter != nil else { return }
        DiagnosticsLog.record(
            "MODELOS",
            "segmentador v\(segmentation.version) cargado de disco en \(clock.duration(to: .now))"
        )

        if let embedderModel = installed[AppConfiguration.ModelID.garmentEmbedder],
           let bankModel = installed[AppConfiguration.ModelID.promptBank] {
            let loaded = await Self.loadEmbedder(
                at: embedderModel.compiledURL,
                inputSize: embedderModel.inputWidth,
                bankAt: bankModel.compiledURL
            )
            embedder = loaded.embedder
            promptBank = loaded.bank
        }

        VisionStages.resetNeuralAvailability()
        // **Ya se puede importar.** Lo que venga después —comprobar si hay una
        // versión nueva, bajarla— pasa por detrás sin que nadie espere.
        modelState = .ready(version: segmentation.version)
    }

    /// Tira lo descargado y lo vuelve a traer.
    ///
    /// Para depurar: si un modelo quedó a medias o se subió uno nuevo con la
    /// misma versión, comparar versiones no detecta nada y la app se queda con
    /// lo viejo para siempre. Esto es la salida.
    public func redownloadModels() async {
        DiagnosticsLog.record("MODELOS", "borrando lo descargado para volver a traerlo")
        segmenter = nil
        embedder = nil
        promptBank = nil
        try? await modelStore.removeAll()
        modelState = .idle
        await prepareModels()
    }

    /// Qué hay instalado ahora mismo, para enseñarlo en Ajustes.
    public func installedModels() async -> [InstalledModelInfo] {
        let installed = await modelStore.installed()
        var result: [InstalledModelInfo] = []
        for (id, model) in installed {
            result.append(
                InstalledModelInfo(
                    modelID: id,
                    version: model.version,
                    inputSize: model.inputWidth,
                    labelCount: model.labels.count,
                    sizeOnDisk: await modelStore.sizeOnDisk(of: id)
                )
            )
        }
        return result.sorted { $0.modelID < $1.modelID }
    }

    /// Lo que se enseña de un modelo instalado.
    public struct InstalledModelInfo: Identifiable, Sendable {
        public let modelID: String
        public let version: Int
        public let inputSize: Int
        public let labelCount: Int
        public let sizeOnDisk: Int
        public var id: String { modelID }
    }

    /// Carga el segmentador **fuera del hilo principal**.
    ///
    /// `MLModel(contentsOf:)` es síncrono y con el segmentador tarda segundos:
    /// mapea el `.mlmodelc`, valida la descripción y prepara el plan de
    /// cómputo. Hecho desde `prepareModels()` —que está aislado en `@MainActor`
    /// porque publica el estado a la UI— eso **congela la app entera** justo al
    /// arrancar, que es exactamente cuando el usuario está mirando la primera
    /// pantalla del onboarding y tocando el botón sin que pase nada.
    ///
    /// `ClothesSegmenter` es un `actor`, así que cruza de vuelta sin problema.
    private nonisolated static func loadSegmenter(
        at url: URL,
        inputSize: Int
    ) async -> ClothesSegmenter? {
        await Task.detached(priority: .userInitiated) {
            try? ClothesSegmenter(compiledModelAt: url, inputSize: inputSize)
        }.value
    }

    /// Igual para el embedder y su banco de prompts.
    ///
    /// Van juntos a propósito: **o los dos, o ninguno**. Un banco sin embedder
    /// no tiene contra qué comparar, y un embedder sin banco no sabe cómo se
    /// llama lo que ha medido.
    ///
    /// El `Data(contentsOf:)` del banco también viaja aquí: es una lectura de
    /// disco síncrona, y en el hilo principal se paga igual que la del modelo.
    private nonisolated static func loadEmbedder(
        at url: URL,
        inputSize: Int,
        bankAt bankURL: URL
    ) async -> (embedder: GarmentEmbedder?, bank: PromptBank?) {
        await Task.detached(priority: .userInitiated) {
            guard
                let embedder = try? GarmentEmbedder(compiledModelAt: url, inputSize: inputSize),
                let data = try? Data(contentsOf: bankURL),
                let bank = try? PromptBank(decoding: data)
            else { return (nil, nil) }
            return (embedder, bank)
        }.value
    }

    #if DEBUG
    /// Edita una prenda pasado un margen y deja marcas en el log, para medir
    /// qué vistas se reevalúan sin depender de tocar la pantalla.
    private func runEditProbe() async {
        try? await Task.sleep(for: .seconds(4))
        NSLog("PROBE: antes de editar")
        try? await wardrobe.renameFirstGarment(inCategorySlug: "tops", to: "SONDA")
        NSLog("PROBE: despues de editar")
    }
    #endif
}
