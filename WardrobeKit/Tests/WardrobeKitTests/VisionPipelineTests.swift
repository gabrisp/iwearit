import CoreGraphics
import CoreML
import Foundation
import Testing
import WKCore
@testable import WKVision

/// Esqueleto de referencia, en convención Vision (y=1 arriba).
private let standing = BodyLandmarks(
    shoulderY: 0.78,
    hipY: 0.52,
    kneeY: 0.28,
    ankleY: 0.06,
    confidence: 0.9
)

private func solidImage(
    red: Double, green: Double, blue: Double,
    size: Int = 256,
    insetFraction: Double = 0
) -> CGImage {
    let context = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
    let inset = CGFloat(Double(size) * insetFraction)
    context.fill(CGRect(
        x: inset, y: inset,
        width: CGFloat(size) - inset * 2,
        height: CGFloat(size) - inset * 2
    ))
    return context.makeImage()!
}

@Suite("Bandas corporales")
struct BodyBandTests {

    @Test("Cada altura cae en su banda")
    func bandsByHeight() {
        #expect(standing.band(forCenterY: 0.92) == .aboveShoulders, "una gorra")
        #expect(standing.band(forCenterY: 0.66) == .torso, "una camiseta")
        #expect(standing.band(forCenterY: 0.35) == .legs, "un pantalón")
        #expect(standing.band(forCenterY: 0.03) == .feet, "unos zapatos")
    }

    @Test("Cada banda mapea al kind que le toca")
    func bandKinds() {
        #expect(BodyBand.aboveShoulders.kind == .head)
        #expect(BodyBand.torso.kind == .upperBody)
        #expect(BodyBand.legs.kind == .lowerBody)
        #expect(BodyBand.feet.kind == .feet)
    }

    /// Lo importante del modo degradado no es acertar siempre, es **saber
    /// cuándo no está seguro** para que la prenda acabe en la pantalla de
    /// revisión en vez de colarse en la balda equivocada.
    @Test("Cerca de una frontera la confianza baja")
    func confidenceDropsNearBoundaries() {
        let onBoundary = standing.bandConfidence(forCenterY: standing.hipY)
        let farFromAny = standing.bandConfidence(forCenterY: 0.66)

        #expect(onBoundary < farFromAny)
        #expect(onBoundary <= standing.confidence * 0.55)
    }

    @Test("El modo degradado nunca se declara seguro")
    func degradedNeverConfident() {
        #expect(GarmentPipeline.degradedConfidenceCeiling < GarmentDraft.reviewConfidenceThreshold,
                "toda prenda del modo degradado tiene que entrar en revisión")
    }
}

@Suite("Normalización del recorte")
struct CropNormalizerTests {

    @Test("La caja opaca ignora el margen transparente")
    func opaqueBoundsIgnoresTransparency() throws {
        let image = solidImage(red: 0.8, green: 0.2, blue: 0.2, size: 200, insetFraction: 0.25)
        let bounds = try #require(CropNormalizer.opaqueBounds(of: image))

        #expect(abs(bounds.width - 100) <= 2)
        #expect(abs(bounds.height - 100) <= 2)
        #expect(abs(bounds.minX - 50) <= 2)
    }

    /// El contrato que hace que las baldas se vean ordenadas: toda prenda sale
    /// cuadrada, centrada y con el mismo margen, venga de donde venga.
    @Test("La salida es cuadrada y respeta el margen del 8%")
    func normalizedOutputHonoursPadding() throws {
        let image = solidImage(red: 0.2, green: 0.4, blue: 0.7, size: 300, insetFraction: 0.30)
        let normalized = try #require(CropNormalizer.normalize(image, side: 512))

        #expect(normalized.width == 512)
        #expect(normalized.height == 512)

        let bounds = try #require(CropNormalizer.opaqueBounds(of: normalized))
        let expected = 512.0 * (1 - 2 * CropNormalizer.paddingFraction)
        #expect(abs(bounds.width - expected) <= 6, "la silueta ocupa el 84% del lienzo")
        // Centrada: los márgenes de ambos lados coinciden.
        #expect(abs(bounds.minX - (512 - bounds.width) / 2) <= 3)
    }
}

@Suite("Color")
struct ColorExtractorTests {

