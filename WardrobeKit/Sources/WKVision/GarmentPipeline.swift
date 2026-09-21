import CoreGraphics
import Foundation
import Foundation
import VideoToolbox
import Vision
import WKCore

/// Extrae prendas de una foto.
///
/// Esta es la **ruta degradada**: solo APIs nativas de Vision, sin modelos
/// descargados. Es la que se construye primero a propósito, porque tiene que
/// funcionar sin red, sin Appwrite y en cualquier iPhone con iOS 18. Cuando en
/// F7 existan SegFormer y MobileCLIP, sustituirán las etapas 2 y 4 sin tocar
/// esta estructura.
///
/// Corre en un actor propio, fuera del hilo principal. Lo que cruza al llamante
/// son `DetectedGarment`, que son `Sendable`.
public actor GarmentPipeline {

    /// Confianza máxima en modo degradado.
    ///
    /// Nunca sube de aquí porque la categoría sale de **dónde cae** la prenda
    /// respecto al esqueleto, no de reconocerla. Marcar como segura una
    /// deducción geométrica sería mentir, y además evita que estas prendas se
    /// salten la pantalla de revisión.
    public static let degradedConfidenceCeiling = 0.35

    /// Área mínima de una instancia respecto a la foto. Por debajo es ruido:
    /// un botón, un reflejo, una mano.
    ///
    /// **En la duda, no.** Perderse una prenda diminuta se arregla añadiéndola
    /// a mano en dos toques; aparecer con tres recortes de nada obliga a
    /// borrarlos uno a uno y a desconfiar del resto.
    static let minimumAreaFraction = 0.03

    /// Por encima de esto, la región es casi toda piel y no una prenda.
    static let maximumSkinFraction = 0.40

    /// El segmentador de prendas, si el modelo está descargado.
    ///
    /// Opcional a propósito: sin él la app **sigue funcionando** por la ruta
    /// degradada. Es lo que permite usar la app sin red, antes de descargar
    /// nada, y si el usuario declina la descarga.
    private let segmenter: ClothesSegmenter?
    /// Embedder y banco de prompts. Van juntos o no van: el banco solo
    /// significa algo contra embeddings del mismo checkpoint.
    private let embedder: GarmentEmbedder?
    private let promptBank: PromptBank?

    /// Si se lee la marca con OCR. Ver `readBrand(in:)`.
    private let readsBrands: Bool

    /// Si se descartan las fotos que Vision considera "de utilidad".
    ///
    /// **Solo en el escaneo masivo.** En una galería, descartar recibos,
    /// capturas y documentos antes de segmentar ahorra muchísimo trabajo. Pero
    /// `isUtility` marca también las **fotos de producto sobre fondo liso** —una
    /// prenda sola sobre blanco es justo lo que ese clasificador llama utility—
    /// y aplicarlo a una foto que el usuario acaba de elegir a mano significa
    /// devolver "no he encontrado nada" sin haber mirado.
    ///
    /// Si el usuario elige una foto, se analiza. Él ya ha decidido que ahí hay
    /// una prenda.
    private let skipsUtilityImages: Bool

    /// Si una clase puede dar más de una prenda.
    ///
    /// **Apagado al añadir una prenda a mano.** Ahí se está fotografiando una
    /// cosa, y partir solo puede equivocarse. Encendido en el escaneo de la
    /// galería, donde una foto sí puede traer dos prendas de la misma clase.
    private let splitsInstances: Bool

    /// Si se consulta al resolutor **para todas** las prendas.
    ///
    /// Encendido al añadir una prenda a mano: ahí se está mirando una sola
    /// ficha y lo que se espera es que esté bien, no que esté barata. Apagado
    /// en el escaneo de la galería, donde mil fotos a unos céntimos cada una
    /// sería una factura y no una función.
    private let alwaysAsksRemote: Bool

    /// A quién preguntar cuando el dispositivo no llega. `nil` = a nadie, y
    /// entonces todo sale de aquí.
    ///
    /// **No es el camino normal.** Cuesta dinero y un segundo y medio, así que
    /// entra solo donde el resultado local es dudoso: ver `needsRemoteHelp`.
    private let resolver: (any ClothingResolving)?

    public init(
        segmenter: ClothesSegmenter? = nil,
        embedder: GarmentEmbedder? = nil,
        promptBank: PromptBank? = nil,
        resolver: (any ClothingResolving)? = nil,
        readsBrands: Bool = true,
        skipsUtilityImages: Bool = false,
        splitsInstances: Bool = true,
        alwaysAsksRemote: Bool = false
    ) {
        self.splitsInstances = splitsInstances
        self.alwaysAsksRemote = alwaysAsksRemote
        self.segmenter = segmenter
        self.embedder = embedder
        self.promptBank = promptBank
        self.resolver = resolver
        self.readsBrands = readsBrands
        self.skipsUtilityImages = skipsUtilityImages
    }

    // MARK: - Cuándo merece preguntar fuera

    /// Confianza local por debajo de la cual se pregunta.
    static let remoteConfidenceFloor = 0.55
    /// Y el listón de marca: con una lectura de OCR dudosa, confirmarla fuera
    /// es la diferencia entre escribirla y dejarla en blanco.
    static let remoteBrandFloor = BrandVerdict.displayThreshold

    /// Si esta prenda merece una consulta remota.
    ///
    /// Tres motivos, y ninguno es "por si acaso":
    ///
    /// 1. **La categoría es dudosa.** Una prenda mal clasificada acaba en la
    ///    balda equivocada y estorba en todas las búsquedas.
    /// 2. **No hay subcategoría.** Sin ella el nombre queda en "Top en gris",
    ///    que no distingue una camisa de una sudadera.
    /// 3. **Hay una marca a medio leer.** Ni escribirla ni tirarla es lo peor
    ///    de los dos mundos; preguntar la resuelve.
    ///
    /// Una prenda bien resuelta en el dispositivo **no se pregunta**. Ese es el
    /// caso normal y tiene que seguir costando cero.
    static func needsRemoteHelp(
        confidence: Double,
        subcategory: String?,
        brandEvidence: [BrandEvidence]
    ) -> Bool {
        if confidence < remoteConfidenceFloor { return true }
        if subcategory == nil { return true }
        let best = BrandVerdict.resolve(brandEvidence)
        if best == nil, !brandEvidence.isEmpty { return true }
        return false
    }

    /// - Parameter image: la foto original, sin recortar.
    /// - Returns: una prenda por franja utilizable, de arriba abajo.
    /// - Parameter image: la foto original, sin recortar.
    /// - Returns: una prenda por franja utilizable, de arriba abajo.
    ///
    /// ## Qué ruta se toma y por qué en ese orden
    ///
    /// **Primero se mira si hay alguien en la foto**, que cuesta unos
    /// milisegundos, y de ahí sale todo lo demás:
    ///
    /// - **Sin persona** — la foto es de la prenda sola: colgada, sobre la
    ///   cama, la del catálogo. La máscara de sujeto la recorta entera y
    ///   perfecta en ~40 ms. Pasar antes por el segmentador es tirar 60 ms más
    ///   todo el post-proceso para que devuelva vacío: está entrenado con
    ///   **gente vestida** y sin gente no reconoce clases.
    /// - **Con persona y con modelo** — segmentación por píxel, que es la
    ///   única que separa la camiseta del pantalón.
    /// - **Con persona y sin modelo** — corte por articulaciones, que es lo
    ///   mejor que dan las APIs nativas.
    ///
    /// Antes se probaba el segmentador siempre y la máscara de sujeto solo
    /// como último recurso: para el caso más común de "añadir una prenda" eso
    /// era pagar la ruta cara entera para acabar usando la barata.
    public func extractGarments(from image: CGImage) async throws -> [DetectedGarment] {
        if skipsUtilityImages, (try? await VisionStages.isUtilityImage(image)) == true {
            return []
        }

        DiagnosticsLog.record(
            "PIPELINE",
            "foto \(image.width)×\(image.height) · segmentador \(segmenter == nil ? "NO cargado" : "cargado")"
                + " · embedder \(embedder == nil ? "NO" : "sí")"
        )

        // ## El segmentador primero, y la pose solo si no lo hay
        //
        // Antes esto empezaba preguntando a Vision por la pose para decidir la
        // ruta. Era **la pregunta equivocada**: lo que se busca son prendas, y
        // el segmentador las encuentra —con su clase y su recorte— haya o no
        // haya alguien puesto. Saber si hay una persona no añadía nada que el
        // mapa de clases no dijera mejor.
        //
        // Y costaba caro. La pose es una petición neuronal, así que con la ANE
        // ocupada no falla: **no vuelve**. Ocho segundos de tope antes de
        // empezar a trabajar, para una respuesta que se iba a ignorar.
        //
        // La pose sigue haciendo falta, pero solo donde de verdad no hay nada
        // mejor: sin modelo descargado, cortar por articulaciones es lo único
        // que queda.
        if let segmenter {
            if let garments = try? await extractWithSegmenter(segmenter, from: image),
               !garments.isEmpty {
                return await refinedOnSolidBackground(garments, from: image)
            }
            DiagnosticsLog.record(
                "PIPELINE",
                "el segmentador no reconoce ropa; se mira si hay alguien en la foto"
            )

            // **Con persona, levantar el sujeto está prohibido.**
            //
            // `GenerateForegroundInstanceMaskRequest` separa objeto de fondo y
            // no sabe qué es una prenda: con alguien en la foto, el sujeto es
            // **la persona entera**, y el resultado era un recorte del usuario
            // dado de alta como una prenda. Es la clase de fallo que no se
            // arregla aflojando un umbral: hay que no tomar ese camino.
            //
            // Si hay pose, se corta por franjas —que es lo que sabe distinguir
            // una camiseta de un pantalón— y si no la hay, entonces sí: la
            // foto es de una prenda suelta y el sujeto es la prenda.
            if (try? await VisionStages.bodyLandmarks(in: image)) == nil {
                let single = await extractSingleSubject(from: image)
                if !single.isEmpty {
                    DiagnosticsLog.record("PIPELINE", "recortada por máscara de sujeto")
                    return single
                }
            } else {
                DiagnosticsLog.record(
                    "PIPELINE",
                    "hay persona: no se levanta el sujeto — sería recortar a la persona"
                )
            }

            let salient = await extractSalientRegion(from: image)
            guard salient.isEmpty else { return salient }

            DiagnosticsLog.record("PIPELINE", "nada que recortar", isProblem: true)
            throw PipelineError.noSubjectFound
        }

        // ## Sin modelo: la ruta degradada
        //
        // Aquí sí se pregunta por la pose, porque es lo único que distingue una
        // camiseta de un pantalón cuando nadie ha etiquetado los píxeles.
        DiagnosticsLog.record("PIPELINE", "sin segmentador: ruta degradada")

        // Igual aquí: **primero se mira si hay alguien**, y solo sin nadie se
        // levanta el sujeto. Antes esto iba al revés y una foto de cuerpo
        // entero devolvía a la persona entera como "una prenda".
        let landmarks = try? await VisionStages.bodyLandmarks(in: image)
        DiagnosticsLog.record(
            "PIPELINE",
            landmarks == nil ? "no hay pose" : "hay pose: se corta por franjas"
        )

        if landmarks == nil {
            let single = await extractSingleSubject(from: image)
            if !single.isEmpty {
                DiagnosticsLog.record("PIPELINE", "recortada por máscara de sujeto")
                return single
            }
        }

        guard landmarks != nil else {
            let salient = await extractSalientRegion(from: image)
            guard salient.isEmpty else { return salient }

            // **Por qué no se encontró nada importa.** Decir "no se pudo
            // separar el sujeto" manda al usuario a cambiar de foto cuando el
            // problema es que el modelo todavía no está.
            DiagnosticsLog.record(
                "PIPELINE", "nada que recortar y sin segmentador cargado", isProblem: true
            )
            throw PipelineError.modelNotReady
        }

        let observation: InstanceMaskObservation
        do {
            guard let instances = try await VisionStages.foregroundInstances(in: image) else {
                throw PipelineError.noSubjectFound
            }
            observation = instances
        } catch {
            throw PipelineErrorMapper.map(error)
        }

        // La silueta completa, con el fondo ya fuera. Es **una** persona, no
        // una prenda: el corte por prendas lo hacemos nosotros a partir de aquí.
        let handler = ImageRequestHandler(image)
        let maskedBuffer = try observation.generateMaskedImage(
            for: observation.allInstances,
            imageFrom: handler,
            croppedToInstancesExtent: false
        )
        guard
            let person = Self.cgImage(from: maskedBuffer),
            let personBounds = CropNormalizer.opaqueBounds(of: person)
        else { throw PipelineError.maskGenerationFailed }

        guard let landmarks else { throw PipelineError.noPersonFound }
        let regions = GarmentRegion.regions(
            for: landmarks,
            imageSize: CGSize(width: person.width, height: person.height),
            personBounds: personBounds
        )

        var results: [DetectedGarment] = []
        for region in regions {
            if let garment = await garment(in: person, region: region) {
                results.append(garment)
            }
        }
        return results
    }

    // MARK: - Con modelo

    private func extractWithSegmenter(
        _ segmenter: ClothesSegmenter,
        from image: CGImage
    ) async throws -> [DetectedGarment] {
        let clock = ContinuousClock.now
        let map = try await segmenter.classMap(for: image)
        DiagnosticsLog.record("SEGMENTA", "mapa \(map.width)×\(map.height) en \(clock.duration(to: .now))")

        // **Qué vio el modelo, clase por clase.** Es el dato que falta cuando
        // una foto "no detecta nada": sin esto no se sabe si el modelo no vio
        // ropa o si la vio y se cayó después, al recortar o al normalizar.
        let histogram = map.histogram()
        let total = Double(map.width * map.height)
        let seen = histogram
            .compactMap { raw, count -> String? in
                guard
                    let label = ClothesSegmenter.Label(rawValue: raw),
                    label != .background,
                    Double(count) / total >= 0.002
                else { return nil }
                return String(format: "%@ %.1f%%", "\(label)", Double(count) / total * 100)
            }
            .sorted()
        DiagnosticsLog.record(
            "SEGMENTA",
            seen.isEmpty ? "no reconoce ninguna clase de ropa" : "ve: " + seen.joined(separator: ", "),
            isProblem: seen.isEmpty
        )

        let regions = SegmentedGarmentExtractor.regions(in: map, splitting: splitsInstances)
        DiagnosticsLog.record(
            "SEGMENTA",
            regions.isEmpty
                ? "ninguna región supera el mínimo de área"
                : "\(regions.count) prenda(s): " + regions
                    .map { "\($0.label)#\($0.instanceIndex)" }
                    .joined(separator: ", "),
            isProblem: regions.isEmpty
        )

        // **Se trabaja sobre una copia acotada, no sobre la foto original.**
        //
        // El recorte final mide 768 píxeles, así que todo lo que venga por
        // encima de ~1280 se tira igualmente — pero antes se pagaba entero:
        // aplicar la máscara a una foto de 12 MP es recorrer doce millones de
        // píxeles por prenda, y con tres prendas por foto eso es el coste
        // dominante de todo el escaneo. La máscara viene de un mapa de 512, de
        // modo que reducir aquí no pierde un solo detalle real.
        let working = Self.limited(image, longestSide: Self.workingSide) ?? image

        var results: [DetectedGarment] = []
        for region in regions {
            guard
                let rawCrop = SegmentedGarmentExtractor.crop(region: region, from: working),
                // Sin esto, una prenda que se cae aquí desaparece en silencio y
                // el recuento final no cuadra con lo que el modelo dijo ver.
                logCrop(region, rawCrop),
                // Con la categoría delante: un pantalón no se encaja como una
                // camiseta. Se usa la del segmentador y no la que acabe
                // diciendo el embedder porque la diferencia entre las dos es
                // camiseta contra chaqueta, y las dos comparten perfil.
                let normalized = CropNormalizer.normalize(rawCrop, for: region.kind)
            else { continue }

            var colors = ColorExtractor.dominantColors(in: normalized)
            // El modelo ya excluye piel y pelo por clase, pero un borde mal
            // clasificado puede arrastrar brazo dentro de una manga. Barato de
            // comprobar y evita que se cuele.
            guard !Self.looksLikeSkin(colors) else {
                DiagnosticsLog.record(
                    "RECORTE", "\(region.label) descartada: casi toda piel", isProblem: true
                )
                continue
            }

            let described = await describe(normalized, region: region)
            DiagnosticsLog.record(
                "RECORTE",
                "\(region.label)#\(region.instanceIndex) → \(described.kind.rawValue)"
                    + " \(described.subcategory ?? "—") · \(colors.first?.nameKey ?? "sin color")"
            )
            let evidence = await readBrandEvidence(in: rawCrop)

            // Y, solo si hace falta, la segunda opinión.
            let refined = await refineIfNeeded(
                normalized: normalized,
                kind: described.kind,
                subcategory: described.subcategory,
                material: described.material,
                confidence: 0.85,
                colorName: colors.first?.nameKey,
                evidence: evidence
            )

            // El mapa de clases cubre la foto entera estirado, así que sus
            // coordenadas normalizadas son ya las de la foto.
            let mapWidth = Double(map.width)
            let mapHeight = Double(map.height)
            let sourceRect = CGRect(
                x: region.bounds.minX / mapWidth,
                y: region.bounds.minY / mapHeight,
                width: region.bounds.width / mapWidth,
                height: region.bounds.height / mapHeight
            )

            colors = Self.renamed(colors, to: refined.colorName)

            results.append(
                DetectedGarment(
                    kind: refined.kind,
                    confidence: refined.confidence,
                    normalized: ImmutableImage(normalized),
                    rawCrop: ImmutableImage(rawCrop),
                    colors: colors,
                    featurePrint: described.embedding,
                    subcategory: refined.subcategory,
                    material: refined.material,
                    tags: described.tags,
                    seasons: described.seasons,
                    brand: refined.brand,
                    brandEvidence: refined.evidence,
                    instanceIndex: region.instanceIndex,
                    sourceRect: sourceRect
                )
            )
        }
        return results
    }

    /// Anota un recorte hecho. Devuelve siempre `true` para poder encadenarlo
    /// en el `guard` sin romper la secuencia de `let`.
    private func logCrop(_ region: SegmentedGarmentExtractor.Region, _ crop: CGImage) -> Bool {
        DiagnosticsLog.record(
            "RECORTE", "\(region.label)#\(region.instanceIndex) recortada \(crop.width)×\(crop.height)"
        )
        return true
    }

    /// Lo que el embedder y el prompt bank añaden sobre lo que dijo SegFormer.
    ///
    /// Sin ellos se devuelve lo que ya había: SegFormer clasifica bien el tipo,
    /// solo que no distingue una chaqueta de una camiseta ni sabe de qué
    /// material es.
    /// - Parameter region: de qué clase venía el recorte. `nil` cuando no lo
    ///   sabemos porque el recorte no salió del segmentador sino de la máscara
    ///   de sujeto — ahí el tipo de prenda lo decide el embedder sin pistas.
    private func describe(
        _ image: CGImage,
        region: SegmentedGarmentExtractor.Region?
    ) async -> (
        kind: GarmentKind, embedding: Data?, subcategory: String?,
        material: String?, tags: [String], seasons: SeasonSet
    ) {
        guard
            let embedder,
            let promptBank,
            let vector = try? await embedder.embedding(for: image)
        else {
            return (
                region?.kind ?? .other,
                try? await VisionStages.featurePrint(of: image),
                nil, nil, [], .all
            )
        }

        // Las clases candidatas. Para el torso son **dos**: SegFormer marca
        // igual una camiseta y una chaqueta —ambas son `upper-clothes`— y esta
        // es la única señal que las separa.
        // Sin región, **cualquiera**: la foto de una prenda suelta no trae
        // ninguna pista de qué es, y restringir a una clase que no conocemos
        // sería inventarla.
        let candidates: Set<GarmentKindName>
        if let region {
            candidates = region.label == .upperClothes
                ? [.upperBody, .outerLayer]
                : [GarmentKindName(rawValue: region.kind.rawValue)]
                    .compactMap { $0 }
                    .reduce(into: []) { $0.insert($1) }
        } else {
            candidates = Set(GarmentKindName.allCases)
        }

        let match = promptBank.bestSubcategory(for: vector, constrainedTo: candidates)
        let resolvedKind = match.flatMap { GarmentKind(rawValue: $0.kind.rawValue) }
            ?? region?.kind
            ?? .other

        let material = promptBank.best(group: "material", for: vector).first
        let pattern = promptBank.best(group: "pattern", for: vector).first
        let style = promptBank.best(group: "style", for: vector).first
        let season = promptBank.best(group: "season", for: vector).first

        var tags: [String] = []
        if let pattern, pattern.similarity > 0.18 { tags.append(pattern.entry.key) }
        if let style, style.similarity > 0.18 { tags.append(style.entry.key) }

        let seasons: SeasonSet
        switch season?.entry.key {
        case "verano": seasons = [.spring, .summer]
        case "invierno": seasons = [.autumn, .winter]
        default: seasons = .all
        }

        return (
            kind: resolvedKind,
            embedding: EmbeddingMath.encode(vector),
            subcategory: match?.key,
            material: (material?.similarity ?? 0) > 0.18 ? material?.entry.key : nil,
            tags: tags,
            seasons: seasons
        )
    }

    // MARK: - Una prenda sola

    /// Una foto con **un objeto y nada más**: la prenda es el sujeto.
    ///
    /// No hace falta fondo blanco ni nada parecido —`GenerateForegroundInstance
    /// MaskRequest` separa el sujeto del fondo sea cual sea—, y esto cubre el
    /// caso más común de "añadir una prenda": fotografiarla suelta.
    ///
    /// Solo se llama cuando **no hay persona** en la foto. Con persona, el
    /// sujeto es la persona entera, y devolverla como "una prenda" es
    /// exactamente el error que tenía el pipeline al principio. Quien decide
    /// eso es `extractGarments`, que ya ha mirado la pose.
    /// Sobre fondo liso, el recorte lo pone Vision y la clase el segmentador.
    ///
    /// ## Qué arregla
    ///
    /// La foto de una prenda sola sobre una mesa o una cama. El segmentador
    /// —entrenado con gente vestida— acierta **qué** prenda es y falla en el
    /// contorno: deja picos, se come un puño, incluye un trozo de mesa. Y
    /// levantar el sujeto, que ahí es casi perfecto, no sabe qué ha levantado.
    ///
    /// Así que se usan las dos: la clase, las etiquetas y el color siguen
    /// viniendo del segmentador y del embedder; los píxeles, de la máscara de
    /// sujeto.
    ///
    /// ## Cuándo no
    ///
    /// - Con **más de una prenda** en la foto: el sujeto sería las dos juntas.
    /// - Con **persona**: el sujeto es la persona entera, y eso ya nos costó
    ///   dar de alta al usuario como una prenda.
    /// - Con fondo **no liso**: ahí el segmentador es mejor que Vision, que se
    ///   llevaría la silla de detrás.
    private func refinedOnSolidBackground(
        _ garments: [DetectedGarment],
        from image: CGImage
    ) async -> [DetectedGarment] {
        guard
            garments.count == 1,
            let garment = garments.first,
            SolidBackground.isLikely(in: image),
            (try? await VisionStages.bodyLandmarks(in: image)) == nil
        else { return garments }

        // **Tres técnicas y se mide.**
        //
        // Ninguna gana siempre: el segmentador sabe de ropa pero no de esta
        // foto, la máscara de sujeto sabe de objetos pero no de ropa, y el
        // corte por color no sabe de nada pero sobre fondo liso acierta el
        // borde al píxel. Así que se hacen las tres y se puntúan igual —
        // ver `CutoutQuality`—, que es más barato que decidir a priori cuál
        // debería ganar.
        var candidates: [(name: String, garment: DetectedGarment)] = [
            ("segmentador", garment),
        ]

        if let lifted = await subjectCutout(from: image) {
            candidates.append(("sujeto", garment.replacingImages(
                normalized: lifted.normalized,
                rawCrop: lifted.rawCrop
            )))
        }

        if let split = ColorSplitter.split(image),
           let cut = ColorSplitter.cutout(image, using: split),
           let tight = CropNormalizer.opaqueBounds(of: cut),
           let rawCrop = cut.cropping(to: tight),
           let normalized = CropNormalizer.normalize(rawCrop, for: garment.kind) {
            candidates.append(("color", garment.replacingImages(
                normalized: ImmutableImage(normalized),
                rawCrop: ImmutableImage(rawCrop)
            )))
        }

        // **Dos notas, no una.** La forma dice si el recorte está entero; la
        // contaminación dice si se ha traído medio mueble dentro. Un recorte
        // que se lleva la mesa tiene silueta impecable —una mancha, buen
        // tamaño, sin tocar el canto— y es el peor de los tres. Sin la segunda
        // nota, gana.
        let scored = candidates.map { candidate -> (String, DetectedGarment, Double) in
            let cutout = candidate.garment.normalized.cgImage
            let shape = CutoutQuality.assess(cutout).score
            let dirt = CutoutQuality.contamination(of: cutout, backgroundOf: image)
            return (candidate.name, candidate.garment, shape - dirt)
        }
        DiagnosticsLog.record(
            "RECORTE",
            "fondo liso · " + scored
                .map { String(format: "%@ %.2f", $0.0, $0.2) }
                .joined(separator: " · ")
        )
        guard
            let best = scored.max(by: { $0.2 < $1.2 }),
            best.0 != "segmentador"
        else { return garments }

        DiagnosticsLog.record("RECORTE", "gana el recorte por \(best.0)")
        let winner = best.1
        return [
            DetectedGarment(
                kind: winner.kind,
                confidence: winner.confidence,
                normalized: winner.normalized,
                rawCrop: winner.rawCrop,
                // El color se remide sobre el recorte bueno: medido sobre el
                // malo llevaba dentro píxeles de mesa.
                colors: ColorExtractor.dominantColors(in: winner.normalized.cgImage),
                featurePrint: winner.featurePrint,
                subcategory: winner.subcategory,
                material: winner.material,
                tags: winner.tags,
                seasons: winner.seasons,
                brand: winner.brand,
                brandEvidence: winner.brandEvidence,
                instanceIndex: winner.instanceIndex,
                sourceRect: winner.sourceRect
            ),
        ]
    }

    /// La prenda levantada del fondo, sin describirla.
    ///
    /// Comparte trabajo con `extractSingleSubject`, que hace lo mismo y además
    /// la clasifica: aquí la clase ya la sabemos.
    private func subjectCutout(
        from image: CGImage
    ) async -> (normalized: ImmutableImage, rawCrop: ImmutableImage)? {
        guard
            let observation = try? await VisionStages.foregroundInstances(in: image),
            let buffer = try? observation.generateMaskedImage(
                for: observation.allInstances,
                imageFrom: ImageRequestHandler(image),
                croppedToInstancesExtent: true
            ),
            let subject = Self.cgImage(from: buffer),
            let tight = CropNormalizer.opaqueBounds(of: subject),
            let rawCrop = subject.cropping(to: tight),
            let normalized = CropNormalizer.normalize(rawCrop)
        else { return nil }
        return (ImmutableImage(normalized), ImmutableImage(rawCrop))
    }

    private func extractSingleSubject(from image: CGImage) async -> [DetectedGarment] {
        guard
            let observation = try? await VisionStages.foregroundInstances(in: image),
            let buffer = try? observation.generateMaskedImage(
                for: observation.allInstances,
                imageFrom: ImageRequestHandler(image),
                croppedToInstancesExtent: true
            ),
            let subject = Self.cgImage(from: buffer),
            let tight = CropNormalizer.opaqueBounds(of: subject),
            let rawCrop = subject.cropping(to: tight),
            // Cuadrado: aquí todavía no se sabe qué prenda es —eso lo dice
            // `describe` **después**— y elegir el perfil de pantalón para algo
            // que resulte ser una gorra encaja peor que no elegir ninguno.
            let normalized = CropNormalizer.normalize(rawCrop)
        else { return [] }

        let area = Double(tight.width * tight.height) / Double(subject.width * subject.height)
        guard area >= Self.minimumAreaFraction else { return [] }

        let colors = ColorExtractor.dominantColors(in: normalized)
        // Una mano sujetando la prenda, o la prenda puesta y mal recortada.
        guard !Self.looksLikeSkin(colors) else { return [] }

        let described = await describe(normalized, region: nil)

        return [
            DetectedGarment(
                kind: described.kind,
                // El recorte es bueno; de qué prenda se trata lo decide el
                // embedder, y sin él es una conjetura por la forma.
                confidence: embedder == nil ? Self.degradedConfidenceCeiling : 0.7,
                normalized: ImmutableImage(normalized),
                rawCrop: ImmutableImage(rawCrop),
                colors: colors,
                featurePrint: described.embedding,
                subcategory: described.subcategory,
                material: described.material,
                tags: described.tags,
                seasons: described.seasons,
                brand: await readBrand(in: rawCrop),
                sourceRect: CGRect(
                    x: tight.minX / Double(subject.width),
                    y: tight.minY / Double(subject.height),
                    width: tight.width / Double(subject.width),
                    height: tight.height / Double(subject.height)
                )
            )
        ]
    }

    // MARK: - Último recurso

    /// Recorta por donde mira el ojo.
    ///
    /// Cuando ni la máscara de sujeto ni el segmentador encuentran nada, la
    /// alternativa no es un error: es **recortar la zona importante de la
    /// foto** y dejar que el usuario decida. Lleva algo de fondo y sale con
    /// poca confianza —entra marcada para revisar—, pero convierte "no se pudo
    /// separar el sujeto" en una prenda que se puede guardar.
    private func extractSalientRegion(from image: CGImage) async -> [DetectedGarment] {
        guard
            let region = try? await VisionStages.salientRegion(in: image),
            let rawCrop = image.cropping(to: region.integral),
            let normalized = CropNormalizer.normalize(rawCrop)
        else { return [] }

        #if DEBUG
        NSLog("PIPELINE: recorte por saliencia")
        #endif

        let colors = ColorExtractor.dominantColors(in: normalized)
        let described = await describe(normalized, region: nil)

        return [
            DetectedGarment(
                kind: described.kind,
                // Baja: el recorte lleva fondo y el tipo es una conjetura.
                confidence: 0.3,
                normalized: ImmutableImage(normalized),
                rawCrop: ImmutableImage(rawCrop),
                colors: colors,
                featurePrint: described.embedding,
                subcategory: described.subcategory,
                material: described.material,
                tags: described.tags,
                seasons: described.seasons,
                brand: await readBrand(in: rawCrop),
                sourceRect: CGRect(
                    x: region.minX / Double(image.width),
                    y: region.minY / Double(image.height),
                    width: region.width / Double(image.width),
                    height: region.height / Double(image.height)
                )
            )
        ]
    }

    // MARK: - Una franja

    private func garment(in person: CGImage, region: GarmentRegion) async -> DetectedGarment? {
        let clamped = region.rect.intersection(
            CGRect(x: 0, y: 0, width: person.width, height: person.height)
        )
        guard !clamped.isNull, clamped.width > 8, clamped.height > 8 else { return nil }

        guard
            let slice = person.cropping(to: clamped),
            // La franja es un rectángulo, pero la prenda dentro no llena las
            // esquinas: se vuelve a ajustar a los píxeles opacos reales.
            let tight = CropNormalizer.opaqueBounds(of: slice),
            let rawCrop = slice.cropping(to: tight),
            let normalized = CropNormalizer.normalize(rawCrop, for: region.kind.kind)
        else { return nil }

        let area = Double(tight.width * tight.height)
            / Double(person.width * person.height)
        guard area >= Self.minimumAreaFraction else { return nil }

        let colors = ColorExtractor.dominantColors(in: normalized)
        // Sin esto, la franja de la cabeza entra como "accesorio" siendo una
        // cara, y la de las piernas entra como "pantalón" siendo unas piernas.
        guard !Self.looksLikeSkin(colors) else { return nil }

        // `person` se generó sin recortar a la extensión de las instancias, así
        // que comparte sistema de coordenadas con la foto original: la franja
        // más el ajuste fino a píxeles opacos ya está en el espacio correcto.
        let sourceRect = CGRect(
            x: (clamped.minX + tight.minX) / Double(person.width),
            y: (clamped.minY + tight.minY) / Double(person.height),
            width: tight.width / Double(person.width),
            height: tight.height / Double(person.height)
        )

        return DetectedGarment(
            kind: region.kind.kind,
            confidence: min(region.confidence, Self.degradedConfidenceCeiling),
            normalized: ImmutableImage(normalized),
            rawCrop: ImmutableImage(rawCrop),
            colors: colors,
            featurePrint: try? await VisionStages.featurePrint(of: normalized),
            sourceRect: sourceRect
        )
    }

    /// Lado máximo con el que se trabaja tras la segmentación.
    ///
    /// 1280 y no más: el recorte normalizado mide 768, así que por encima de
    /// esto se está recorriendo píxeles que acabarán descartados.
    static let workingSide = 1280

    /// Reduce la foto si pasa del lado dado. `nil` si no hacía falta.
    static func limited(_ image: CGImage, longestSide: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > longestSide else { return nil }

        let scale = Double(longestSide) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))

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

    /// Lee la marca, si toca.
    ///
    /// **Solo cuando se importa una foto a mano**, no al escanear la galería.
    /// El OCR en modo `.accurate` cuesta entre 50 y 200 ms por prenda: en una
    /// importación suelta no se nota, y en un escaneo de dos mil fotos son
    /// minutos enteros por un dato que no hace falta para enseñar la prenda en
    /// la balda. En el escaneo se deja vacío y se rellena al abrirla.
    ///
    /// Por debajo de 160 píxeles no hay letra legible y el OCR es coste puro.
    private func readBrand(in rawCrop: CGImage) async -> String? {
        BrandVerdict.resolve(await readBrandEvidence(in: rawCrop))
    }

    /// Lo que se lee en la prenda, **con lo seguro que se está de cada
    /// lectura**.
    ///
    /// - Parameter rawCrop: sin normalizar. Normalizado, el texto de una
    ///   etiqueta se ha reescalado y ya no se lee.
    private func readBrandEvidence(in rawCrop: CGImage) async -> [BrandEvidence] {
        guard readsBrands, min(rawCrop.width, rawCrop.height) >= 160 else { return [] }
        let evidence = await BrandRecognizer.evidence(in: rawCrop)
        if !evidence.isEmpty {
            DiagnosticsLog.record(
                "MARCA",
                "OCR: " + evidence
                    .map { "\($0.brand) \(String(format: "%.2f", $0.confidence))" }
                    .joined(separator: ", ")
            )
        }
        return evidence
    }

    // MARK: - La segunda opinión

    /// Lo que queda de una prenda después de preguntar fuera —o de no hacerlo.
    struct Refined {
        let kind: GarmentKind
        let subcategory: String?
        let material: String?
        let confidence: Double
        let brand: String?
        let evidence: [BrandEvidence]
        /// El nombre del color según el resolutor. `nil` = se queda el medido.
        let colorName: String?
    }

    /// Pregunta al resolutor remoto **solo si merece la pena**, y mezcla.
    ///
    /// ## Qué se acepta de la respuesta y qué no
    ///
    /// - La **subcategoría** se acepta cuando aquí no había ninguna. Es lo que
    ///   peor se resuelve en el dispositivo y lo que más cambia el nombre de la
    ///   prenda.
    /// - La **categoría** solo se acepta si la local venía floja. El
    ///   segmentador etiqueta píxel a píxel y acierta más que una mirada
    ///   general a un recorte de 512.
    /// - La **marca** no se acepta: se **añade como una evidencia más** y se
    ///   vuelve a votar. Es lo que impide que una respuesta segura de sí misma
    ///   escriba "Nike" en una camiseta lisa.
    private func refineIfNeeded(
        normalized: CGImage,
        kind: GarmentKind,
        subcategory: String?,
        material: String?,
        confidence: Double,
        colorName: String?,
        evidence: [BrandEvidence]
    ) async -> Refined {
        let local = Refined(
            kind: kind,
            subcategory: subcategory,
            material: material,
            confidence: confidence,
            brand: BrandVerdict.resolve(evidence),
            evidence: evidence,
            colorName: nil
        )

        guard
            let resolver,
            alwaysAsksRemote || Self.needsRemoteHelp(
                confidence: confidence, subcategory: subcategory, brandEvidence: evidence
            )
        else { return local }

        guard let jpeg = NormalizedJPEG.encode(normalized) else { return local }
        DiagnosticsLog.record(
            "REMOTO",
            "se consulta: \(kind.rawValue) · sub \(subcategory ?? "—")"
                + " · \(jpeg.count / 1024) KB"
        )

        let query = RemoteGarmentQuery(
            imageJPEG: jpeg,
            kind: kind.rawValue,
            subcategory: subcategory,
            dominantColor: colorName,
            brandCandidates: evidence.map(\.brand)
        )

        guard let answer = try? await resolver.resolve(query) else {
            DiagnosticsLog.record("REMOTO", "sin respuesta; se queda lo local", isProblem: true)
            return local
        }

        var merged = evidence
        if let brand = answer.brand {
            merged.append(
                BrandEvidence(
                    brand: brand,
                    source: .remote,
                    // Sin confianza declarada, la mitad del techo: una
                    // afirmación sin medida no puede valer lo mismo que una
                    // medida.
                    confidence: answer.brandConfidence ?? (BrandEvidence.Source.remote.ceiling / 2)
                )
            )
        }

        let remoteKind = answer.kind.flatMap(GarmentKind.init(rawValue:))
        return Refined(
            // La categoría del segmentador manda salvo que viniera floja.
            kind: confidence < Self.remoteConfidenceFloor ? (remoteKind ?? kind) : kind,
            subcategory: subcategory ?? answer.subcategory,
            material: material ?? answer.material,
            confidence: max(confidence, answer.confidence ?? confidence),
            brand: BrandVerdict.resolve(merged),
            evidence: merged,
            colorName: answer.colorName
        )
    }

    /// Los colores medidos, con el nombre que puso el resolutor.
    ///
    /// **Se cambia el nombre, no el color.** El RGB sale de los píxeles de la
    /// prenda y es exacto; lo que falla es cómo se llama ese RGB, porque la
    /// tabla lo redondea al color con nombre más cercano y un azul marino cae
    /// del lado del negro. Así la muestra de color sigue siendo la de la
    /// prenda y la etiqueta deja de mentir.
    static func renamed(_ colors: [NamedColor], to name: String?) -> [NamedColor] {
        guard let name, let dominant = colors.first else { return colors }
        let renamed = NamedColor(
            nameKey: name,
            red: dominant.red, green: dominant.green, blue: dominant.blue,
            weight: dominant.weight
        )
        return [renamed] + colors.dropFirst()
    }

    // MARK: - Utilidades

    /// Una región cuyos colores dominantes son todos tonos de piel es un brazo
    /// o una pierna, no una prenda.
    ///
    /// Es la diferencia entre el armario de la captura de referencia —donde se
    /// cuelan caras y trozos de piel— y uno que solo tiene ropa.
    static func looksLikeSkin(_ colors: [NamedColor]) -> Bool {
        let skinWeight = colors
            .filter { isSkinTone($0) }
            .reduce(0) { $0 + $1.weight }
        return skinWeight > maximumSkinFraction
    }

    static func isSkinTone(_ color: NamedColor) -> Bool {
        let lab = ColorExtractor.rgbToLab(color.red, color.green, color.blue)
        // Franja de tonos piel en Lab: luminosidad media-alta, a* y b* positivos
        // y moderados. Cubre desde piel muy clara hasta muy oscura porque lo que
        // caracteriza a la piel es el tono cálido, no la claridad.
        return lab.x > 20 && lab.x < 92
            && lab.y > 5 && lab.y < 27
            && lab.z > 8 && lab.z < 35
    }

    static func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
        return image
    }
}
