import CoreGraphics
import Foundation
import ImageIO
import Observation
import SwiftUI
import WKCore
import WKPersistence
import WKVision

/// Coordina "una foto entra, prendas salen".
///
/// Vive aparte de la vista porque el trabajo pesado —pipeline de visión,
/// escritura a disco, inserción— no tiene por qué reejecutarse cada vez que
/// SwiftUI reevalúa un `body`.
@MainActor
@Observable
final class ImportModel {

    enum Phase {
        case idle
        case processing
        /// **Lo detectado, antes de tocar nada.**
        ///
        /// El paso que faltaba. Se enseña lo que ha salido de la foto y se
        /// decide ahí: qué se queda, qué sobra y qué hay que rodear a mano
        /// porque el detector lo partió o se lo dejó. Solo después de eso se
        /// pide la reconstrucción — que cuesta dinero y no tiene sentido pagar
        /// por tres trozos de un mismo pantalón.
        case detected
        /// Redibujando las prendas. Con cuántas van, porque son segundos por
        /// prenda y una pantalla parada sin número parece colgada.
        case generating(done: Int, total: Int)
        case review
        /// La foto era válida pero no había nada que recortar.
        case nothingFound(NothingFoundReason)
        case failed(String)
    }

    enum NothingFoundReason {
        case noPerson
        case noGarments
        /// Vision no puede correr aquí. En la práctica: simulador.
        case visionUnavailable
        /// El resto de fallos del pipeline, con su motivo real.
        case pipeline(PipelineError)

        var title: String {
            switch self {
            case .visionUnavailable: "Necesita un iPhone de verdad"
            case .pipeline(let error): error.errorDescription ?? "No se pudo procesar"
            default: "Nada que recortar"
            }
        }

        var symbol: String {
            switch self {
            case .visionUnavailable: "iphone.gen3"
            case .pipeline: "exclamationmark.triangle"
            default: "scissors"
            }
        }

        var message: String {
            switch self {
            case .noPerson:
                "No se reconoce a nadie en la foto. Por ahora el recorte se apoya en el cuerpo para saber qué es cada prenda."
            case .noGarments:
                "Se reconoce a alguien, pero no se pudo separar ninguna prenda. Prueba con una foto de cuerpo entero y fondo despejado."
            case .visionUnavailable:
                "El reconocimiento de imágenes no funciona en el simulador: necesita el Neural Engine de un dispositivo real. En un iPhone funciona con normalidad."
            case .pipeline(let error):
                error.recoverySuggestion ?? "Prueba con otra foto."
            }
        }
    }

    private(set) var phase: Phase = .idle
    /// Prendas propuestas, con la decisión del usuario encima.
    private(set) var candidates: [ImportCandidate] = []

    /// Dónde estaba el registro al empezar esta foto.
    ///
    /// Para poder enseñar en la hoja **solo lo de esta foto** y no el historial
    /// entero de la sesión, que incluye la descarga de los modelos y todo lo
    /// anterior.
    private(set) var logMarker = 0

    private var pipeline: GarmentPipeline
    /// Para pedir la versión de catálogo. El mismo que usa el pipeline.
    private let resolver: (any ClothingResolving)?
    /// Para comparar contra lo que ya hay. Opcional porque las previsualizaciones
    /// construyen el modelo sin armario detrás.
    private let wardrobe: WardrobeActor?