    @Test("Un color plano se reconoce y se nombra")
    func solidColourIsNamed() throws {
        let image = solidImage(red: 0.78, green: 0.15, blue: 0.15, insetFraction: 0.1)
        let colors = ColorExtractor.dominantColors(in: image)

        let dominant = try #require(colors.first)
        #expect(dominant.nameKey == "rojo")
        #expect(dominant.weight > 0.9)
    }

    /// Un nombre de prenda que cambia entre ejecuciones es un bug que nadie
    /// sabe reproducir. Por eso la siembra del k-means es determinista.
    @Test("La misma imagen da siempre el mismo color")
    func extractionIsDeterministic() {
        let image = solidImage(red: 0.36, green: 0.38, blue: 0.24, insetFraction: 0.15)
        let first = ColorExtractor.dominantColors(in: image).map(\.nameKey)
        let second = ColorExtractor.dominantColors(in: image).map(\.nameKey)

        #expect(first == second)
        #expect(first.first == "oliva")
    }

    @Test("Azul marino y negro no se confunden")
    func navyIsNotBlack() {
        let navy = ColorExtractor.rgbToLab(0.13, 0.18, 0.34)
        let black = ColorExtractor.rgbToLab(0.05, 0.05, 0.06)

        #expect(NamedColorTable.closestName(toLab: navy) == "azul marino")
        #expect(NamedColorTable.closestName(toLab: black) == "negro")
    }

    @Test("Lab ida y vuelta conserva el color")
    func labRoundTrip() {
        let lab = ColorExtractor.rgbToLab(0.45, 0.13, 0.16)
        let (r, g, b) = ColorExtractor.labToRGB(lab)

        #expect(abs(r - 0.45) < 0.01)
        #expect(abs(g - 0.13) < 0.01)
        #expect(abs(b - 0.16) < 0.01)
    }
}

@Suite("Descarte de piel")
struct SkinRejectionTests {

    private func color(_ r: Double, _ g: Double, _ b: Double, weight: Double = 1) -> NamedColor {
        NamedColor(nameKey: "x", red: r, green: g, blue: b, weight: weight)
    }

    /// Es lo que separa este armario del de la captura de referencia, donde se
    /// cuelan caras, gafas con ojos dentro y trozos de brazo.
    @Test("Los tonos de piel se reconocen en todo el rango")
    func skinTonesDetected() {
        #expect(GarmentPipeline.isSkinTone(color(0.96, 0.82, 0.72)), "piel muy clara")
        #expect(GarmentPipeline.isSkinTone(color(0.82, 0.62, 0.48)), "piel media")
        #expect(GarmentPipeline.isSkinTone(color(0.45, 0.30, 0.22)), "piel oscura")
    }

    @Test("La ropa no se confunde con piel")
    func clothingIsNotSkin() {
        #expect(!GarmentPipeline.isSkinTone(color(0.05, 0.05, 0.06)), "negro")
        #expect(!GarmentPipeline.isSkinTone(color(0.20, 0.38, 0.68)), "azul")
        #expect(!GarmentPipeline.isSkinTone(color(0.22, 0.52, 0.30)), "verde")
        #expect(!GarmentPipeline.isSkinTone(color(0.97, 0.97, 0.96)), "blanco")
    }

    @Test("Una región mayoritariamente piel se descarta")
    func mostlySkinRegionRejected() {
        let arm = [color(0.82, 0.62, 0.48, weight: 0.7), color(0.2, 0.2, 0.2, weight: 0.3)]
        let sleeve = [color(0.82, 0.62, 0.48, weight: 0.2), color(0.2, 0.3, 0.6, weight: 0.8)]

        #expect(GarmentPipeline.looksLikeSkin(arm))
        #expect(!GarmentPipeline.looksLikeSkin(sleeve), "una manga con algo de brazo sigue siendo prenda")
    }
}


@Suite("Marca")
struct BrandRecognizerTests {

    @Test("Lee la marca aunque venga pegada a otras palabras")
    func matchesInsideALine() {
        #expect(BrandRecognizer.match("ADIDAS ORIGINALS") == "Adidas")
        #expect(BrandRecognizer.match("zara man") == "Zara")
        #expect(BrandRecognizer.match("hecho en Portugal para LACOSTE") == "Lacoste")
    }

