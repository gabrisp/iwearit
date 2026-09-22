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
        onProgress: @Sendable @escaping (ScanProgress) async -> Void,
        onDiscovery: @Sendable @escaping (ScanDiscovery) async -> Void
    ) async -> ScanProgress {
        isCancelled = false
        harvest.removeAll()

        let assets = Self.candidateAssets()
        #if DEBUG
        Logger(subsystem: "com.gabrisp.iWearIt", category: "scan")
            .notice("candidatas: \(assets.count, privacy: .public)")
        #endif
        var progress = ScanProgress()
        progress.totalPhotos = min(assets.count, limit.map { startIndex + $0 } ?? assets.count)

        var pending: [GarmentDraft] = []
        var lastReport = ContinuousClock.now

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

            // Sin `autoreleasepool`: no funciona a través de un `await`, así
            // que envolver esta llamada sería decorativo. Lo que de verdad
            // mantiene la memoria a raya es que cada foto se pide ya reducida
            // (256 px para la puerta barata, 1024 para el resto) y que los
            // buffers mueren al salir de `process`, sin acumularse en el bucle.
            let drafts = await process(asset: asset, onDiscovery: onDiscovery)

            switch drafts {
            case .skippedInCloud:
                progress.skippedInCloud += 1
            case let .found(found):
                if !found.isEmpty {
                    progress.outfitsFound += 1
                    progress.garmentsFound += found.count
                    pending.append(contentsOf: found)
                }
            case .nothing:
                break
            }

            progress.photosProcessed = index - startIndex + 1

            if pending.count >= Self.commitBatchSize {
                if inserts {
                    try? await wardrobe.insert(pending)
                } else {
                    harvest.append(contentsOf: pending)
                }
                pending.removeAll(keepingCapacity: true)
            }

            if ContinuousClock.now - lastReport > Self.progressInterval {
                lastReport = .now
                await onProgress(progress)
            }
        }

        if !pending.isEmpty {
            if inserts {
                try? await wardrobe.insert(pending)
            } else {
                harvest.append(contentsOf: pending)
            }
        }
        await onProgress(progress)
        return progress
    }

    // MARK: - Una foto

    private enum PhotoOutcome {
        case nothing
        case skippedInCloud
        case found([GarmentDraft])
    }

    private func process(
        asset: PHAsset,
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
            guard let key = try? await imageStore.store(garment.normalized.cgImage) else { continue }
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
        if !pieces.isEmpty, let photo = Self.downscaled(full, maxSide: 520) {
            await onDiscovery(ScanDiscovery(photo: ImmutableImage(photo), pieces: pieces))
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
    static func candidateAssets() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d AND NOT ((mediaSubtype & %d) != 0) AND NOT ((mediaSubtype & %d) != 0)",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoScreenshot.rawValue,
            PHAssetMediaSubtype.photoPanorama.rawValue
        )
        options.includeAssetSourceTypes = [.typeUserLibrary]
        return PHAsset.fetchAssets(with: options)
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
