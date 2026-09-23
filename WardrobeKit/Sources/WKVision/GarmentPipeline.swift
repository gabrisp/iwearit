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
    public static let defaultMinimumAreaFraction = 0.03

    /// Si hay alguien **de verdad** en la foto.
    ///
    /// Una prenda con forma de torso —una camiseta sobre la cama— le saca a
    /// Vision "hombros" con media confianza; una persona tiene rodillas o
    /// tobillos, o una pose clara. Ver `convincingPoseConfidence`.
    static func hasConvincingPerson(in image: CGImage) async -> Bool {
        guard let pose = (try? await VisionStages.bodyLandmarks(in: image)) ?? nil else {
            return false
        }
        let hasLegs = pose.kneeY != nil || pose.ankleY != nil
        let convincing = hasLegs || pose.confidence >= convincingPoseConfidence
        DiagnosticsLog.record(
            "RECORTE",
            String(
                format: convincing
                    ? "hay alguien en la foto (conf %.2f%@): se deja al segmentador"
                    : "pose floja (conf %.2f%@): se trata como prenda suelta",
                pose.confidence, hasLegs ? ", con piernas" : ""
            )
        )
        return convincing
    }

    /// Cuánta mesa se le tolera al sujeto antes de preferir otro recorte.
    static let acceptableContamination = 0.12

    /// A partir de cuánta confianza una pose cuenta como persona.
    ///
    /// Por debajo, y sin rodillas ni tobillos, lo más probable es que sea una
    /// prenda con forma de torso: una camiseta doblada, una camisa estirada
    /// sobre la cama. Ver `refinedOnSolidBackground`.
    static let convincingPoseConfidence = 0.6

    /// Lado máximo con el que se analiza. Ver `extractGarments`.
    static let workingMaxSide = 1100

    /// Lado máximo de la foto **sobre la que se aplica** la máscara de sujeto.
    ///
    /// La máscara se calcula en pequeño (`workingMaxSide`), que es lo caro,
    /// pero Vision la escala a la foto que se le dé al generar el recorte. Si
    /// esa foto era también la de 1100, una prenda que ocupa media foto se
    /// quedaba en 500 px y se **ampliaba** a 1024 al normalizar: bordes
    /// pixelados. Con esta, sobra resolución y el recorte se reduce.
    static let detailMaxSide = 2400

    /// Lado máximo del recorte que se **conserva**.
    ///
    /// La máscara se calcula y se aplica sobre la foto original —es lo que da
    /// el canto limpio—, pero guardar ese recorte a doce megapíxeles por prenda
    /// es lo que hace que importar diez fotos se quede sin memoria. Reducido
    /// aquí, con interpolación buena, el borde sigue siendo el de iOS.
    static let keptCropMaxSide = 2048

    /// La misma foto, más pequeña, si hacía falta.
    static func scaledDown(_ image: CGImage, maxSide: Int) -> CGImage? {
        let side = max(image.width, image.height)
        guard side > maxSide else { return nil }

        let factor = Double(maxSide) / Double(side)
        let width = Int(Double(image.width) * factor)
        let height = Int(Double(image.height) * factor)
        guard
            width > 0, height > 0,
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

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

    /// Cuánto tiene que ocupar algo para contar como prenda.
    ///
    /// Ajustable **solo para el reintento**, y con el valor de siempre por
    /// defecto: el camino normal detecta bien y no se toca. Subirlo es la
    /// versión estricta —se queda lo que ocupa de verdad y se van las piezas
    /// pequeñas que a veces se cuelan— y es una de las dos cosas que se
    /// prueban cuando el usuario dice "vuelve a mirar".
    private let minimumAreaFraction: Double

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
        alwaysAsksRemote: Bool = false,
        minimumAreaFraction: Double = GarmentPipeline.defaultMinimumAreaFraction
    ) {
        self.splitsInstances = splitsInstances
        self.alwaysAsksRemote = alwaysAsksRemote
        self.minimumAreaFraction = minimumAreaFraction
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
    public func extractGarments(from original: CGImage) async throws -> [DetectedGarment] {
        let garments = try await extractGarmentsFromPixels(original)
        return await annotatedFromProductPage(garments, in: original)
    }

    /// Lo que dice la **ficha del producto**, si la foto es de una tienda.
    ///
    /// Una captura de la web o una foto de catálogo lleva escrito al lado el
    /// nombre del producto, y eso dice qué es la prenda mejor que los píxeles.
    /// Ver `ProductPageReader`. Con una sola prenda se le aplica todo; con
    /// varias, solo a la que casa con el tipo del título.
    private func annotatedFromProductPage(
        _ garments: [DetectedGarment],
        in original: CGImage
    ) async -> [DetectedGarment] {
        guard readsBrands, !garments.isEmpty else { return garments }
        // A tamaño de pantalla: la letra de una ficha se lee de sobra, y la
        // foto entera a doce megapíxeles es tiempo de espera.
        let page = Self.scaledDown(original, maxSide: 2000) ?? original
        guard let read = await ProductPageReader.read(page) else {
            DiagnosticsLog.record("FICHA", "sin texto de producto en la foto")
            return garments
        }

        if garments.count == 1 {
            return [garments[0].annotated(with: read, allowsKindChange: true)]
        }
        let matching = garments.indices.filter { garments[$0].kind == read.kind }
        guard matching.count == 1, let index = matching.first else { return garments }
        var result = garments
        result[index] = garments[index].annotated(with: read, allowsKindChange: false)
        return result
    }

    private func extractGarmentsFromPixels(_ original: CGImage) async throws -> [DetectedGarment] {
        if skipsUtilityImages, (try? await VisionStages.isUtilityImage(original)) == true {
            return []
        }

        // **Se trabaja en pequeño.**
        //
        // Una foto de tienda o de cámara llega con doce millones de píxeles, y
        // todo lo que viene después los recorre enteros: el corte por color,
        // el cierre morfológico, el relleno de agujeros, el alisado y las dos
        // notas de calidad. Son media docena de pasadas sobre doce millones,
        // en Swift, y eso son segundos — los segundos que se notan esperando.
        //
        // Y no se pierde nada, porque **el recorte acaba en 768 píxeles de
        // todos modos**: `CropNormalizer` lo escala ahí antes de guardarlo.
        // Analizar a 1100 de lado es analizar con más detalle del que va a
        // sobrevivir —y a 1400 eran un 60% más de píxeles en cada una de esas
        // media docena de pasadas, que es tiempo de espera puro.
        let image = Self.scaledDown(original, maxSide: Self.workingMaxSide) ?? original
        // **La máscara se pide sobre la original y se aplica sobre esta.**
        //
        // Lo primero es lo que da el canto limpio: Vision calcula la máscara a
        // la resolución de la foto que se le da. Lo segundo es lo que evita
        // quedarse sin memoria: aplicarla sobre doce megapíxeles son ~48 MB por
        // sujeto, y con varias fotos a la vez eso es la app cerrándose. La
        // máscara es normalizada, así que al aplicarla aquí se escala sola y el
        // borde sigue siendo el de la original.
        let detail = Self.scaledDown(original, maxSide: Self.detailMaxSide) ?? original
        if image !== original {
            DiagnosticsLog.record(
                "PIPELINE",
                "se trabaja a \(image.width)×\(image.height)"
                    + " en vez de \(original.width)×\(original.height)"
            )
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
            // ## Sujeto primero
            //
            // Lo lógico, y lo que hace el propio iPhone: mirar **qué objetos
            // hay** antes de preguntar de qué clase es cada píxel. Si nadie
            // lleva la ropa puesta, cada sujeto que separa iOS es una cosa —un
            // zapato, una camiseta doblada— y su máscara es el mejor recorte
            // que existe. El segmentador solo dice **qué** es, mirando dentro
            // de esa máscara. Antes era al revés: el segmentador recortaba y
            // el sujeto solo se probaba en casos contados, y una cosa tan
            // básica como un zapato salía mordida.
            //
            // Con alguien puesto, el sujeto es la persona entera: ahí manda el
            // segmentador, que separa camiseta de pantalón. Y si el sujeto no
            // resuelve la foto —varias prendas pegadas en uno solo, nada que
            // parezca ropa— se sigue por el camino de siempre.
            if !(await Self.hasConvincingPerson(in: image)) {
                if let fromSubjects = await extractFromSubjects(segmenter, image: image, detail: detail, original: original),
                   !fromSubjects.isEmpty {
                    return fromSubjects
                }
                DiagnosticsLog.record("SUJETO", "el sujeto no resuelve la foto: se sigue por el segmentador")
            }

            if let garments = try? await extractWithSegmenter(segmenter, from: image, detail: detail, original: original),
               !garments.isEmpty {
                return await refinedOnSolidBackground(Self.merged(garments), from: image, detail: detail, original: original)
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
                let single = await extractSingleSubject(from: original, detail: detail)
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
            let single = await extractSingleSubject(from: original, detail: detail)
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
        from image: CGImage,
        detail: CGImage,
        original: CGImage
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

        let regions = SegmentedGarmentExtractor.regions(
            in: map,
            splitting: splitsInstances,
            // El listón del pipeline manda sobre el del extractor cuando es
            // más alto: es lo que hace que el reintento estricto lo sea de
            // verdad y no solo en el último filtro.
            minimumArea: max(SegmentedGarmentExtractor.minimumAreaFraction, minimumAreaFraction)
        )
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
        // let working = Self.limited(image, longestSide: Self.workingSide) ?? image
        //
        // **Sobre la foto con resolución, y con el canto del sujeto.** Recortar
        // sobre 1280 px con una máscara de 512 estirada daba bordes en
        // escalera. Ahora el recorte sale de `detail` y su canto exterior lo
        // marca la máscara de sujeto de iOS, precisa al píxel. Algo más lento,
        // bastante más limpio.
        let working = detail
        let subjectMask = await subjectMask(for: original, appliedTo: detail)

        var results: [DetectedGarment] = []
        for region in regions {
            guard
                let rawCrop = SegmentedGarmentExtractor.crop(region: region, from: working, refinedBy: subjectMask),
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
        region: SegmentedGarmentExtractor.Region?,
        candidates override: Set<GarmentKindName>? = nil,
        fallbackKind: GarmentKind? = nil
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
                region?.kind ?? fallbackKind ?? .other,
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
        if let override {
            candidates = override
        } else if let region {
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
            ?? fallbackKind
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

    // MARK: - Sujeto primero

    /// Lo que el segmentador ve dentro de la máscara de un sujeto.
    struct SubjectTally {
        /// Fracción de la foto que ocupa el sujeto.
        var area: Double
        /// Fracción del sujeto que el segmentador llama ropa.
        var clothing: Double
        /// Fracción del sujeto que es cara, pelo, brazos o piernas.
        var person: Double
        var byKind: [GarmentKind: Int]
        var byLabel: [ClothesSegmenter.Label: Int]

        var dominantKind: GarmentKind? { byKind.max { $0.value < $1.value }?.key }
        var dominantLabel: ClothesSegmenter.Label? { byLabel.max { $0.value < $1.value }?.key }
        /// Cuánto de la ropa es de la clase dominante.
        var dominantShare: Double {
            let total = byKind.values.reduce(0, +)
            guard total > 0, let top = byKind.values.max() else { return 0 }
            return Double(top) / Double(total)
        }
    }

    /// Por debajo de esto, lo que hay en el sujeto no se considera ropa.
    static let subjectClothingFloor = 0.2
    /// Por encima de esto de cara, pelo o piel, el sujeto es una persona.
    static let subjectPersonCeiling = 0.08
    /// Si la clase dominante no llega a esto, el sujeto son varias prendas
    /// pegadas —una camiseta tocando un pantalón— y las separa el segmentador.
    /// No es 1: el segmentador llama "pantalón" al bajo de muchas camisetas.
    static let subjectDominantShare = 0.6

    /// Cuánto tiene que medir un sujeto, comparado con el mayor, para contar
    /// como prenda propia y no como un trozo del otro.
    ///
    /// Un tercio: una capucha, un cordón o un bolsillo suelto no llegan; una
    /// camiseta al lado de un pantalón, sí. Por debajo se junta, que es lo que
    /// protege al caso de siempre —una foto, una prenda—.
    static let separateSubjectShare = 0.33
    /// Y cuánto puede solaparse con él. Lo que cae dentro del otro es parte
    /// del otro, por grande que sea.
    static let sameSubjectOverlap = 0.35

    /// Junta los sujetos que son trozos de la misma prenda y deja sueltos los
    /// que son prendas distintas.
    ///
    /// La medida es tonta a propósito —área y solape de recuadros— porque la
    /// pregunta lo es: ¿esto de aquí es un pedazo de aquello, o es otra cosa
    /// que está al lado? Nada de esto necesita un modelo, y meterlo haría
    /// impredecible el caso que ya funcionaba.
    static func groupedInstances(
        _ instances: [Int],
        observation: InstanceMaskObservation,
        handler: ImageRequestHandler,
        map: ClassMap
    ) async -> [IndexSet] {
        guard instances.count > 1 else { return [IndexSet(instances)] }

        struct Piece {
            let instance: Int
            let bounds: CGRect
            let area: Double
            let clothing: Double
        }

        var pieces: [Piece] = []
        for instance in instances {
            guard
                let buffer = try? observation.generateMaskedImage(
                    for: IndexSet(integer: instance),
                    imageFrom: handler,
                    croppedToInstancesExtent: false
                ),
                let masked = Self.cgImage(from: buffer),
                let bounds = CropNormalizer.opaqueBounds(of: masked),
                let tally = Self.tally(of: masked, in: map)
            else { continue }
            pieces.append(
                Piece(
                    instance: instance,
                    bounds: bounds,
                    area: tally.area,
                    clothing: tally.clothing
                )
            )
        }
        guard let largest = pieces.max(by: { $0.area < $1.area }) else {
            return [IndexSet(instances)]
        }

        // Cada pieza empieza sola; las que no se sostienen se pegan a la
        // mayor con la que se solapan.
        var groups: [IndexSet] = []
        var attachedToLargest = IndexSet(integer: largest.instance)
        for piece in pieces where piece.instance != largest.instance {
            let isBigEnough = piece.area >= largest.area * separateSubjectShare
            let isClothing = piece.clothing >= subjectClothingFloor
            let overlap = Self.overlapFraction(piece.bounds, inside: largest.bounds)
            if isBigEnough, isClothing, overlap < sameSubjectOverlap {
                groups.append(IndexSet(integer: piece.instance))
                DiagnosticsLog.record(
                    "SUJETO",
                    String(
                        format: "sujeto %d va suelto: %.0f%% del mayor, solape %.0f%%",
                        piece.instance, piece.area / max(largest.area, 0.0001) * 100, overlap * 100
                    )
                )
            } else {
                attachedToLargest.insert(piece.instance)
            }
        }
        groups.insert(attachedToLargest, at: 0)
        return groups
    }

    /// Cuánto de un recuadro cae dentro de otro, de 0 a 1.
    static func overlapFraction(_ rect: CGRect, inside other: CGRect) -> Double {
        let intersection = rect.intersection(other)
        guard !intersection.isNull, rect.width > 0, rect.height > 0 else { return 0 }
        return (intersection.width * intersection.height) / (rect.width * rect.height)
    }

    static func tally(of masked: CGImage, in map: ClassMap) -> SubjectTally? {
        guard
            let buffer = PixelBuffer(width: map.width, height: map.height),
            let context = buffer.makeContext()
        else { return nil }
        context.draw(masked, in: CGRect(x: 0, y: 0, width: map.width, height: map.height))

        var inside = 0, clothing = 0, person = 0
        var byKind: [GarmentKind: Int] = [:]
        var byLabel: [ClothesSegmenter.Label: Int] = [:]
        for y in 0..<map.height {
            for x in 0..<map.width where buffer[x, y, 3] > 127 {
                inside += 1
                guard let label = map[x, y] else { continue }
                if let kind = label.kind {
                    clothing += 1
                    byKind[kind, default: 0] += 1
                    byLabel[label, default: 0] += 1
                } else if label != .background {
                    person += 1
                }
            }
        }
        guard inside > 0 else { return nil }
        return SubjectTally(
            area: Double(inside) / Double(map.width * map.height),
            clothing: Double(clothing) / Double(inside),
            person: Double(person) / Double(inside),
            byKind: byKind,
            byLabel: byLabel
        )
    }

    /// El encaje de un recorte por sujeto: el de su tipo, **sin enderezar**.
    ///
    /// La máscara de iOS ya deja la cosa como está en la foto, y enderezar por
    /// el eje principal tumbaba lo que es diagonal por naturaleza —un zapato,
    /// una gorra de lado—. Eso era la "distorsión".
    static func subjectProfile(for kind: GarmentKind?) -> CropNormalizer.Profile {
        let base = kind.map { CropNormalizer.Profile.profile(for: $0) } ?? .square()
        return CropNormalizer.Profile(
            width: base.width, height: base.height,
            padding: base.padding, anchor: base.anchor,
            deskews: false,
            // Y **sin quitar motas**: lo que iOS levanta es la prenda entera,
            // y una mancha aparte suya es parte de ella. Ver `Profile`.
            despeckles: false
        )
    }

    /// Una prenda por sujeto de iOS, clasificada por lo que el segmentador ve
    /// dentro de su máscara.
    ///
    /// `nil` cuando el sujeto no resuelve la foto y hay que seguir por el
    /// segmentador: no hay sujeto, alguno es una persona, o alguno son varias
    /// prendas pegadas.
    private func extractFromSubjects(
        _ segmenter: ClothesSegmenter,
        image: CGImage,
        detail: CGImage,
        /// La foto tal cual llegó: la máscara se le pide a ella. Ver
        /// `extractGarmentsFromPixels`.
        original: CGImage
    ) async -> [DetectedGarment]? {
        guard
            // **La máscara se pide sobre la foto grande.** Pedida sobre la
            // copia de trabajo —1100 px— y aplicada luego sobre la de detalle,
            // el borde se amplía y sale dentado: eso era lo pixelado. Vision
            // la calcula a la resolución de la foto que se le da, así que
            // dándole la buena el canto sale como el de "copiar sujeto".
            let observation = try? await VisionStages.foregroundInstances(in: original),
            !observation.allInstances.isEmpty,
            let map = try? await segmenter.classMap(for: image)
        else { return nil }
        let handler = ImageRequestHandler(detail)
        let detailHandler = handler
        let instances = Array(observation.allInstances)

        struct Subject {
            var instances: IndexSet
            var tally: SubjectTally
            var kind: GarmentKind?
        }

        var subjects: [Subject] = []
        // **Lo que decide si dos sujetos son una prenda o dos es la foto, no
        // un interruptor.**
        //
        // Antes, al añadir a mano se juntaban **todos** los sujetos en uno:
        // partía de que el usuario fotografía una cosa, y con la chaqueta y su
        // capucha —o el zapato y su cordón— acertaba. Pero con dos prendas en
        // la misma foto daba una sola prenda hecha de las dos, que es lo que
        // nunca debería pasar: se ve a simple vista que son dos.
        //
        // Ahora se mira: un sujeto pequeño o metido dentro de otro es un trozo
        // suyo y se junta; un sujeto grande, con su ropa dentro y en su sitio
        // de la foto, es otra prenda. Ver `groupedInstances`.
        let merged = splitsInstances
            ? instances.map { IndexSet(integer: $0) }
            : await Self.groupedInstances(instances, observation: observation, handler: handler, map: map)
        for group in merged {
            let instance = group.first ?? 0
            guard
                let buffer = try? observation.generateMaskedImage(
                    for: group,
                    imageFrom: handler,
                    croppedToInstancesExtent: false
                ),
                let masked = Self.cgImage(from: buffer),
                let tally = Self.tally(of: masked, in: map)
            else { continue }

            let summary = String(
                format: "sujeto %d: %.0f%% de la foto · ropa %.0f%% · persona %.0f%% · %@ (%.0f%%)",
                instance, tally.area * 100, tally.clothing * 100, tally.person * 100,
                tally.dominantKind?.rawValue ?? "—", tally.dominantShare * 100
            )
            DiagnosticsLog.record("SUJETO", summary)

            guard tally.area >= minimumAreaFraction else { continue }
            // Alguien, aunque la pose no convenciera: que lo separe el
            // segmentador. Devolver a la persona como prenda es el fallo que
            // más caro nos ha salido.
            if tally.person > Self.subjectPersonCeiling { return nil }

            if tally.clothing >= Self.subjectClothingFloor {
                // Varias prendas en un solo sujeto: el sujeto no sirve.
                guard tally.dominantShare >= Self.subjectDominantShare else { return nil }
                subjects.append(Subject(instances: group, tally: tally, kind: tally.dominantKind))
            } else if merged.count == 1 {
                // Una sola cosa en la foto y el segmentador no la reconoce:
                // lo que sea lo dice el embedder, como con cualquier prenda
                // suelta.
                subjects.append(Subject(instances: group, tally: tally, kind: nil))
            }
        }
        guard !subjects.isEmpty else { return nil }

        // Un par de zapatos es **una** prenda, aunque iOS los separe en dos.
        let feet = subjects.filter { $0.kind == .feet }
        if feet.count > 1 {
            let pair = Subject(
                instances: feet.reduce(into: IndexSet()) { $0.formUnion($1.instances) },
                tally: feet[0].tally,
                kind: .feet
            )
            subjects = subjects.filter { $0.kind != .feet } + [pair]
        }

        var results: [DetectedGarment] = []
        var seenByKind: [GarmentKind: Int] = [:]
        for subject in subjects {
            guard
                let buffer = try? observation.generateMaskedImage(
                    for: subject.instances,
                    imageFrom: detailHandler,
                    croppedToInstancesExtent: false
                ),
                let masked = Self.cgImage(from: buffer),
                let tight = CropNormalizer.opaqueBounds(of: masked),
                let full = masked.cropping(to: tight),
                // A tamaño manejable, ya recortado: ver `keptCropMaxSide`.
                let rawCrop = Self.scaledDown(full, maxSide: Self.keptCropMaxSide) ?? full as CGImage?,
                let normalized = CropNormalizer.normalize(rawCrop, profile: Self.subjectProfile(for: subject.kind))
            else { continue }

            var colors = ColorExtractor.dominantColors(in: normalized)
            guard !Self.looksLikeSkin(colors) else { continue }

            // Camiseta o chaqueta lo decide el embedder, como siempre: el
            // segmentador las llama igual.
            let candidates: Set<GarmentKindName>?
            if subject.tally.dominantLabel == .upperClothes {
                candidates = [.upperBody, .outerLayer]
            } else if let kind = subject.kind, let name = GarmentKindName(rawValue: kind.rawValue) {
                candidates = [name]
            } else {
                candidates = nil
            }
            let described = await describe(
                normalized, region: nil, candidates: candidates, fallbackKind: subject.kind
            )
            let evidence = await readBrandEvidence(in: rawCrop)
            let refined = await refineIfNeeded(
                normalized: normalized,
                kind: described.kind,
                subcategory: described.subcategory,
                material: described.material,
                confidence: subject.kind == nil
                    ? (embedder == nil ? Self.degradedConfidenceCeiling : 0.7)
                    : 0.85,
                colorName: colors.first?.nameKey,
                evidence: evidence
            )
            colors = Self.renamed(colors, to: refined.colorName)

            let index = seenByKind[refined.kind, default: 0]
            seenByKind[refined.kind] = index + 1
            DiagnosticsLog.record(
                "SUJETO",
                "→ \(refined.kind.rawValue) \(refined.subcategory ?? "—") · recorte del sujeto de iOS"
            )

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
                    instanceIndex: index,
                    sourceRect: CGRect(
                        x: tight.minX / Double(masked.width),
                        y: tight.minY / Double(masked.height),
                        width: tight.width / Double(masked.width),
                        height: tight.height / Double(masked.height)
                    )
                )
            )
        }
        return results.isEmpty ? nil : results
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
    /// La misma prenda con el recorte que da el corte por color.
    private func colourCutout(
        of garment: DetectedGarment,
        from image: CGImage,
        using split: ColorSplitter.Split
    ) -> DetectedGarment? {
        guard
            let cut = ColorSplitter.cutout(image, using: split),
            let tight = CropNormalizer.opaqueBounds(of: cut),
            let rawCrop = cut.cropping(to: tight),
            let normalized = CropNormalizer.normalize(rawCrop, for: garment.kind)
        else { return nil }

        return garment.replacingImages(
            normalized: ImmutableImage(normalized),
            rawCrop: ImmutableImage(rawCrop)
        )
    }

    /// La prenda con la que seguir, si es que hay **una sola**.
    ///
    /// - Si el segmentador ya devolvió una, esa.
    /// - Si devolvió varias pero el color dice que la mancha es una, se
    ///   quedan unificadas en la mejor de ellas: el recorte bueno lo va a
    ///   producir el corte por color, que recorta la mancha entera, así que lo
    ///   único que hace falta de las piezas es **qué prenda es**.
    /// - Si el color también ve varias, no se toca nada: son prendas de
    ///   verdad, separadas sobre la misma foto.
    private func unified(_ garments: [DetectedGarment], pieces: Int?) -> DetectedGarment? {
        if garments.count == 1 { return garments.first }
        guard pieces == 1 else { return nil }

        // La mejor de ellas es la que menos se parece a un descarte: entre un
        // "otro" y un "pantalón", el pantalón. A igualdad, la primera, que es
        // la de mayor área — así llegan ordenadas.
        let best = garments.min { first, second in
            rank(first.kind) < rank(second.kind)
        }
        DiagnosticsLog.record(
            "RECORTE",
            "el color ve 1 pieza y el segmentador \(garments.count):"
                + " se unifican en \(best?.kind.rawValue ?? "—")"
        )
        return best
    }

    /// Junta lo que es **una prenda partida en dos**.
    ///
    /// El mapa de clases no ve prendas, ve píxeles de una clase. Una camiseta
    /// doblada, una camisa con una sombra fuerte en el pliegue o un pantalón
    /// con el cinturón cruzado rompen la mancha en dos trozos, y cada trozo
    /// sale como una prenda: dos fichas, dos recortes a medias y un armario
    /// con la misma camiseta dos veces.
    ///
    /// La pista de que son una sola es geométrica y no hace falta saber de
    /// ropa para leerla: **misma clase y pegados**. Dos prendas de verdad del
    /// mismo tipo en una foto están separadas —se dejan aparte, justo para que
    /// se vean las dos—; dos trozos de la misma se tocan o se solapan.
    ///
    /// Lo que **no** se junta nunca es lo de clases distintas: una chaqueta
    /// encima de una camiseta se solapa entera y son dos prendas, y ahí la
    /// clase es la que lo dice.
    static func merged(_ garments: [DetectedGarment]) -> [DetectedGarment] {
        guard garments.count > 1 else { return garments }

        var survivors: [DetectedGarment] = []
        for garment in garments {
            guard let rect = garment.sourceRect else {
                survivors.append(garment)
                continue
            }

            // ¿Es un trozo de algo que ya está?
            let twin = survivors.firstIndex { survivor in
                guard survivor.kind == garment.kind, let other = survivor.sourceRect else {
                    return false
                }
                return Self.arePieces(of: other, and: rect)
            }

            guard let twin else {
                survivors.append(garment)
                continue
            }

            // Se queda el trozo mayor: es el que trae más prenda, y el recorte
            // del pequeño no aporta nada que el grande no tenga peor.
            let existing = survivors[twin].sourceRect.map { $0.width * $0.height } ?? 0
            let candidate = rect.width * rect.height
            if candidate > existing { survivors[twin] = garment }

            DiagnosticsLog.record(
                "SEGMENTA",
                "dos trozos pegados de \(garment.kind.rawValue): es una prenda, no dos"
            )
        }
        return survivors
    }

    /// Junta en una las regiones que se pisan.
    ///
    /// Solo se llama donde ya se sabe que **no hay nadie puesto** y el fondo es
    /// liso: ahí dos regiones que se solapan no pueden ser dos prendas, porque
    /// dos prendas tiradas sobre una mesa se dejan aparte.
    ///
    /// Se conserva la de mejor tipo —ver `rank`— y, a igualdad, la mayor: el
    /// recorte bueno lo va a dar el corte por color de todas formas, y lo que
    /// importa de la superviviente es su clase, su marca y sus colores.
    static func collapsedIfOverlapping(_ garments: [DetectedGarment]) -> [DetectedGarment] {
        guard garments.count > 1 else { return garments }

        var survivors: [DetectedGarment] = []
        for garment in garments {
            guard let rect = garment.sourceRect else {
                survivors.append(garment)
                continue
            }

            let twin = survivors.firstIndex { survivor in
                guard let other = survivor.sourceRect else { return false }
                return Self.overlapFraction(of: other, and: rect) >= Self.overlapToBeTheSame
                    || Self.arePieces(of: other, and: rect)
            }

            guard let twin else {
                survivors.append(garment)
                continue
            }

            let keeps = Self.betterOfTwo(survivors[twin], garment)
            survivors[twin] = keeps
        }
        return survivors
    }

    /// Cuánto se pisan dos rectángulos, respecto al menor de los dos.
    private static func overlapFraction(of one: CGRect, and other: CGRect) -> Double {
        let intersection = one.intersection(other)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let area = intersection.width * intersection.height
        let smaller = min(one.width * one.height, other.width * other.height)
        guard smaller > 0 else { return 0 }
        return area / smaller
    }

    /// A partir de cuánto pisarse dos regiones son la misma prenda.
    ///
    /// Un tercio del menor: dos etiquetas del mapa sobre la misma prenda se
    /// solapan mucho más que eso, y dos prendas de verdad puestas en una mesa
    /// no se tocan.
    static let overlapToBeTheSame = 0.33

    /// Cuál de las dos representa mejor a la prenda.
    private static func betterOfTwo(
        _ one: DetectedGarment, _ other: DetectedGarment
    ) -> DetectedGarment {
        func score(_ garment: DetectedGarment) -> (Int, Double) {
            let rank: Int
            switch garment.kind {
            case .other: rank = 3
            case .head, .bag: rank = 2
            default: rank = 1
            }
            let area = garment.sourceRect.map { $0.width * $0.height } ?? 0
            return (rank, -area)
        }
        return score(one) <= score(other) ? one : other
    }

    /// Si dos rectángulos son trozos de la misma prenda.
    ///
    /// Se solapan, o casi se tocan: un pliegue deja una grieta de unos pocos
    /// píxeles, no un palmo de fondo.
    private static func arePieces(of one: CGRect, and other: CGRect) -> Bool {
        if one.intersects(other) { return true }

        // Pegados: el hueco entre los dos es pequeño y además se llevan por
        // el otro eje, que es como caen los trozos de una prenda doblada.
        let gapX = max(0, max(one.minX, other.minX) - min(one.maxX, other.maxX))
        let gapY = max(0, max(one.minY, other.minY) - min(one.maxY, other.maxY))
        let overlapX = min(one.maxX, other.maxX) - max(one.minX, other.minX)
        let overlapY = min(one.maxY, other.maxY) - max(one.minY, other.minY)

        let touchingVertically = gapY <= Self.pieceGap
            && overlapX >= 0.4 * min(one.width, other.width)
        let touchingHorizontally = gapX <= Self.pieceGap
            && overlapY >= 0.4 * min(one.height, other.height)
        return touchingVertically || touchingHorizontally
    }

    /// Cuánto fondo puede haber entre dos trozos de la misma prenda.
    ///
    /// Un 3% del lado de la foto: lo que deja un pliegue o una sombra, no lo
    /// que hay entre dos prendas puestas una al lado de la otra.
    static let pieceGap = 0.03

    /// Cuánto pesa cada tipo al elegir con cuál quedarse. Menos es mejor.
    private func rank(_ kind: GarmentKind) -> Int {
        switch kind {
        case .other: 3
        case .head, .bag: 2
        default: 1
        }
    }

    private func refinedOnSolidBackground(
        _ garments: [DetectedGarment],
        from image: CGImage,
        detail: CGImage,
        original: CGImage
    ) async -> [DetectedGarment] {
        guard !garments.isEmpty else { return garments }

        // **Primero: ¿hay alguien puesto?** Con una persona vestida, el
        // segmentador es el que sabe separar camiseta de pantalón, y todo lo de
        // abajo —juntar regiones, tomar el sujeto entero— sería mezclarlas.
        // Una prenda tirada en la mesa no tiene piernas: ver
        // `hasConvincingPerson`.
        if await Self.hasConvincingPerson(in: image) {
            return garments
        }

        // **Sin nadie puesto, lo que se toca es una prenda.**
        //
        // El mapa de clases no parte solo por pliegues: a una camiseta lisa le
        // llama "parte de arriba" al pecho y otra cosa al bajo, y entonces son
        // dos regiones de clases distintas que se solapan. Cada una salía
        // recortada por su lado, y la de arriba con un mordisco enorme donde
        // empezaba la otra.
        let collapsed = Self.collapsedIfOverlapping(garments)
        if collapsed.count < garments.count {
            DiagnosticsLog.record(
                "SEGMENTA",
                "\(garments.count) regiones solapadas sin nadie puesto: es \(collapsed.count) prenda(s)"
            )
        }

        // **El sujeto de iOS, primero — con cualquier fondo.**
        //
        // "Copiar sujeto" —la máscara de primer plano del sistema, la misma de
        // mantener pulsada una foto— es el mejor recorte que hay para una cosa
        // sola: está entrenada para separarla del fondo y lo hace al píxel. Lo
        // que no sabe es qué es, y eso ya lo ha dicho el segmentador: se toma
        // el sujeto como imagen y la prenda detectada como todo lo demás.
        //
        // Antes esto solo se probaba con fondo liso, y con un fondo gris con
        // degradado —el de casi todas las fotos de tienda— ni se intentaba:
        // por eso seguía saliendo el recorte mordido. Ahora se intenta siempre
        // que haya una sola prenda y nadie puesto.
        //
        // Se mide antes de quedárselo —forma y contaminación— porque un sujeto
        // que se trae la percha o la mesa es peor que lo de siempre. Si no
        // pasa, o no hay sujeto, se sigue exactamente como antes.
        if collapsed.count == 1, let garment = collapsed.first,
           let lifted = await subjectCutout(from: original, detail: detail) {
            let cutout = lifted.normalized.cgImage
            let report = CutoutQuality.assess(cutout)
            let dirt = CutoutQuality.contamination(of: cutout, backgroundOf: image)
            if report.isGoodEnough, dirt < Self.acceptableContamination {
                DiagnosticsLog.record(
                    "RECORTE",
                    String(format: "vale el sujeto de iOS (%@, contaminación %.2f)", report.summary, dirt)
                )
                return [
                    garment
                        .replacingImages(normalized: lifted.normalized, rawCrop: lifted.rawCrop)
                        .replacingColors(ColorExtractor.dominantColors(in: cutout)),
                ]
            }
            DiagnosticsLog.record(
                "RECORTE",
                String(format: "el sujeto de iOS no basta (%@, contaminación %.2f)", report.summary, dirt)
            )
        }

        guard SolidBackground.isLikely(in: image) else {
            DiagnosticsLog.record("RECORTE", "el fondo no es liso: se deja lo del segmentador")
            return collapsed
        }

        // **Cuántas prendas hay lo dice el color, no el segmentador.**
        //
        // Sobre fondo liso hay una forma barata de contarlas que no depende de
        // saber de ropa: mirar cuántas manchas separadas hay que no sean del
        // color del fondo. Dos perneras unidas por el tiro son **una** mancha;
        // una camiseta y un pantalón tirados aparte son dos. Ver
        // `ColorSplitter`.
        let split = ColorSplitter.split(image)
        let garments = collapsed
        guard let garment = unified(garments, pieces: split?.pieceCount) else {
            return garments
        }

        // **Atajo para la foto de tienda.**
        //
        // Fondo blanco, prenda sola, una sola mancha: ahí el corte por color
        // no es una de tres opciones, es **la** respuesta. Calcular además la
        // máscara de sujeto —que es una petición a Vision, la parte cara de
        // todo esto— y puntuar tres recortes a resolución completa era gastar
        // segundos para volver a elegir el que ya se sabía.
        //
        // Se comprueba igualmente antes de quedárselo: si el recorte por color
        // no puntúa bien, se sigue por el camino largo y compiten los tres.
        if let split, split.pieceCount == 1, let quick = colourCutout(of: garment, from: image, using: split) {
            let report = CutoutQuality.assess(quick.normalized.cgImage)
            if report.isGoodEnough {
                DiagnosticsLog.record(
                    "RECORTE",
                    "fondo liso y una sola pieza: vale el corte por color (\(report.summary))"
                )
                return [quick]
            }
            DiagnosticsLog.record(
                "RECORTE",
                "el corte por color no basta (\(report.summary)): se prueban los tres"
            )
        }

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

        if let lifted = await subjectCutout(from: original, detail: detail) {
            candidates.append(("sujeto", garment.replacingImages(
                normalized: lifted.normalized,
                rawCrop: lifted.rawCrop
            )))
        }

        if let split, let coloured = colourCutout(of: garment, from: image, using: split) {
            candidates.append(("color", coloured))
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

    /// Todos los sujetos de iOS juntos, aplicados sobre `detail` y del mismo
    /// tamaño. Sirve para afinar el canto de los recortes del segmentador.
    private func subjectMask(
        for original: CGImage,
        appliedTo detail: CGImage
    ) async -> CGImage? {
        guard
            // Sobre la grande: ver `extractFromSubjects`.
            let observation = try? await VisionStages.foregroundInstances(in: original),
            !observation.allInstances.isEmpty,
            let buffer = try? observation.generateMaskedImage(
                for: observation.allInstances,
                imageFrom: ImageRequestHandler(detail),
                croppedToInstancesExtent: false
            )
        else { return nil }
        return Self.cgImage(from: buffer)
    }

    /// La prenda levantada del fondo, sin describirla.
    ///
    /// Comparte trabajo con `extractSingleSubject`, que hace lo mismo y además
    /// la clasifica: aquí la clase ya la sabemos.
    private func subjectCutout(
        from original: CGImage,
        detail: CGImage
    ) async -> (normalized: ImmutableImage, rawCrop: ImmutableImage)? {
        guard
            let observation = try? await VisionStages.foregroundInstances(in: original),
            let buffer = try? observation.generateMaskedImage(
                for: observation.allInstances,
                imageFrom: ImageRequestHandler(detail),
                croppedToInstancesExtent: true
            ),
            let subject = Self.cgImage(from: buffer),
            let tight = CropNormalizer.opaqueBounds(of: subject),
            let full = subject.cropping(to: tight),
            let rawCrop = Self.scaledDown(full, maxSide: Self.keptCropMaxSide) ?? full as CGImage?,
            // Sin enderezar: ver `subjectProfile(for:)`.
            // let normalized = CropNormalizer.normalize(rawCrop)
            let normalized = CropNormalizer.normalize(rawCrop, profile: Self.subjectProfile(for: nil))
        else { return nil }
        return (ImmutableImage(normalized), ImmutableImage(rawCrop))
    }

    private func extractSingleSubject(from original: CGImage, detail: CGImage) async -> [DetectedGarment] {
        guard
            let observation = try? await VisionStages.foregroundInstances(in: original),
            let buffer = try? observation.generateMaskedImage(
                for: observation.allInstances,
                imageFrom: ImageRequestHandler(detail),
                croppedToInstancesExtent: true
            ),
            let subject = Self.cgImage(from: buffer),
            let tight = CropNormalizer.opaqueBounds(of: subject),
            let full = subject.cropping(to: tight),
            let rawCrop = Self.scaledDown(full, maxSide: Self.keptCropMaxSide) ?? full as CGImage?,
            // Cuadrado: aquí todavía no se sabe qué prenda es —eso lo dice
            // `describe` **después**— y elegir el perfil de pantalón para algo
            // que resulte ser una gorra encaja peor que no elegir ninguno.
            // Y sin enderezar: ver `subjectProfile(for:)`.
            // let normalized = CropNormalizer.normalize(rawCrop)
            let normalized = CropNormalizer.normalize(rawCrop, profile: Self.subjectProfile(for: nil))
        else { return [] }

        let area = Double(tight.width * tight.height) / Double(subject.width * subject.height)
        guard area >= minimumAreaFraction else { return [] }

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
        guard area >= SegmentedGarmentExtractor.minimumArea(
            for: region.kind.kind,
            base: minimumAreaFraction
        ) else { return nil }

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