    @Test("Aguanta los fallos típicos del OCR, pero solo uno")
    func toleratesOneMistake() {
        // rn/m, l/I, 0/O: lo que el reconocedor confunde de verdad.
        #expect(BrandRecognizer.match("LAC0STE") == "Lacoste")
        #expect(BrandRecognizer.match("pumaa") == "Puma")
        // Dos fallos ya no: a esa distancia casa cualquier cosa con cualquiera.
        #expect(BrandRecognizer.match("laa0ste") == nil)
    }

    @Test("No inventa marcas donde solo hay texto")
    func doesNotInventBrands() {
        #expect(BrandRecognizer.match("SAN FRANCISCO 1994") == nil)
        #expect(BrandRecognizer.match("100% algodón") == nil)
        // Palabras cortas: con cuatro letras y una de margen, "lees" casaría
        // con "lee" y llenaría el armario de fichas equivocadas.
        #expect(BrandRecognizer.match("live") == nil)
    }

    @Test("Apóstrofos y acentos no cambian la marca")
    func foldsPunctuation() {
        #expect(BrandRecognizer.match("Levi's") == "Levi's")
        #expect(BrandRecognizer.match("LEVIS") == "Levi's")
        #expect(BrandRecognizer.match("Stüssy") == "Stüssy")
    }
}

// MARK: - Instancias

/// Construye un mapa de clases a mano, como el que devolvería SegFormer.
///
/// El lado es pequeño a propósito: lo que se comprueba es la lógica de separar
/// y volver a juntar, y a 128 se lee igual que a 512 corriendo mil veces más
/// rápido.
private func classMap(side: Int = 128, fill: (Int, Int) -> Int) -> ClassMap {
    let array = try! MLMultiArray(
        shape: [1, 1, NSNumber(value: side), NSNumber(value: side)],
        dataType: .float32
    )
    for y in 0..<side {
        for x in 0..<side {
            array[y * side + x] = NSNumber(value: Float(fill(x, y)))
        }
    }
    return ClassMap(array: array, side: side)
}

private let upperClothes = ClothesSegmenter.Label.upperClothes.rawValue
private let leftArm = ClothesSegmenter.Label.leftArm.rawValue

@Suite("Componentes conexas")
struct ConnectedComponentsTests {

    @Test("Dos manchas separadas son dos componentes")
    func separateBlobsAreSeparateComponents() {
        let side = 32
        var mask = [UInt8](repeating: 0, count: side * side)
        for y in 2..<8 { for x in 2..<8 { mask[y * side + x] = 1 } }
        for y in 20..<30 { for x in 20..<30 { mask[y * side + x] = 1 } }

        let result = ConnectedComponents.label(mask: mask, width: side, height: side)

        #expect(result.components.count == 2)
        #expect(result.components.map(\.pixelCount).sorted() == [36, 100])
        let first = result.components[0]
        #expect(first.bounds == CGRect(x: 2, y: 2, width: 6, height: 6))
    }

    /// En diagonal no se juntan: dos prendas que se rozan por una esquina son
    /// dos prendas, y con el borde dentado de una máscara eso pasa a menudo.
    @Test("Tocarse solo en diagonal no las une")
    func diagonalTouchDoesNotConnect() {
        let side = 8
        var mask = [UInt8](repeating: 0, count: side * side)
        mask[2 * side + 2] = 1
        mask[3 * side + 3] = 1

        let result = ConnectedComponents.label(mask: mask, width: side, height: side)
        #expect(result.components.count == 2)
    }
}

@Suite("Separación en instancias")
struct InstanceSeparationTests {

    /// El caso que no funcionaba: SegFormer dice "esto es upper-clothes" de las
    /// dos camisetas, y quedarse con la caja de la clase metía las dos —y la
    /// colcha de en medio— en una sola prenda.
    @Test("Dos prendas de la misma clase son dos prendas")
    func twoGarmentsOfTheSameClassSplit() {
        let map = classMap { x, y in
            let left = (8..<40).contains(x) && (8..<40).contains(y)
            let right = (88..<120).contains(x) && (8..<40).contains(y)
            return left || right ? upperClothes : 0
        }

        let regions = SegmentedGarmentExtractor.regions(in: map)

        #expect(regions.count == 2)
        #expect(regions.allSatisfy { $0.kind == .upperBody })
        #expect(Set(regions.map(\.instanceIndex)) == [0, 1])
        // Cada máscara es la suya: la de la izquierda no puede reclamar un
        // píxel de la de la derecha.
        let first = regions.first { $0.bounds.minX < 50 }!
        #expect(first.mask.contains(x: 20, y: 20))
        #expect(!first.mask.contains(x: 100, y: 20))
    }

