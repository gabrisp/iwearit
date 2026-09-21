import CoreGraphics
import CoreML
import Foundation
import Vision
import WKCore

/// Segmentación de prendas por píxel con SegFormer.
///
/// ## Qué arregla
///
/// El modo degradado se apoya en `GenerateForegroundInstanceMaskRequest`, que
/// es "levantar sujeto": separa objeto de fondo y devuelve **la persona entera
/// como un solo sujeto**. No sabe qué es una camiseta, así que produce una
/// "prenda" que es una persona.
///
/// Esto sí lo sabe: 18 clases del dataset ATR, con clases **explícitas** de
/// piel, pelo y cara. Descartarlas por construcción es lo que evita que se
/// cuelen caras y brazos en el armario.
///
/// ## Lo que no distingue
///
/// Chaqueta de camiseta: ambas son `upper-clothes`. Esa decisión la toma
/// MobileCLIP sobre el recorte ya hecho.
public actor ClothesSegmenter {

    /// Las 18 clases de ATR, en el orden que produce el modelo.
    public enum Label: Int, CaseIterable, Sendable {
        case background = 0, hat, hair, sunglasses, upperClothes, skirt
        case pants, dress, belt, leftShoe, rightShoe, face
        case leftLeg, rightLeg, leftArm, rightArm, bag, scarf

        /// A qué tipo de prenda corresponde. `nil` = no es ropa.
        ///
        /// Piel, pelo y cara devuelven `nil` **siempre**. Es la diferencia entre
        /// un armario con ropa y uno con recortes de la cara del usuario.
        public var kind: GarmentKind? {
            switch self {
            case .background, .hair, .face, .leftLeg, .rightLeg, .leftArm, .rightArm:
                nil
            case .hat, .sunglasses:
                .head
            // Capa interior o exterior: lo decide MobileCLIP sobre el recorte.
            case .upperClothes:
                .upperBody
            case .skirt, .pants:
                .lowerBody
            case .dress:
                .wholeBody
            case .leftShoe, .rightShoe:
                .feet
            case .bag:
                .bag
            case .belt, .scarf:
                .other
            }
        }

        /// Clases que se fusionan en una sola prenda.
        ///
        /// Un par de zapatos es **una** prenda. Sin esto, cada par generaría dos
        /// entradas y la balda de calzado quedaría del doble de larga y llena de
        /// duplicados que no lo son.
        public var mergeGroup: Int {
            Self.mergeGroup(forRaw: rawValue)
        }

        /// La misma regla sin construir el enum.
        ///
        /// El bucle del recorte pregunta por el grupo de cada píxel, y con
        /// millones de píxeles por foto construir un `Label` para tirarlo
        /// inmediatamente cuesta más que la comparación que se quería hacer.
        static func mergeGroup(forRaw raw: Int) -> Int {
            raw == Label.rightShoe.rawValue ? Label.leftShoe.rawValue : raw
        }
    }

    private let model: MLModel
    private let inputSize: Int

    /// - Parameter computeUnits: por defecto **sin ANE**. Ver la nota de abajo
    ///   antes de cambiarlo.
    ///
    /// ## Por qué no se usa la ANE
    ///
    /// Con `.all`, `MLModel(contentsOf:)` no se limita a abrir el fichero:
    /// compila el plan de la ANE para toda la red. Medido en este mismo modelo:
    ///
    /// | | `.all` | `.cpuAndGPU` |
    /// |---|---|---|
    /// | SegFormer-B2 | **13,9 s** | 0,72 s |
    /// | SegFormer-B3 | **18,8 s** | 1,14 s |
    ///
    /// Veinte segundos de carga ya serían malos por sí solos. Lo grave es lo
    /// otro: mientras dura, **la ANE está ocupada**, y las peticiones
    /// neuronales de Vision —pose, máscara de sujeto, saliencia— no fallan,
    /// simplemente no vuelven. Importar una foto en esa ventana daba tres topes
    /// encadenados y un "está tardando demasiado" que no se parecía en nada a
    /// la causa. Es exactamente el fallo que teníamos.
    ///
    /// En GPU la inferencia de este modelo está en el mismo orden de magnitud
    /// que en la ANE para **una** foto, que es el caso de "añadir una prenda".
    /// Para el escaneo masivo —miles de fotos seguidas— la ANE sí compensa, y
    /// ahí el sitio de pagar esos veinte segundos es detrás de la pantalla de
    /// progreso del escaneo, donde esperar ya es lo que toca.
    public init(
        compiledModelAt url: URL,
        inputSize: Int = 512,
        computeUnits: MLComputeUnits = .cpuAndGPU
    ) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        self.model = try MLModel(contentsOf: url, configuration: configuration)
        self.inputSize = inputSize
    }

    /// Mapa de clase por píxel, a `inputSize × inputSize`.
    ///
    /// Devuelve índices y no máscaras separadas: 18 máscaras en float serían
    /// 18 MB por foto, y durante el escaneo masivo eso es la diferencia entre
    /// funcionar y que el sistema mate el proceso.
    public func classMap(for image: CGImage) throws -> ClassMap {
        let resized = try Self.resize(image, to: inputSize)
        let buffer = try Self.pixelBuffer(from: resized, side: inputSize)

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: buffer)
        ])
        // La variante síncrona, no la `async`: `MLModel` no es `Sendable`, y
        // el `await` lo haría cruzar el aislamiento del actor. Aquí no hace
        // falta — el actor ya serializa el acceso y no corre en el hilo
        // principal, así que bloquear su hilo es exactamente lo correcto.
        let output = try model.prediction(from: input)

        guard let array = output.featureValue(for: "classMap")?.multiArrayValue else {
            throw PipelineError.maskGenerationFailed
        }
        return ClassMap(array: array, side: inputSize)
    }

    // MARK: - Preparación de la entrada

    private static func resize(_ image: CGImage, to side: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw PipelineError.renderFailed }

        context.interpolationQuality = .high
        // Deformar a cuadrado en vez de recortar: recortar perdería los pies o
        // la cabeza en una foto vertical, que es justo donde están las prendas
        // que más cuesta detectar.
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let result = context.makeImage() else { throw PipelineError.renderFailed }
        return result
    }

    private static func pixelBuffer(from image: CGImage, side: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        guard
            CVPixelBufferCreate(
                kCFAllocatorDefault, side, side, kCVPixelFormatType_32BGRA,
                attributes as CFDictionary, &buffer
            ) == kCVReturnSuccess,
            let buffer
        else { throw PipelineError.renderFailed }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: side, height: side,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw PipelineError.renderFailed }

        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return buffer
    }
}