    /// - Parameters:
    ///   - segmenter: sin él, el pipeline cae a la ruta degradada.
    ///   - embedder, promptBank: sin ellos hay recorte pero no subcategoría ni
    ///     atributos, y las baldas propias no se rellenan solas.
    ///   - resolver: la segunda opinión. Solo se consulta cuando el resultado
    ///     local es dudoso — ver `GarmentPipeline.needsRemoteHelp`.
    init(
        segmenter: ClothesSegmenter?,
        embedder: GarmentEmbedder?,
        promptBank: PromptBank?,
        resolver: (any ClothingResolving)? = nil,
        wardrobe: WardrobeActor? = nil
    ) {
        self.wardrobe = wardrobe
        self.resolver = resolver
        self.pipeline = GarmentPipeline(
            segmenter: segmenter,
            embedder: embedder,
            promptBank: promptBank,
            // **Sin segunda opinión de pago para los atributos.**
            //
            // El servidor se queda para una sola cosa: redibujar la prenda.
            // Todo lo que es reconocer —tipo, forma, etiquetas, color y la
            // marca por OCR— sale del dispositivo, y desde que el codificador
            // es de moda y no genérico sale bien. Preguntar fuera por cada
            // prenda dudosa era pagar por lo que ya se sabía aquí.
            //
            // El `resolver` de este modelo sigue vivo: lo usa `restyle`.
            resolver: nil,
            // **Una foto, una prenda.** Partir una clase en instancias es del
            // escaneo de la galería; aquí se está fotografiando una cosa y
            // partir solo puede equivocarse — el pantalón que volvía en tres.
            splitsInstances: false,
            // **Y ya no se pregunta siempre.** Preguntar por cada prenda era
            // pagar una consulta también cuando el dispositivo ya sabía la
            // respuesta: el tipo, las etiquetas y hasta la marca salen del
            // propio recorte —prompt bank y OCR— y salen bien a poco que la
            // foto sea decente. Se pregunta solo cuando lo local es dudoso:
            // ver `GarmentPipeline.needsRemoteHelp`.
            alwaysAsksRemote: false
        )
    }

    func process(_ image: CGImage) async {
        phase = .processing
        candidates = []
        logMarker = DiagnosticsLog.shared.marker

        let clock = ContinuousClock.now
        DiagnosticsLog.record("IMPORT", "empieza · foto \(image.width)×\(image.height)")

        // **La pose ya no se pide dos veces.**
        //
        // Antes esto la pedía aparte solo para dejar una traza, y el pipeline la
        // volvía a pedir acto seguido. Con la ANE libre son 8 ms tirados; con la
        // ANE ocupada son **ocho segundos** tirados antes de empezar, y eso era
        // la mitad del cuelgue.

        do {
            // **Con tope.** Si una etapa de Vision se queda esperando —pasa con
            // la ANE ocupada o con un modelo a medio instalar—, sin esto la
            // pantalla se queda con el barrido dando vueltas para siempre y no
            // hay forma de saber por qué.
            let detected: [DetectedGarment] = try await withThrowingTaskGroup(
                of: [DetectedGarment].self
            ) { group in
                let pipeline = self.pipeline
                group.addTask { try await pipeline.extractGarments(from: image) }
                group.addTask {
                    try await Task.sleep(for: .seconds(20))
                    throw PipelineError.timedOut
                }
                guard let first = try await group.next() else { return [] }
                group.cancelAll()
                return first
            }
            DiagnosticsLog.record(
                "IMPORT", "\(detected.count) prenda(s) en \(clock.duration(to: .now))"
            )
            for (index, garment) in detected.enumerated() {
                DiagnosticsLog.record(
                    "IMPORT",
                    "[\(index)] \(garment.kind.rawValue) conf \(String(format: "%.2f", garment.confidence))"
                        + " — " + garment.colors
                            .map { String(format: "%@ %.0f%%", $0.nameKey, $0.weight * 100) }
                            .joined(separator: ", ")
                )
            }
            guard !detected.isEmpty else {
                phase = .nothingFound(.noGarments)
                return
            }
            candidates = detected.map(ImportCandidate.init)
            await markDuplicates()

            // **La versión de catálogo, antes de enseñar nada.**
            //
            // Es lo que se va a ver. El recorte del segmentador rompe las
            // prendas largas —un pantalón se parte donde el cinturón o una
            // sombra cortan la clase— y la reconstrucción lo arregla; enseñar
            // primero el recorte roto y cambiarlo después es enseñar el fallo
            // y luego taparlo.
            //
            // Por eso se espera aquí, con el contador a la vista: son segundos
            // por prenda y una pantalla parada sin número parece colgada.
            // **Sin generar nada todavía.** Primero se revisa lo detectado:
            // ver `Phase.detected` y `confirmDetection()`.
            phase = .detected
        } catch PipelineError.noPersonFound {
            phase = .nothingFound(.noPerson)
        } catch PipelineError.visionUnavailable {
            phase = .nothingFound(.visionUnavailable)
        } catch let error as PipelineError {
            // Cada fallo del pipeline con su motivo: "noSubjectFound" y
            // "maskGenerationFailed" piden cosas distintas al usuario.
            DiagnosticsLog.record("IMPORT", "falla: \(error)", isProblem: true)
            phase = .nothingFound(.pipeline(error))
        } catch {
            DiagnosticsLog.record("IMPORT", "error: \(error)", isProblem: true)
            phase = .failed(error.localizedDescription)
        }
    }