    /// Y el riesgo del camino contrario: un brazo cruzado parte la camiseta en
    /// dos trozos que no se tocan. Eso no son dos prendas.
    @Test("Un brazo cruzado no parte la camiseta en dos")
    func occlusionDoesNotSplitAGarment() {
        let map = classMap { x, y in
            guard (20..<100).contains(x), (20..<100).contains(y) else { return 0 }
            // El brazo, en diagonal: deja dos trozos cuyas cajas se montan casi
            // por completo, que es lo que los delata como la misma prenda.
            return abs(x - y) < 4 ? leftArm : upperClothes
        }

        let regions = SegmentedGarmentExtractor.regions(in: map)

        #expect(regions.count == 1)
        #expect(regions.first?.instanceIndex == 0)
    }

    /// Un par de zapatos es una prenda aunque estén a medio metro.
    @Test("Los dos zapatos siguen siendo un par")
    func shoesStayOnePair() {
        let leftShoe = ClothesSegmenter.Label.leftShoe.rawValue
        let rightShoe = ClothesSegmenter.Label.rightShoe.rawValue
        let map = classMap { x, y in
            guard (96..<120).contains(y) else { return 0 }
            if (10..<40).contains(x) { return leftShoe }
            if (80..<110).contains(x) { return rightShoe }
            return 0
        }

        let regions = SegmentedGarmentExtractor.regions(in: map)

        #expect(regions.count == 1)
        #expect(regions.first?.kind == .feet)
    }

    /// Una mancha suelta de la misma clase no asciende a prenda por existir.
    @Test("Una mota no se convierte en la segunda prenda")
    func aSpeckDoesNotBecomeAGarment() {
        let map = classMap { x, y in
            let garment = (8..<60).contains(x) && (8..<60).contains(y)
            // ~0,9% del mapa: pasa el mínimo general pero no el que se le pide
            // a una segunda prenda de la misma clase.
            let speck = (100..<112).contains(x) && (100..<112).contains(y)
            return garment || speck ? upperClothes : 0
        }

        let regions = SegmentedGarmentExtractor.regions(in: map)

        #expect(regions.count == 1)
        #expect(regions.first?.bounds.minX == 8)
    }
}

@Suite("Perfil de normalización")
struct NormalizationProfileTests {

    /// Un pantalón no se encaja como una camiseta: lienzo 4:5 y colgado de
    /// arriba, que es como se ve en una percha.
    @Test("Las prendas de abajo salen en lienzo alto y colgadas de arriba")
    func lowerBodyHangsFromTheTop() throws {
        // Ancha y baja, como unos pantalones cortos: le sobra sitio vertical,
        // que es cuando el anclaje significa algo.
        let image = wideImage(width: 400, height: 160)
        let normalized = try #require(CropNormalizer.normalize(image, for: .lowerBody))

        #expect(normalized.width == 1024)
        #expect(normalized.height == 1280)

        let bounds = try #require(CropNormalizer.opaqueBounds(of: normalized))
        // `opaqueBounds` cuenta filas desde arriba: pegada al margen superior.
        let margin = 1024.0 * 0.08
        #expect(abs(bounds.minY - margin) <= 4, "colgada del margen, no flotando en medio")
        #expect(bounds.minY < Double(normalized.height) / 4)
    }

    @Test("Una camiseta sigue en cuadrado y centrada")
    func upperBodyStaysSquare() throws {
        let image = wideImage(width: 400, height: 160)
        let normalized = try #require(CropNormalizer.normalize(image, for: .upperBody))

        #expect(normalized.width == 1024)
        #expect(normalized.height == 1024)

        let bounds = try #require(CropNormalizer.opaqueBounds(of: normalized))
        let top = bounds.minY
        let bottom = Double(normalized.height) - bounds.maxY
        #expect(abs(top - bottom) <= 4, "centrada")
    }

    /// El eje principal de un pantalón con las perneras abiertas no apunta a
    /// nada útil: enderezarlo por él lo tuerce.
    @Test("Pantalones y calzado no se enderezan")
    func trousersAndShoesSkipDeskew() {
        #expect(CropNormalizer.Profile.profile(for: .lowerBody).deskews == false)
        #expect(CropNormalizer.Profile.profile(for: .feet).deskews == false)
        #expect(CropNormalizer.Profile.profile(for: .upperBody).deskews == true)
    }

