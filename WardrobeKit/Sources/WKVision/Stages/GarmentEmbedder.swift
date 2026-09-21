import CoreGraphics
import CoreML
import Foundation
import WKCore

/// Convierte el recorte de una prenda en un vector de 512 dimensiones.
///
/// Ese vector hace tres trabajos a la vez, y por eso compensa el modelo:
///
/// 1. **Subcategoría y capa.** SegFormer dice "torso" pero no distingue una
///    chaqueta de una camiseta. El coseno contra el prompt bank sí.
/// 2. **Atributos** — material, patrón, estilo, temporada — sin entrenar nada.
/// 3. **Deduplicación y baldas propias.** La misma camiseta en treinta fotos
///    cae junta, y una balda "Gorras" aprende de los ejemplos que le des.
public actor GarmentEmbedder {
    private let model: MLModel
    private let inputSize: Int

    /// - Parameter computeUnits: sin ANE, por la misma razón que en
    ///   `ClothesSegmenter` — preparar el plan de la ANE bloquea a Vision
    ///   durante toda la carga. Aquí además pesa poco: es un modelo pequeño y
    ///   se le pide un vector por prenda, no por fotograma.
    public init(
        compiledModelAt url: URL,
        inputSize: Int = 224,
        computeUnits: MLComputeUnits = .cpuAndGPU
    ) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        self.model = try MLModel(contentsOf: url, configuration: configuration)
        self.inputSize = inputSize
    }

    /// El embedding, ya normalizado (la normalización va dentro del grafo).
    public func embedding(for image: CGImage) throws -> [Float] {
        let buffer = try Self.pixelBuffer(from: image, side: inputSize)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: buffer)
        ])
        let output = try model.prediction(from: input)

        guard let array = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw PipelineError.maskGenerationFailed
        }
        // Igual que en el segmentador: con precisión FLOAT16 el tensor llega
        // en Float16, y leerlo como Float revienta el proceso.
        switch array.dataType {
        case .float16:
            return array.withUnsafeBufferPointer(ofType: Float16.self) { $0.map(Float.init) }
        case .float32:
            return array.withUnsafeBufferPointer(ofType: Float.self) { Array($0) }
        case .double:
            return array.withUnsafeBufferPointer(ofType: Double.self) { $0.map(Float.init) }
        default:
            return (0..<array.count).map { Float(truncating: array[$0]) }
        }
    }

    /// El recorte llega con fondo transparente; CLIP espera una foto de
    /// producto. Se compone sobre blanco, que es exactamente lo que dice la
    /// plantilla con la que se generaron los prompts.
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

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))

        // Encajado conservando proporción: deformar una prenda cambia su forma,
        // y la forma es justo lo que distingue unos vaqueros de una falda.
        let scale = min(Double(side) / Double(image.width), Double(side) / Double(image.height))
        let width = Double(image.width) * scale
        let height = Double(image.height) * scale
        context.draw(image, in: CGRect(
            x: (Double(side) - width) / 2,
            y: (Double(side) - height) / 2,
            width: width, height: height
        ))
        return buffer
    }
}