    /// Cierra el paso de revisión: genera lo que haga falta y pasa a la ficha.
    ///
    /// La generación ocurre **aquí** y no al detectar, y solo para lo que se
    /// queda: es el único momento en el que se sabe qué es una prenda de
    /// verdad y qué era un trozo suelto.
    func confirmDetection() async {
        // **La versión de catálogo, apagada de momento.**
        //
        // Se queda comentada y no borrada: el camino entero —medir el recorte,
        // decidir si merece la pena, pedirla y guardarla— sigue escrito y
        // probado. Lo que no se hace es llamarlo, así que ninguna importación
        // llega al servidor y lo que se guarda es siempre el recorte local.
        //
        // await restyleKept()
        phase = .review
    }

    /// Añade una prenda que el detector no vio, recortada a dedo.
    ///
    /// Sin atributos deducidos: lo único que se sabe con certeza es la imagen y
    /// sus colores. El tipo y el nombre se corrigen en la ficha, que es donde
    /// están los controles para eso.
    func addManualCandidate(_ image: CGImage) {
        let cropped = ImmutableImage(image)
        let detected = DetectedGarment(
            kind: .other,
            confidence: 1,
            normalized: cropped,
            rawCrop: cropped,
            colors: ColorExtractor.dominantColors(in: image),
            featurePrint: nil
        )
        var candidate = ImportCandidate(detected)
        candidate.wasCorrectedByUser = true
        candidates.append(candidate)
        DiagnosticsLog.record("IMPORT", "prenda añadida a mano: \(candidates.count) en total")
    }

    /// Quita un candidato de la lista **del todo**.
    ///
    /// Distinto de desmarcarlo: desmarcado sigue ahí y se puede recuperar; esto
    /// es para lo que no es una prenda y solo estorba mientras eliges.
    func discard(candidateWithID id: UUID) {
        candidates.removeAll { $0.id == id }
    }

    /// Marca los candidatos que ya están en el armario.
    ///
    /// **Marcar, no descartar.** Un duplicado detectado se desmarca para que no
    /// se guarde por inercia, pero sigue en la lista, con su motivo a la vista
    /// y un toque para quedárselo igual. Borrarlo por su cuenta significaría
    /// que la app decide qué ropa tienes, y el 0,93 del coseno no es tan
    /// infalible como para eso: dos camisetas negras lisas se parecen mucho.
    private func markDuplicates() async {
        // Primero los que se repiten **dentro de esta misma foto**: la persona
        // de frente y de lado, o una prenda que el segmentador partió en dos
        // instancias casi iguales.
        let redundant = DuplicateDetector.redundantIndices(
            in: candidates.map(\.detected.featurePrint)
        )
        for index in redundant {
            candidates[index].duplicateOf = "otra de esta misma foto"
            candidates[index].isKept = false
        }

        // Y después contra el armario.
        guard let known = try? await wardrobe?.knownEmbeddings(), !known.isEmpty else { return }
        for index in candidates.indices where candidates[index].duplicateOf == nil {
            guard
                let match = DuplicateDetector.match(
                    for: candidates[index].detected.featurePrint, among: known
                )
            else { continue }
            candidates[index].duplicateOf = match.known.name
            candidates[index].isKept = false
            DiagnosticsLog.record(
                "DUPLICADO",
                "candidata \(index) se parece a \"\(match.known.name)\""
                    + " (\(String(format: "%.3f", match.similarity)))"
            )
        }
    }