    /// Los accesorios llevan más aire: una gorra llenando el lienzo al lado de
    /// una camiseta que no lo llena parece más grande que la camiseta.
    @Test("Los accesorios llevan más margen")
    func accessoriesGetMoreAir() {
        let cap = CropNormalizer.Profile.profile(for: .head)
        let shirt = CropNormalizer.Profile.profile(for: .upperBody)
        #expect(cap.padding > shirt.padding)
    }
}

private func wideImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(red: 0.2, green: 0.3, blue: 0.6, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

@Suite("Prendas partidas")
struct SplitGarmentTests {

    private static let pants = ClothesSegmenter.Label.pants.rawValue

    /// El caso que salía partido en tres: un pantalón sobre fondo blanco.
    /// Cinturilla arriba y dos perneras que no se tocan.
    @Test("Un pantalón es una prenda, no tres")
    func trousersStayOneGarment() {
        let map = classMap { x, y in
            // Cinturilla: una banda ancha arriba.
            if (30..<98).contains(x), (20..<40).contains(y) { return Self.pants }
            // Perneras: dos columnas separadas por un hueco estrecho.
            if (30..<60).contains(x), (40..<110).contains(y) { return Self.pants }
            if (68..<98).contains(x), (40..<110).contains(y) { return Self.pants }
            return 0
        }

        let regions = SegmentedGarmentExtractor.regions(in: map)

        #expect(regions.count == 1)
        #expect(regions.first?.kind == .lowerBody)
        // Y la máscara cubre las dos perneras, no solo una.
        let region = try? #require(regions.first)
        #expect(region?.mask.contains(x: 45, y: 80) == true)
        #expect(region?.mask.contains(x: 80, y: 80) == true)
    }

    /// Sin perder lo de ayer: dos prendas de verdad, separadas, siguen siendo
    /// dos. El hueco entre ellas es del orden de su propio tamaño.
    @Test("Dos pantalones separados siguen siendo dos")
    func twoTrousersStillSplit() {
        let map = classMap { x, y in
            if (6..<30).contains(x), (20..<110).contains(y) { return Self.pants }
            if (98..<122).contains(x), (20..<110).contains(y) { return Self.pants }
            return 0
        }

        let regions = SegmentedGarmentExtractor.regions(in: map)
        #expect(regions.count == 2)
    }
}

@Suite("Evidencia de marca")
struct BrandEvidenceTests {

    /// La regla que da nombre a todo esto: sin pruebas, no hay marca.
    @Test("Un parecido visual no basta para escribir una marca")
    func embeddingAloneIsNotEnough() {
        let only = [BrandEvidence(brand: "Nike", source: .embedding, confidence: 1.0)]
        #expect(BrandVerdict.resolve(only) == nil, "el techo del embedding está por debajo del listón")
    }

    @Test("Una lectura limpia de OCR sí basta")
    func cleanOCRIsEnough() {
        let read = [BrandEvidence(brand: "Zara", source: .ocr, confidence: 1.0)]
        #expect(BrandVerdict.resolve(read) == "Zara")
    }

    /// El caso que justifica guardar las evidencias y no solo el nombre: una
    /// lectura con errata no basta sola, y confirmada fuera sí.
    @Test("Una lectura dudosa se confirma con la segunda opinión")
    func typoConfirmedRemotely() {
        let doubtful = [BrandEvidence(brand: "Levi's", source: .ocr, confidence: 0.62)]
        #expect(BrandVerdict.resolve(doubtful) == nil)

        let confirmed = doubtful + [
            BrandEvidence(brand: "Levi's", source: .remote, confidence: 0.7)
        ]
        #expect(BrandVerdict.resolve(confirmed) == "Levi's")
    }

    /// Dos marcas distintas empatadas: callarse sale más barato que elegir.
    @Test("Si dos marcas empatan, no hay marca")
    func tiesResolveToNothing() {
        let tied = [
            BrandEvidence(brand: "Adidas", source: .ocr, confidence: 0.9),
            BrandEvidence(brand: "Nike", source: .ocr, confidence: 0.9),
        ]
        #expect(BrandVerdict.resolve(tied) == nil)
    }

    @Test("Lo que escribe el usuario manda sobre todo")
    func userWins() {
        let mixed = [
            BrandEvidence(brand: "Nike", source: .ocr, confidence: 0.9),
            BrandEvidence(brand: "Uniqlo", source: .user, confidence: 1),
        ]
        #expect(BrandVerdict.resolve(mixed) == "Uniqlo")
    }
}

@Suite("Cuándo se pregunta fuera")
struct RemoteTriggerTests {

    /// El caso normal **no se pregunta**. Es lo que mantiene el coste en cero
    /// para la inmensa mayoría de las prendas.
    @Test("Una prenda bien resuelta no se consulta")
    func confidentGarmentStaysLocal() {
        #expect(
            GarmentPipeline.needsRemoteHelp(
                confidence: 0.85, subcategory: "camisa", brandEvidence: []
            ) == false
        )
    }

    @Test("Sin subcategoría se consulta")
    func missingSubcategoryTriggers() {
        #expect(
            GarmentPipeline.needsRemoteHelp(
                confidence: 0.85, subcategory: nil, brandEvidence: []
            )
        )
    }

    @Test("Con la categoría dudosa se consulta")
    func lowConfidenceTriggers() {
        #expect(
            GarmentPipeline.needsRemoteHelp(
                confidence: 0.3, subcategory: "camisa", brandEvidence: []
            )
        )
    }

    /// Ni escribir una marca a medio leer ni tirarla: preguntar.
    @Test("Una marca a medio leer se consulta")
    func doubtfulBrandTriggers() {
        let doubtful = [BrandEvidence(brand: "Levi's", source: .ocr, confidence: 0.62)]
        #expect(
            GarmentPipeline.needsRemoteHelp(
                confidence: 0.85, subcategory: "vaqueros", brandEvidence: doubtful
            )
        )
    }

    /// Y una leída limpia, no: ya está resuelta.
    @Test("Una marca leída limpia no se consulta")
    func cleanBrandStaysLocal() {
        let clean = [BrandEvidence(brand: "Zara", source: .ocr, confidence: 1)]
        #expect(
            GarmentPipeline.needsRemoteHelp(
                confidence: 0.85, subcategory: "camisa", brandEvidence: clean
            ) == false
        )
    }
}

