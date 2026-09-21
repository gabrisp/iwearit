#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WKCore
import WKVision

/// Arnés de validación del pipeline.
///
/// Lee las fotos de `Documents/ProbeInput/`, las pasa por el pipeline y escribe
/// cada recorte en `Documents/ProbeOutput/` junto con un resumen en el log.
///
/// Existe porque el pipeline no se puede validar con tests: depende de modelos
/// de Vision entrenados con fotos reales, y ninguna imagen sintética los activa
/// de forma representativa. Esto permite pasarle fotos de verdad y **mirar** lo
/// que sale, que es la única verificación honesta.
///
/// Se reutilizará en F7 para comparar la ruta degradada contra SegFormer sobre
/// el mismo conjunto de fotos.
enum PipelineProbe {

    static func run() async {
        let documents = URL.documentsDirectory
        let input = documents.appending(path: "ProbeInput", directoryHint: .isDirectory)
        let output = documents.appending(path: "ProbeOutput", directoryHint: .isDirectory)

        try? FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let files = (try? FileManager.default.contentsOfDirectory(
            at: input, includingPropertiesForKeys: nil
        )) ?? []

        NSLog("PROBE-PIPELINE: %d fotos en %@", files.count, input.path())
        guard !files.isEmpty else {
            NSLog("PROBE-PIPELINE: sin fotos. Copia imágenes a ProbeInput/ y relanza.")
            return
        }

        let pipeline = GarmentPipeline()

        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let image = loadImage(at: file) else {
                NSLog("PROBE-PIPELINE: %@ no se pudo decodificar", file.lastPathComponent)
                continue
            }

            // Cada etapa por separado y con su error a la vista: `try?` aquí
            // escondía que Vision estaba fallando y lo hacía parecer "no
            // detectado", que es un diagnóstico completamente distinto.
            await report("aesthetics") { _ = try await VisionStages.isUtilityImage(image) }
            await report("bodyPose") { _ = try await VisionStages.bodyLandmarks(in: image) }
            await report("foregroundInstances") { _ = try await VisionStages.foregroundInstances(in: image) }
            await report("featurePrint") { _ = try await VisionStages.featurePrint(of: image) }

            let landmarks = try? await VisionStages.bodyLandmarks(in: image)
            let isUtility = (try? await VisionStages.isUtilityImage(image)) ?? false

            NSLog(
                "PROBE-PIPELINE: %@ (%dx%d) utility=%@ pose=%@",
                file.lastPathComponent, image.width, image.height,
                isUtility ? "sí" : "no",
                landmarks.map { String(format: "hombros %.2f caderas %.2f rodillas %@ tobillos %@ conf %.2f",
                                       $0.shoulderY, $0.hipY,
                                       $0.kneeY.map { String(format: "%.2f", $0) } ?? "—",
                                       $0.ankleY.map { String(format: "%.2f", $0) } ?? "—",
                                       $0.confidence) } ?? "no detectada"
            )

            let clock = ContinuousClock.now
            do {
                let garments = try await pipeline.extractGarments(from: image)
                let elapsed = clock.duration(to: .now)
                NSLog("PROBE-PIPELINE:   → %d prendas en %@", garments.count, "\(elapsed)")

                let stem = file.deletingPathExtension().lastPathComponent
                for (index, garment) in garments.enumerated() {
                    NSLog(
                        "PROBE-PIPELINE:   [%d] %@ conf %.2f colores %@",
                        index, garment.kind.rawValue, garment.confidence,
                        garment.colors.map { String(format: "%@ %.0f%%", $0.nameKey, $0.weight * 100) }
                            .joined(separator: ", ")
                    )
                    write(
                        garment.normalized.cgImage,
                        to: output.appending(path: "\(stem)-\(index)-\(garment.kind.rawValue).png")
                    )
                }
            } catch {
                NSLog("PROBE-PIPELINE:   → error: %@", String(describing: error))
            }
        }
        NSLog("PROBE-PIPELINE: recortes en %@", output.path())
    }

    /// Ejecuta una etapa y dice si funciona o por qué no.
    private static func report(_ name: String, _ work: () async throws -> Void) async {
        do {
            try await work()
            NSLog("PROBE-STAGE: %@ OK", name)
        } catch {
            NSLog("PROBE-STAGE: %@ FALLA — %@", name, String(describing: error))
        }
    }

    private static func loadImage(at url: URL) -> CGImage? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return image
    }

    /// PNG y no HEIC: estos recortes son para mirarlos, y un PNG sin pérdida
    /// no introduce artefactos que se puedan confundir con fallos del recorte.
    private static func write(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
#endif