    /// La versión de catálogo de las prendas de esta foto.
    ///
    /// ## Solo cuando la foto trae **una**
    ///
    /// Cada reconstrucción es una petición facturable. Con una prenda, generar
    /// antes de enseñar nada es lo correcto: es lo que se va a ver, y enseñar
    /// primero el recorte roto para cambiarlo después es enseñar el fallo y
    /// luego taparlo.
    ///
    /// Con varias, no. El detector se equivoca **hacia arriba**: un pantalón
    /// partido por el cinturón sale como tres prendas, y generar las tres es
    /// pagar tres veces por una foto que encima está mal detectada. Cuando hay
    /// más de una, cada ficha pide la suya al llegar a ella — así se paga por
    /// lo que de verdad se mira, y los recortes que ibas a descartar no cuestan
    /// nada.
    private func restyleKept() async {
        guard resolver != nil else { return }

        // **Solo lo que no salió bien.** Un recorte correcto es el que se
        // guarda; reconstruirlo cuesta dinero y no arregla nada. Lo que sí
        // merece la pena redibujar es lo que el segmentador partió, dejó a
        // medias o cortó por el encuadre — y eso se mide mirando el alfa, sin
        // preguntar a nadie. Ver `CutoutQuality`.
        let ids = candidates.filter { candidate in
            guard candidate.isKept, candidate.catalogImage == nil else { return false }
            let report = CutoutQuality.assess(candidate.cutout.cgImage)

            // Tres casos y solo uno cuesta dinero:
            //
            // - El recorte vale → se guarda tal cual.
            // - Le falta algo pero queda prenda de sobra → se reconstruye, que
            //   es justo para lo que sirve.
            // - No queda casi nada → **tampoco** se reconstruye: con eso el
            //   modelo no completa, inventa, y lo inventado se cobra igual.
            let verdict = if report.isGoodEnough {
                "vale tal cual"
            } else if report.isBeyondRepair {
                "demasiado roto: mejor recortarlo a mano"
            } else {
                "se reconstruye"
            }
            DiagnosticsLog.record("RECORTE", "\(candidate.displayName): \(report.summary) → \(verdict)")
            return report.needsReconstruction
        }.map(\.id)

        guard !ids.isEmpty else {
            DiagnosticsLog.record("CATÁLOGO", "los recortes valen: no se genera nada")
            return
        }
        phase = .generating(done: 0, total: ids.count)
        for (index, id) in ids.enumerated() {
            await restyle(candidateWithID: id)
            phase = .generating(done: index + 1, total: ids.count)
        }
    }

    /// Pide la versión de catálogo de una prenda.
    func restyle(candidateWithID id: UUID) async {
        guard
            let resolver,
            let index = candidates.firstIndex(where: { $0.id == id }),
            candidates[index].catalogImage == nil,
            !candidates[index].isRestyling
        else { return }

        candidates[index].isRestyling = true
        defer {
            if let index = candidates.firstIndex(where: { $0.id == id }) {
                candidates[index].isRestyling = false
            }
        }

        guard let jpeg = NormalizedJPEG.encode(candidates[index].cutout.cgImage) else {
            fail(id, "no se pudo preparar el JPEG del recorte")
            return
        }
        DiagnosticsLog.record("CATÁLOGO", "pidiendo la versión de catálogo · \(jpeg.count / 1024) KB")

        // **El error se mira, no se traga.**
        //
        // Aquí había un `try?`, y por eso todos los fallos —sin red, sin
        // sesión, la función rechazando la imagen por no fiel, un tiempo de
        // espera agotado— se veían igual desde fuera: la tarjeta decía "el
        // recorte es la foto real" y no había manera de saber cuál de los
        // cinco era.
        let data: Data
        do {
            data = try await resolver.restyle(jpeg)
        } catch {
            fail(id, describe(error))
            return
        }

        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let generated = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            fail(id, "la respuesta no es una imagen legible (\(data.count) bytes)")
            return
        }