@Suite("Duplicados")
struct DuplicateDetectorTests {

    /// Un vector reproducible y **de verdad independiente** de los demás.
    ///
    /// Con un seno desplazado por la semilla —que es lo primero que probé— dos
    /// "prendas distintas" salían al 0,94 de parecido: son la misma onda con
    /// otra fase, y eso correla muchísimo. Un generador congruencial da series
    /// sin relación entre sí, que es lo que hace falta para poder afirmar algo
    /// sobre el umbral.
    private static func values(seed: UInt64, count: Int = 512) -> [Float] {
        var state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return (0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max)
        }
    }

    private static func vector(seed: UInt64, count: Int = 512) -> Data {
        EmbeddingMath.encode(values(seed: seed, count: count)) ?? Data()
    }

    /// El mismo, con ruido encima: lo que sería otra foto de la misma prenda.
    private static func nudged(seed: UInt64, by amount: Float, count: Int = 512) -> Data {
        let base = values(seed: seed, count: count)
        let noise = values(seed: seed &+ 7919, count: count)
        let mixed = zip(base, noise).map { $0 + amount * $1 }
        return EmbeddingMath.encode(mixed) ?? Data()
    }

    @Test("La misma prenda desde otra foto se reconoce")
    func sameGarmentIsFound() throws {
        let known = [
            DuplicateDetector.Known(
                id: PersistentIdentifierBox("camiseta"),
                name: "Camiseta negra",
                embedding: Self.vector(seed: 7)
            )
        ]
        let match = try #require(
            DuplicateDetector.match(for: Self.nudged(seed: 7, by: 0.15), among: known)
        )
        #expect(match.known.name == "Camiseta negra")
        #expect(match.similarity >= DuplicateDetector.threshold)
    }

    /// El error que cuesta caro: fundir dos prendas distintas. Por eso el
    /// listón está en 0,93 y no en 0,85.
    @Test("Una prenda distinta no se confunde")
    func differentGarmentIsNotAMatch() {
        let known = [
            DuplicateDetector.Known(
                id: PersistentIdentifierBox("otra"),
                name: "Sudadera gris",
                embedding: Self.vector(seed: 7)
            )
        ]
        #expect(DuplicateDetector.match(for: Self.vector(seed: 99), among: known) == nil)
    }

    /// Los dos espacios de embedding no son comparables, y lo único que los
    /// distingue es el tamaño del vector.
    @Test("No se compara contra vectores de otro espacio")
    func differentSpacesAreNotCompared() {
        let known = [
            DuplicateDetector.Known(
                id: PersistentIdentifierBox("nativa"),
                name: "De feature print",
                embedding: Self.vector(seed: 7, count: 2048)
            )
        ]
        #expect(DuplicateDetector.match(for: Self.vector(seed: 7, count: 512), among: known) == nil)
    }

    @Test("Sin embedding no se descarta nada")
    func noEmbeddingMeansNoMatch() {
        let known = [
            DuplicateDetector.Known(
                id: PersistentIdentifierBox("x"), name: "X", embedding: Self.vector(seed: 1)
            )
        ]
        #expect(DuplicateDetector.match(for: nil, among: known) == nil)
    }

    /// Dos recortes casi iguales de la misma foto: se queda el primero.
    @Test("Los repetidos de la misma foto se marcan, menos el primero")
    func redundantWithinOneImport() {
        let embeddings: [Data?] = [
            Self.vector(seed: 3),
            Self.nudged(seed: 3, by: 0.12),
            Self.vector(seed: 50),
        ]
        #expect(DuplicateDetector.redundantIndices(in: embeddings) == [1])
    }
}