/// Mapa de clase por píxel.
public struct ClassMap: Sendable {
    /// Ancho y alto **del tensor de salida**, que no tienen por qué ser los de
    /// la entrada.
    ///
    /// SegFormer predice a **1/4 de resolución**: con una entrada de 512 la
    /// salida es 128×128. Dar por hecho que el mapa medía lo mismo que la
    /// entrada era el fallo que destrozaba los recortes — se indexaba
    /// `y * 512 + x` sobre un búfer de 16.384 valores, así que solo las 32
    /// primeras filas tenían clases y el resto quedaba a cero. El resultado
    /// eran cajas altísimas y estrechas: tiras de foto en vez de prendas.
    public let width: Int
    public let height: Int
    private let values: [UInt8]

    init(array: MLMultiArray, side: Int) {
        // De la forma real, no del tamaño de entrada. Las dos últimas
        // dimensiones son siempre alto y ancho, venga como [1,H,W],
        // [1,1,H,W] o [H,W].
        let shape = array.shape.map(\.intValue)
        let height = shape.count >= 2 ? shape[shape.count - 2] : side
        let width = shape.count >= 1 ? shape[shape.count - 1] : side
        self.width = max(1, width)
        self.height = max(1, height)

        var values = [UInt8](repeating: 0, count: self.width * self.height)
        let count = min(values.count, array.count)

        // El tipo del tensor **se consulta**, no se supone.
        //
        // Con `compute_precision = FLOAT16` el modelo devuelve Float16, no
        // Float32, y leerlo con `withUnsafeBufferPointer(ofType: Float.self)`
        // no da un valor raro: **revienta el proceso**. Es exactamente lo que
        // pasaba al escanear.
        //
        // Se compacta a bytes al leerlo: 18 clases caben de sobra en uno, y el
        // mapa ocupa una cuarta parte.
        switch array.dataType {
        case .float16:
            array.withUnsafeBufferPointer(ofType: Float16.self) { pointer in
                for index in 0..<min(count, pointer.count) {
                    values[index] = Self.clamp(Double(pointer[index]))
                }
            }
        case .float32:
            array.withUnsafeBufferPointer(ofType: Float.self) { pointer in
                for index in 0..<min(count, pointer.count) {
                    values[index] = Self.clamp(Double(pointer[index]))
                }
            }
        case .double:
            array.withUnsafeBufferPointer(ofType: Double.self) { pointer in
                for index in 0..<min(count, pointer.count) {
                    values[index] = Self.clamp(pointer[index])
                }
            }
        case .int32:
            array.withUnsafeBufferPointer(ofType: Int32.self) { pointer in
                for index in 0..<min(count, pointer.count) {
                    values[index] = Self.clamp(Double(pointer[index]))
                }
            }
        @unknown default:
            // Subíndice genérico: más lento, pero vale para cualquier tipo
            // futuro. Mejor lento que caído.
            for index in 0..<count {
                values[index] = Self.clamp(array[index].doubleValue)
            }
        }
        self.values = values
    }

    private static func clamp(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, value.rounded())))
    }

    public subscript(x: Int, y: Int) -> ClothesSegmenter.Label? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        return ClothesSegmenter.Label(rawValue: Int(values[y * width + x]))
    }

    /// Grupo de fusión en crudo, sin construir un `Label`.
    ///
    /// El camino rápido para el bucle del recorte: `subscript` devuelve un
    /// `Optional<Label>` y eso es una construcción de enum por píxel, con
    /// millones de píxeles por foto.
    public func group(x: Int, y: Int) -> Int {
        guard x >= 0, x < width, y >= 0, y < height else { return -1 }
        return ClothesSegmenter.Label.mergeGroup(forRaw: Int(values[y * width + x]))
    }

    /// Cuántos píxeles tiene el mapa.
    public var count: Int { width * height }

    /// El valor crudo por índice lineal, sin construir el enum.
    ///
    /// Lo usa el separador de instancias, que recorre el mapa entero una vez
    /// por grupo presente. Con `subscript` eso serían millones de
    /// construcciones de `Optional<Label>` para tirarlas acto seguido.
    @inline(__always)
    public func rawValue(at index: Int) -> Int {
        guard index >= 0, index < values.count else { return 0 }
        return Int(values[index])
    }

    /// Cuántos píxeles hay de cada clase. Base para descartar manchas.
    public func histogram() -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for value in values {
            counts[Int(value), default: 0] += 1
        }
        return counts
    }
}
