import CoreGraphics
import Foundation
import os
import Photos
import WKCore
import WKPersistence
import WKVision

/// Escanea la galería y llena el armario.
///
/// ## El embudo
///
/// Una galería típica tiene miles de fotos y casi ninguna sirve. Procesarlas
/// todas al completo sería tirar horas de batería, así que cada etapa descarta
/// antes de que la siguiente gaste:
///
/// 1. **Metadatos** — capturas de pantalla, panorámicas. Gratis.
/// 2. **Miniatura de 256 px + detección de persona** — ~3 ms, y mata el grueso.
/// 3. **Foto a 1024 px + segmentación** — ~120 ms, solo para las que llegan.
///
/// ## Reanudable
///
/// iOS no da CPU sostenida en segundo plano para visión, así que el escaneo se
/// pausa al salir de la app. El cursor se guarda cada lote para poder continuar
/// donde se quedó en vez de empezar de cero — que con 4.000 fotos es la
/// diferencia entre una molestia y un abandono.
public actor GalleryScanner {

    /// Lote de escrituras. Un insert por foto convertiría 3.000 fotos en 3.000
    /// transacciones; así son 120.
    static let commitBatchSize = 25

    /// Cada cuánto se informa a la UI, como mucho.
    ///
    /// A 20 fotos por segundo, publicar cada una reevaluaría la pantalla de
    /// progreso 20 veces por segundo para mover un número. Esto lo acota.
    static let progressInterval: Duration = .milliseconds(200)

    private let pipeline: GarmentPipeline
    private let imageStore: ImageStore
    private let wardrobe: WardrobeActor

    private var isCancelled = false
    /// Lo que ya se ha visto: en el armario, en lo pendiente y en este mismo
    /// escaneo. Ver `ScanDeduper`.
    private var deduper = ScanDeduper()

    /// Lo encontrado y **no guardado**, cuando se escanea sin insertar.
    ///
    /// El escaneo del onboarding recorre la galería entera y encuentra lo que
    /// encuentra; decidir qué entra al armario es del usuario, no del escáner.
    /// Los recortes ya están escritos en disco —eso es inevitable, hay que
    /// verlos para elegir— pero ninguna prenda existe hasta que alguien dice
    /// que sí.
    public private(set) var harvest: [GarmentDraft] = []

    public init(pipeline: GarmentPipeline, imageStore: ImageStore, wardrobe: WardrobeActor) {
        self.pipeline = pipeline
        self.imageStore = imageStore
        self.wardrobe = wardrobe
    }

    public func cancel() { isCancelled = true }

    /// Recorre la galería.
    ///
    /// - Parameters:
    ///   - startIndex: desde dónde continuar. 0 para empezar de cero.
    ///   - limit: tope de fotos a mirar. Es el gate del plan gratuito.
    ///   - inserts: si lo encontrado entra al armario directamente. `false`
    ///     en el onboarding: ahí se cosecha y se elige después, en
    ///     `harvest`.
    public func scan(
        startIndex: Int = 0,
        limit: Int? = nil,
        inserts: Bool = true,
        /// Parar al llegar a tantas prendas **distintas**. El onboarding no
        /// necesita la galería entera para arrancar un armario: con unas
        /// decenas de prendas buenas ya hay armario, y seguir era dejar al
        /// usuario mirando cómo se repasan seis años de fotos.
        stopAfter: Int? = nil,
        onProgress: @Sendable @escaping (ScanProgress) async -> Void,
        /// Una foto con alguien que empieza a analizarse. Ver `ScanLook`.
        onLook: @Sendable @escaping (ScanLook) async -> Void = { _ in },
        onDiscovery: @Sendable @escaping (ScanDiscovery) async -> Void
    ) async -> ScanProgress {
        isCancelled = false
        harvest.removeAll()
        // **Lo que ya existe no se vuelve a proponer.** Sin esto, escanear
        // otra vez —o reiniciar el onboarding— traía de nuevo todo lo que ya
        // estaba en el armario o esperando a que lo aceptaras.
        deduper = ScanDeduper(known: (try? await wardrobe.fingerprints()) ?? .init())

        let assets = Self.candidateAssets()
        #if DEBUG
        Logger(subsystem: "com.gabrisp.iWearIt", category: "scan")
            .notice("candidatas: \(assets.count, privacy: .public)")
        #endif
        var progress = ScanProgress()
        progress.totalPhotos = min(assets.count, limit.map { startIndex + $0 } ?? assets.count)

        var pending: [GarmentDraft] = []
        /// Las fechas de las fotos de lo pendiente, en el mismo orden.
        var pendingDates: [Date?] = []
        var lastReport = ContinuousClock.now
        /// Cuándo se hizo la última foto que **dio** prendas. Ver
        /// `sameOutfitWindow`.
        var lastProductiveDate: Date?
        var uniqueFound = 0

        for index in startIndex..<progress.totalPhotos {
            if isCancelled { break }

            // Presupuesto por foto y no por sesión: el iPhone se calienta *a
            // mitad* del escaneo, que es justo cuando hay que bajar el ritmo.
            let budget = ScanBudget.current()
            if budget.shouldPause {
                progress.isPaused = true
                progress.pauseReason = budget.reason
                await onProgress(progress)
                try? await Task.sleep(for: .seconds(20))
                continue
            }
            progress.isPaused = false
            progress.pauseReason = budget.reason

            let asset = assets.object(at: index)

            // **Una foto ya mirada no se vuelve a mirar**: sus prendas ya
            // están en el armario o esperando.
            if deduper.hasSeenPhoto(asset.localIdentifier) {
                progress.photosProcessed = index - startIndex + 1
                continue
            }

            // **La misma ropa, el mismo rato.** Las fotos de una misma tarde
            // —una ráfaga, diez fotos en la misma cena— llevan la misma ropa, y
            // cada una la proponía otra vez: la camiseta aparecía seis veces.
            // Si la foto es de muy poco antes de la última que dio prendas, se
            // salta sin gastar un milisegundo en ella. Es además lo que más
            // acelera el escaneo: en una galería normal, la mayoría de fotos
            // con gente vienen en tandas así.
            if let last = lastProductiveDate, let date = asset.creationDate,
               abs(last.timeIntervalSince(date)) < Self.sameOutfitWindow {
                progress.photosProcessed = index - startIndex + 1
                continue
            }

            // Sin `autoreleasepool`: no funciona a través de un `await`, así
            // que envolver esta llamada sería decorativo. Lo que de verdad
            // mantiene la memoria a raya es que cada foto se pide ya reducida
            // (256 px para la puerta barata, 1024 para el resto) y que los
            // buffers mueren al salir de `process`, sin acumularse en el bucle.
            // **Solo fotos hechas con la cámara.** Lo guardado de otras apps
            // —memes, capturas de Instagram, fotos de WhatsApp— no es ropa
            // tuya. Ver `isCameraCapture`.
            guard Self.isCameraCapture(asset) else {
                progress.photosProcessed = index - startIndex + 1
                continue
            }

            let drafts = await process(asset: asset, onLook: onLook, onDiscovery: onDiscovery)

            switch drafts {
            case .skippedInCloud:
                progress.skippedInCloud += 1
            case let .found(found):
                if !found.isEmpty {
                    progress.outfitsFound += 1
                    progress.garmentsFound += found.count
                    pending.append(contentsOf: found)
                    pendingDates.append(contentsOf: Array(repeating: asset.creationDate, count: found.count))
                    uniqueFound += found.count
                    lastProductiveDate = asset.creationDate
                }
            case .nothing:
                break
            }

            progress.photosProcessed = index - startIndex + 1

            if pending.count >= Self.commitBatchSize {
                await flush(pending, dates: pendingDates, inserts: inserts)
                pending.removeAll(keepingCapacity: true)
                pendingDates.removeAll(keepingCapacity: true)
            }

            // Suficiente: se para aquí y se informa de que ha acabado.
            if let stopAfter, uniqueFound >= stopAfter {
                progress.photosProcessed = index - startIndex + 1
                break
            }

            if ContinuousClock.now - lastReport > Self.progressInterval {
                lastReport = .now
                await onProgress(progress)
            }
        }

        if !pending.isEmpty {
            await flush(pending, dates: pendingDates, inserts: inserts)
        }
        await onProgress(progress)
        return progress
    }

    /// Cuánto tiempo entre dos fotos para darlas por **la misma ropa**.
    ///
    /// Hora y media: lo que dura una comida, una tarde de paseo, una ráfaga.
    /// Menos dejaba pasar las series; más empezaba a saltarse cambios de ropa
    /// de verdad —la de por la mañana y la de por la noche—.
    static let sameOutfitWindow: TimeInterval = 90 * 60

    /// Guarda un lote: al armario, o como pendiente.
    ///
    /// **Pendiente en disco y no en memoria.** Lo encontrado vivía en un array
    /// mientras el usuario decidía: saltar el paso, cerrar la app o que se
    /// colgara el escaneo lo tiraba todo. Ahora cada lote se queda guardado
    /// según se encuentra. Ver `PendingGarment`.
    private func flush(_ drafts: [GarmentDraft], dates: [Date?], inserts: Bool) async {
        if inserts {
            try? await wardrobe.insert(drafts)
        } else {
            try? await wardrobe.insertPending(
                zip(drafts, dates).map { (draft: $0, photoDate: $1) }
            )
            harvest.append(contentsOf: drafts)
        }
    }

    // MARK: - Una foto

    private enum PhotoOutcome {
        case nothing
        case skippedInCloud
        case found([GarmentDraft])
    }

    private func process(
        asset: PHAsset,
        onLook: @Sendable @escaping (ScanLook) async -> Void,
        onDiscovery: @Sendable @escaping (ScanDiscovery) async -> Void
    ) async -> PhotoOutcome {
        // Etapa barata: miniatura y ¿hay alguien?
        guard let thumbnail = await Self.image(for: asset, targetSize: 256) else {
            return .skippedInCloud
        }
        guard await Self.containsPerson(thumbnail) else { return .nothing }

        // Etapa cara: solo para las supervivientes.
        guard let full = await Self.image(for: asset, targetSize: 1024) else {
            return .skippedInCloud
        }
        // Se enseña **ya**, antes de segmentar: es la foto que se está
        // mirando, y la pantalla tiene que ir al paso del escáner.
        let shown = Self.downscaled(full, maxSide: 520)
        if let shown {
            await onLook(ScanLook(photoID: asset.localIdentifier, photo: ImmutableImage(shown)))
        }

        guard let found = try? await pipeline.extractGarments(from: full), !found.isEmpty else {
            return .nothing
        }

        // **Solo lo que se ve bien.** El escaneo es lo primero que el usuario
        // ve de la app: una prenda mordida, borrosa o diminuta resta más de lo
        // que suma. Mejor diez prendas buenas que treinta regulares.
        let detected = found.filter(Self.isShowcaseQuality)
        if detected.count < found.count {
            DiagnosticsLog.record(
                "ESCANEO", "\(found.count - detected.count) de \(found.count) descartadas por calidad"
            )
        }
        guard !detected.isEmpty else { return .nothing }

        var drafts: [GarmentDraft] = []
        var pieces: [ScanDiscovery.Piece] = []
        for garment in detected {
            // **Casi igual a algo ya visto: fuera.** Antes de escribir nada y
            // antes de enseñarlo, para que la pantalla del escaneo no vaya
            // soltando la misma camiseta foto tras foto.
            if deduper.isNearDuplicate(garment.featurePrint) { continue }
            guard let key = try? await imageStore.store(garment.normalized.cgImage) else { continue }
            // El mismo recorte exacto —misma clave— también.
            guard deduper.accept(key: key, embedding: garment.featurePrint) else { continue }
            if let small = Self.downscaled(garment.rawCrop.cgImage, maxSide: 360) {
                pieces.append(ScanDiscovery.Piece(
                    image: ImmutableImage(small),
                    sourceRect: garment.sourceRect,
                    kind: garment.kind
                ))
            }
            drafts.append(
                GarmentDraft(
                    kind: garment.kind,
                    subcategory: garment.subcategory,
                    material: garment.material,
                    colors: garment.colors,
                    seasons: garment.seasons,
                    tags: garment.tags,
                    normalizedImageKey: key,
                    sourcePhotoLocalIdentifier: asset.localIdentifier,
                    embedding: garment.featurePrint,
                    confidence: garment.confidence,
                    brand: garment.brand
                )
            )
        }
        // La foto ya está mirada, dé lo que dé.
        deduper.markPhoto(asset.localIdentifier)
        if !pieces.isEmpty, let photo = shown {
            await onDiscovery(ScanDiscovery(
                photoID: asset.localIdentifier, photo: ImmutableImage(photo), pieces: pieces
            ))
        }
        return .found(drafts)
    }

    /// Si una prenda es digna de enseñarse en el escaneo.
    static func isShowcaseQuality(_ garment: DetectedGarment) -> Bool {
        // Por encima del techo del modo degradado: lo que sale de ahí es una
        // conjetura por la forma.
        guard garment.confidence > GarmentPipeline.degradedConfidenceCeiling else { return false }
        // Diminuta en la foto: al ampliarla para el armario se ve fatal.
        guard min(garment.rawCrop.width, garment.rawCrop.height) >= 140 else { return false }
        return CutoutQuality.assess(garment.normalized.cgImage).isGoodEnough
    }

    static func downscaled(_ image: CGImage, maxSide: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let scale = Double(maxSide) / Double(longest)
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - PhotoKit

    /// Las fotos que vale la pena mirar.
    ///
    /// Se descartan por metadatos antes de tocar un solo píxel: una captura de
    /// pantalla no lleva a nadie puesto nada, y una panorámica deforma tanto
    /// que la segmentación no sirve.
    ///
    /// ## Solo lo reciente
    ///
    /// Una galería de verdad tiene cien mil fotos, y la ropa de hace seis años
    /// ya no está en el armario. Así que **el último año y como mucho las
    /// últimas 10.000**: es lo que llevas ahora, y es lo que cabe en un
    /// escaneo que se termina mirando.
    ///
    /// ## Solo fotos de cámara, en bruto
    ///
    /// Lado corto de al menos 1.500 px ya en la consulta: una foto de cámara
    /// de iPhone tiene 2.000-3.000, y lo guardado de otras apps —Instagram a
    /// 1.080, WhatsApp a 1.200— se queda fuera sin tocar un píxel. El resto
    /// del filtro, en `isCameraCapture`.
    static let recentWindow: TimeInterval = 365 * 24 * 60 * 60
    static let maximumCandidates = 10_000
    static let minimumCameraSide = 1_500

    static func candidateAssets() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d AND NOT ((mediaSubtype & %d) != 0) AND NOT ((mediaSubtype & %d) != 0)"
                + " AND creationDate >= %@ AND pixelWidth >= %d AND pixelHeight >= %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoScreenshot.rawValue,
            PHAssetMediaSubtype.photoPanorama.rawValue,
            Date(timeIntervalSinceNow: -recentWindow) as NSDate,
            minimumCameraSide,
            minimumCameraSide
        )
        options.includeAssetSourceTypes = [.typeUserLibrary]
        options.fetchLimit = maximumCandidates
        return PHAsset.fetchAssets(with: options)
    }

    /// Si una foto la hizo la cámara, o viene de otra app.
    ///
    /// No hay un campo que lo diga, así que se juntan pistas baratas —solo
    /// metadatos, ningún píxel—:
    ///
    /// - **Fuera** PNG, GIF y WebP: la cámara nunca los produce; son capturas
    ///   de otros dispositivos, stickers e imágenes descargadas.
    /// - **Dentro** si es Live Photo, retrato o HDR, si es HEIC o RAW, o si
    ///   lleva ubicación: son cosas que solo hace la cámara, y las apps de
    ///   mensajería quitan la ubicación al guardar.
    /// - Un JPEG sin nada de eso **pasa**: la cámara en "Más compatible" hace
    ///   JPEG, y el tamaño mínimo de la consulta ya ha echado lo de las apps.
    static func isCameraCapture(_ asset: PHAsset) -> Bool {
        let resources = PHAssetResource.assetResources(for: asset)
        let photo = resources.first { $0.type == .photo || $0.type == .fullSizePhoto } ?? resources.first
        let type = photo?.uniformTypeIdentifier.lowercased() ?? ""

        let exported = ["public.png", "com.compuserve.gif", "org.webmproject.webp"]
        if exported.contains(type) { return false }

        let cameraSubtypes: PHAssetMediaSubtype = [.photoLive, .photoDepthEffect, .photoHDR]
        if !asset.mediaSubtypes.intersection(cameraSubtypes).isEmpty { return true }
        if type.contains("heic") || type.contains("heif") || type.contains("raw") || type.contains("dng") {
            return true
        }
        if asset.location != nil { return true }
        return type.contains("jpeg") || type.isEmpty
    }

    /// Cuánto se espera una foto antes de darla por perdida.
    ///
    /// Sin este tope el escaneo se cuelga: `requestImage` **no garantiza** que
    /// llame al handler con un resultado final. Con `isNetworkAccessAllowed =
    /// false` y una foto que solo vive en iCloud, puede entregar únicamente una
    /// versión degradada y no volver a llamar nunca. La continuación se queda
    /// sin reanudar y el bucle entero se detiene para siempre en esa foto.
    static let imageTimeout: Duration = .seconds(4)

    /// Pide una foto **sin permitir descarga de iCloud**.
    ///
    /// Con `isNetworkAccessAllowed = true`, escanear una galería en iCloud se
    /// traería gigabytes en silencio, con la factura de datos que eso supone.
    /// Las que solo están en la nube se cuentan aparte y se ofrecen después.
    static func image(for asset: PHAsset, targetSize: CGFloat) async -> CGImage? {
        let request = ImageRequest(asset: asset, targetSize: targetSize)

        return await withTaskGroup(of: CGImage?.self) { group in
            group.addTask { await request.run() }
            group.addTask {
                try? await Task.sleep(for: imageTimeout)
                return nil
            }
            // El primero que conteste manda; el otro se cancela.
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// Una petición a PhotoKit, en forma de valor.
    ///
    /// `PHAsset` y `PHImageRequestOptions` no son `Sendable`, así que no pueden
    /// cruzar a una tarea hija tal cual. Son objetos inmutables una vez creados
    /// —el asset es un snapshot y las opciones se construyen dentro— de modo
    /// que envolverlos con la justificación a la vista es preferible a esparcir
    /// `nonisolated(unsafe)`.
    private struct ImageRequest: @unchecked Sendable {
        let asset: PHAsset
        let targetSize: CGFloat

        func run() async -> CGImage? {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isSynchronous = false

            let size = CGSize(width: targetSize, height: targetSize)

            return await withCheckedContinuation { continuation in
                // Una sola reanudación, pase lo que pase: `requestImage` puede
                // llamar al handler varias veces (degradada y luego final), y
                // reanudar dos veces una continuación **revienta** el proceso.
                let resumed = OSAllocatedUnfairLock(initialState: false)

                PHImageManager.default().requestImage(
                    for: asset, targetSize: size, contentMode: .aspectFit, options: options
                ) { image, info in
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    let failed = info?[PHImageErrorKey] != nil
                    let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false

                    // Una degradada no es la respuesta: se espera la buena. Un
                    // error o una cancelación sí lo son, y hay que reanudar o
                    // el bucle se queda esperando para siempre.
                    guard !isDegraded || failed || cancelled else { return }

                    let shouldResume = resumed.withLock { alreadyResumed -> Bool in
                        guard !alreadyResumed else { return false }
                        alreadyResumed = true
                        return true
                    }
                    guard shouldResume else { return }
                    // **Derecha.** `UIImage.cgImage` da los píxeles en crudo y
                    // una foto vertical de iPhone los guarda en horizontal: a
                    // Vision le llegaba todo tumbado.
                    continuation.resume(
                        returning: (failed || cancelled)
                            ? nil
                            : image.flatMap(UprightImage.cgImage(from:))
                    )
                }
            }
        }
    }

    static func containsPerson(_ image: CGImage) async -> Bool {
        (try? await VisionStages.containsPerson(image)) ?? false
    }
}

/// Lo que ya se ha visto, para no proponerlo dos veces.
///
/// Tres filtros, del más barato al más caro:
///
/// 1. **La foto.** Una foto que ya dio prendas —en este escaneo o en uno
///    anterior— no se vuelve a mirar.
/// 2. **El recorte exacto.** El `ImageStore` direcciona por contenido: dos
///    recortes idénticos tienen la misma clave.
/// 3. **La prenda casi igual.** La misma camiseta en dos fotos distintas no da
///    dos recortes idénticos, pero sí dos vectores casi iguales. El listón es
///    el de `DuplicateDetector`, alto a propósito: dos camisetas negras
///    distintas pasan de 0,85 sin ser la misma.
///
/// Los vectores se guardan ya normalizados: se comparan contra cada prenda
/// nueva, y normalizar cientos de vectores por cada una sería trabajo repetido.
struct ScanDeduper {
    private var imageKeys: Set<String> = []
    private var photoIDs: Set<String> = []
    /// Las direcciones, separadas por longitud: los vectores de TinyCLIP y los
    /// de `VNFeaturePrint` viven en espacios distintos y no se comparan.
    private var directions: [Int: [[Float]]] = [:]

    init() {}

    init(known: WardrobeActor.Fingerprints) {
        imageKeys = known.imageKeys
        photoIDs = known.photoIDs
        for embedding in known.embeddings { remember(embedding) }
    }

    func hasSeenPhoto(_ id: String) -> Bool { photoIDs.contains(id) }

    mutating func markPhoto(_ id: String) { photoIDs.insert(id) }

    func isNearDuplicate(_ embedding: Data?) -> Bool {
        guard
            let embedding,
            let direction = EmbeddingMath.direction(of: EmbeddingMath.decode(embedding))
        else { return false }
        for other in directions[direction.count] ?? [] {
            if EmbeddingMath.similarity(direction, other) >= DuplicateDetector.threshold {
                return true
            }
        }
        return false
    }

    /// Lo da por visto. `false` si el recorte exacto ya estaba.
    mutating func accept(key: String, embedding: Data?) -> Bool {
        guard imageKeys.insert(key).inserted else { return false }
        remember(embedding)
        return true
    }

    private mutating func remember(_ embedding: Data?) {
        guard
            let embedding,
            let direction = EmbeddingMath.direction(of: EmbeddingMath.decode(embedding))
        else { return }
        directions[direction.count, default: []].append(direction)
    }
}