@Suite("Croma")
struct ChromaKeyTests {

    /// El caso que dejaba el filete rosa alrededor de cada prenda.
    ///
    /// La versión anterior recortaba rojo y azul a `max(verde, min(rojo,
    /// azul))`, que en un píxel bien teñido de magenta es el propio canal: no
    /// corregía nada justo donde más derrame había.
    @Test("Un píxel de magenta puro se apaga")
    func pureMagentaIsSuppressed() {
        let result = ChromaKey.suppressSpill(red: 255, green: 0, blue: 255)
        #expect(result.red <= ChromaKey.spillTolerance)
        #expect(result.blue <= ChromaKey.spillTolerance)
        #expect(result.green == 0)
    }

    @Test("Un derrame suave se desatura sin volverse gris del todo")
    func partialSpillIsReduced() {
        let result = ChromaKey.suppressSpill(red: 230, green: 140, blue: 215)
        #expect(result.red < 230)
        #expect(result.blue < 215)
        // Conserva el orden de los canales: sigue tirando a rojo, que es de lo
        // que era la tela.
        #expect(result.red > result.blue)
    }

    /// Y el contraejemplo, que es lo que hace que la corrección sea usable: hay
    /// colores reales con rojo y azul por encima del verde.
    @Test("Un burdeos no se toca")
    func realColoursSurvive() {
        let result = ChromaKey.suppressSpill(red: 115, green: 30, blue: 45)
        #expect(result.red == 115)
        #expect(result.green == 30)
        #expect(result.blue == 45)
    }

    @Test("Un rosa palo tampoco")
    func pinkSurvives() {
        let result = ChromaKey.suppressSpill(red: 240, green: 180, blue: 190)
        #expect(result.red == 240)
        #expect(result.blue == 190)
    }
}

@Suite("Croma de punta a punta")
struct ChromaCutoutTests {