        // **Y se recorta.** Lo que devuelve el modelo es una foto de estudio:
        // la prenda sobre blanco. Guardada así, en una balda o en un lienzo de
        // color se ve un cuadrado blanco alrededor de cada prenda. Se levanta
        // el sujeto y se encaja con el perfil de su categoría, igual que el
        // recorte de la foto real.
        let kind = candidates.first { $0.id == id }?.kind ?? .other
        guard let cutout = await CatalogExtractor.extract(generated, kind: kind) else {
            fail(id, "se generó pero no se pudo recortar del fondo")
            return
        }
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[index].catalogImage = ImmutableImage(cutout)
        candidates[index].catalogFailure = nil
    }

    /// Anota por qué no hubo versión de catálogo, **y lo enseña**.
    private func fail(_ id: UUID, _ reason: String) {
        DiagnosticsLog.record("CATÁLOGO", "falló: \(reason)", isProblem: true)
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[index].catalogFailure = reason
    }

    /// El error, en una frase que diga qué hacer.
    private func describe(_ error: Error) -> String {
        guard let resolverError = error as? ClothingResolverError else {
            let urlError = error as? URLError
            return urlError?.code == .notConnectedToInternet
                ? "sin conexión"
                : error.localizedDescription
        }
        switch resolverError {
        case .notConfigured: return "el resolutor no está configurado"
        case .rateLimited: return "el servidor va saturado; inténtalo en un momento"
        case let .transport(detail): return "no se pudo conectar — \(detail)"
        case let .badResponse(detail): return detail
        }
    }

    func setKeep(_ keep: Bool, forCandidateWithID id: UUID) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[index].isKept = keep
    }

    /// Corrige el nombre a mano.
    func setName(_ name: String, forCandidateWithID id: UUID) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Vaciarlo es volver al automático, no dejar la prenda sin nombre.
        candidates[index].editedName = trimmed.isEmpty ? nil : trimmed
    }

    /// Corrige el color a mano. Es el que más se equivoca: un azul marino y un
    /// negro están a muy poca distancia en Lab.
    func setColorName(_ name: String, forCandidateWithID id: UUID) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        candidates[index].editedColorName = trimmed.isEmpty ? nil : trimmed
        // El nombre automático lleva el color dentro: si venía del automático,
        // se recalcula solo al no estar editado a mano.
    }

    func setKind(_ kind: GarmentKind, forCandidateWithID id: UUID) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[index].kind = kind
        // Corregir a mano la categoría es la señal más fuerte que hay: a partir
        // de aquí la prenda no necesita revisión y no se vuelve a tocar.
        candidates[index].wasCorrectedByUser = true
    }

    /// El recorte hecho a mano sustituye al detectado.
    ///
    /// Y **tira la reconstrucción**: la que hubiera se generó a partir del
    /// recorte viejo, que es justo el que no valía. La nueva se pide sola al
    /// volver a la ficha.
    func setManualCrop(_ image: CGImage, forCandidateWithID id: UUID) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[index].manualCrop = ImmutableImage(image)
        candidates[index].catalogImage = nil
        candidates[index].catalogFailure = nil
        candidates[index].wasCorrectedByUser = true
        DiagnosticsLog.record("IMPORT", "recorte a mano aplicado")
    }

    var keptCount: Int { candidates.count { $0.isKept } }

    /// Escribe las imágenes a disco y da de alta las prendas.
    func save(imageStore: ImageStore, wardrobe: WardrobeActor) async throws -> Int {
        let kept = candidates.filter(\.isKept)
        guard !kept.isEmpty else { return 0 }

        var drafts: [GarmentDraft] = []
        drafts.reserveCapacity(kept.count)

        for candidate in kept {
            let key = try await imageStore.store(candidate.cutout.cgImage)
            let rawKey = try? await imageStore.store(candidate.detected.rawCrop.cgImage)
            // Bajo **la misma clave** que el recorte: es la misma prenda vista
            // de otra manera, así que borrarla se lleva las dos.
            if let catalog = candidate.catalogImage {
                try? await imageStore.storeCatalog(catalog.cgImage, for: key)
            }

            drafts.append(
                GarmentDraft(
                    kind: candidate.kind,
                    subcategory: candidate.detected.subcategory,
                    material: candidate.detected.material,
                    colors: candidate.colors,
                    seasons: candidate.detected.seasons,
                    tags: candidate.detected.tags,
                    normalizedImageKey: key,
                    rawCropImageKey: rawKey,
                    embedding: candidate.detected.featurePrint,
                    // Si el usuario ha confirmado la categoría, ya no hay duda
                    // que revisar: esa es la única señal fiable que existe en
                    // modo degradado.
                    confidence: candidate.wasCorrectedByUser ? 1 : candidate.detected.confidence,
                    proposedName: candidate.displayName,
                    brand: candidate.detected.brand
                )
            )
        }

        try await wardrobe.insert(drafts)
        return drafts.count
    }
}