    /// Una imagen como la que devuelve el modelo: prenda sólida, fondo magenta
    /// y **una banda de mezcla entre los dos**, que es lo que produce el JPEG.
    /// Esa banda es de donde salía el filete rosa.
    private func bleedingImage(side: Int = 128, bleed: Int = 4) -> CGImage {
        let garment = (red: 0.20, green: 0.34, blue: 0.62)   // azul marino
        let context = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let inset = side / 4

        for y in 0..<side {
            for x in 0..<side {
                // Distancia al borde del cuadrado de la prenda, en píxeles.
                let inside = min(
                    min(x - inset, side - inset - 1 - x),
                    min(y - inset, side - inset - 1 - y)
                )
                let mix: Double
                if inside >= bleed {
                    mix = 0                      // tela pura
                } else if inside < 0 {
                    mix = 1                      // fondo puro
                } else {
                    mix = 1 - Double(inside) / Double(bleed)
                }
                let red = garment.red * (1 - mix) + 1 * mix
                let green = garment.green * (1 - mix)
                let blue = garment.blue * (1 - mix) + 1 * mix
                context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return context.makeImage()!
    }

    /// Lee el resultado píxel a píxel.
    private func pixels(of image: CGImage) -> [(r: Int, g: Int, b: Int, a: Int)] {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var result: [(r: Int, g: Int, b: Int, a: Int)] = []
        result.reserveCapacity(width * height)
        for index in stride(from: 0, to: data.count, by: 4) {
            let red = Int(data[index])
            let green = Int(data[index + 1])
            let blue = Int(data[index + 2])
            let alpha = Int(data[index + 3])
            result.append((r: red, g: green, b: blue, a: alpha))
        }
        return result
    }

    @Test("El fondo queda transparente del todo, no casi")
    func backgroundIsFullyTransparent() throws {
        let cut = try #require(ChromaKey.cutout(bleedingImage()))
        let all = pixels(of: cut)
        let corners = [all[0], all[cut.width - 1], all[all.count - cut.width], all[all.count - 1]]
        for corner in corners {
            #expect(corner.a == 0)
            // Y sin color escondido debajo: un alfa a cero con RGB sin limpiar
            // reaparece en cuanto algo lo desmultiplica.
            #expect(corner.r == 0 && corner.g == 0 && corner.b == 0)
        }
    }

    /// La prueba que importa: **ni un solo píxel visible tira a magenta**.
    ///
    /// Se puede recortar bien y seguir dejando un anillo de píxeles medio
    /// transparentes con color de fondo dentro, que es exactamente lo que se
    /// veía como filete rosa sobre el lienzo.
    @Test("No sobrevive ningún píxel magenta")
    func noMagentaSurvives() throws {
        let cut = try #require(ChromaKey.cutout(bleedingImage()))
        let visible = pixels(of: cut).filter { $0.a > 0 }
        #expect(!visible.isEmpty)

        let magenta = visible.filter { pixel in
            // Premultiplicado: se compara sobre el color ya desmultiplicado,
            // que es el que se verá al componer sobre cualquier fondo.
            let scale = 255.0 / Double(pixel.a)
            let red = Double(pixel.r) * scale
            let green = Double(pixel.g) * scale
            let blue = Double(pixel.b) * scale
            return red > green + 60 && blue > green + 60
        }
        #expect(magenta.isEmpty, "quedan \(magenta.count) píxeles tirando a magenta")
    }

    @Test("La prenda sigue entera y con su color")
    func garmentSurvives() throws {
        let side = 128
        let cut = try #require(ChromaKey.cutout(bleedingImage(side: side)))
        let all = pixels(of: cut)
        let centre = all[(side / 2) * cut.width + cut.width / 2]
        #expect(centre.a == 255)
        #expect(centre.b > centre.r, "el azul marino sigue siendo azul")
    }
}

@Suite("Calidad del recorte")
struct CutoutQualityTests {

    /// Un recorte normal: la prenda de una pieza, con aire alrededor.
    private func wholeGarment(side: Int = 128) -> CGImage {
        let context = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(red: 0.2, green: 0.3, blue: 0.6, alpha: 1)
        let inset = side / 5
        context.fill(CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset))
        return context.makeImage()!
    }

    /// Y el fallo que de verdad ocurre: el segmentador parte la prenda en dos
    /// trozos separados —el pantalón cortado por el cinturón—.
    private func splitGarment(side: Int = 128) -> CGImage {
        let context = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(red: 0.2, green: 0.3, blue: 0.6, alpha: 1)
        let piece = side / 3
        context.fill(CGRect(x: piece, y: 4, width: piece, height: piece))
        context.fill(CGRect(x: piece, y: side - piece - 4, width: piece, height: piece))
        return context.makeImage()!
    }

    @Test("Un recorte entero se da por bueno")
    func wholeGarmentPasses() {
        let report = CutoutQuality.assess(wholeGarment())
        #expect(report.isGoodEnough, "\(report.summary)")
    }

    /// Este es el que justifica el gasto: partido en dos, se reconstruye.
    @Test("Un recorte partido en dos no vale")
    func splitGarmentFails() {
        let report = CutoutQuality.assess(splitGarment())
        #expect(!report.isGoodEnough, "\(report.summary)")
    }

    @Test("Un recorte vacío no vale")
    func emptyFails() {
        let side = 32
        let context = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        let report = CutoutQuality.assess(context.makeImage()!)
        #expect(report.score == 0)
    }
}