/// Una prenda propuesta, con lo que el usuario decida encima.
struct ImportCandidate: Identifiable {
    let id = UUID()
    let detected: DetectedGarment
    var kind: GarmentKind
    var isKept: Bool
    var wasCorrectedByUser = false
    /// El nombre de la prenda que ya tienes y a la que se parece. `nil` cuando
    /// es nueva, que es lo normal.
    var duplicateOf: String?
    /// La versión de catálogo, si se ha generado. Se guarda junto al recorte,
    /// no en su lugar: el recorte es lo que estuvo delante de la cámara.
    var catalogImage: ImmutableImage?
    var isRestyling = false
    /// Por qué no la hay. `nil` = no se ha intentado o salió bien.
    var catalogFailure: String?

    /// El recorte hecho a dedo, si lo hay, **y manda sobre el detectado**.
    ///
    /// Aparte y no pisando `detected`: lo detectado sigue sirviendo —el color,
    /// el tipo, la marca salen de ahí— y además así se puede volver atrás sin
    /// repetir el análisis.
    var manualCrop: ImmutableImage?

    /// Lo que el usuario haya corregido a mano, si ha corregido algo.
    ///
    /// **Se equivocan.** El color sale de un k-means y una zapatilla azul
    /// marino se mide como negra más veces de las que parece; el nombre se
    /// construye con ese color. Guardar la corrección aparte —en vez de pisar
    /// lo detectado— deja ver las dos cosas y permite volver atrás.
    var editedName: String?
    var editedColorName: String?

    /// El nombre con el que se va a guardar.
    var displayName: String {
        editedName ?? GarmentNaming.name(
            kind: kind,
            subcategory: detected.subcategory,
            colors: colors,
            brand: detected.brand
        )
    }

    /// Los colores, con la corrección aplicada si la hay.
    var colors: [NamedColor] {
        guard let editedColorName, var first = detected.colors.first else {
            return detected.colors
        }
        first = NamedColor(
            nameKey: editedColorName,
            red: first.red, green: first.green, blue: first.blue,
            weight: first.weight
        )
        return [first] + detected.colors.dropFirst()
    }

    init(_ detected: DetectedGarment) {
        self.detected = detected
        self.kind = detected.kind
        // Se marcan todas por defecto: es más rápido descartar una que marcar
        // cuatro, y lo normal es quedárselas casi todas.
        self.isKept = true
    }

    /// El recorte que vale: el de dedo si lo hay, y si no el detectado.
    var cutout: ImmutableImage { manualCrop ?? detected.normalized }

    var image: Image { Image(decorative: cutout.cgImage, scale: 1) }
}
