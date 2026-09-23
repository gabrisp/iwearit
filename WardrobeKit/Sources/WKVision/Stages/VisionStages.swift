import CoreGraphics
import Foundation
import os
import Vision
import WKCore

/// Envoltorios sobre la API Swift de Vision (iOS 18).
///
/// Todo lo de aquí usa **solo APIs nativas**: es el modo degradado, el que
/// corre sin red, sin modelos descargados y en cualquier iPhone con iOS 18.
public enum VisionStages {

    /// Si las peticiones neuronales de Vision responden en este aparato **ahora
    /// mismo**.
    ///
    /// ## Por qué hace falta recordarlo
    ///
    /// Pose, máscara de sujeto, saliencia y huella no corren en la CPU: van a
    /// la ANE. Y cuando la ANE está ocupada —cargando un modelo grande de Core
    /// ML, con una sesión de cámara todavía viva, o en un simulador que no la
    /// tiene— estas peticiones **no fallan: no vuelven**. Cada una se come su
    /// tope entero.
    ///
    /// Eso es lo que convertía un análisis en un cuelgue de veinte segundos:
    /// pose 8 s + sujeto 10 s + saliencia 6 s, uno detrás de otro, para acabar
    /// diciendo "está tardando demasiado" sin haber llegado a probar el
    /// segmentador — que es de Core ML, corre donde puede y **sí** habría
    /// funcionado.
    ///
    /// Así que la primera que se cae marca el resto: a partir de ahí se falla
    /// al instante y se va directo a lo que sí funciona. Se vuelve a probar
    /// pasado un rato, porque "la ANE está ocupada" es un estado temporal y no
    /// una propiedad del aparato.
    private enum Neural {
        private static let state = OSAllocatedUnfairLock(initialState: Date.distantPast)
        /// Cuánto se da por no disponible antes de volver a intentarlo.
        private static let cooldown: TimeInterval = 60

        static var isAvailable: Bool {
            state.withLock { Date().timeIntervalSince($0) > cooldown }
        }

        static func markUnavailable() {
            state.withLock { $0 = Date() }
        }

        static func markAvailable() {
            state.withLock { $0 = .distantPast }
        }
    }

    /// Vuelve a dar por buena la ANE. Se llama cuando algo que la tenía ocupada
    /// ha terminado — por ejemplo, al acabar de cargar un modelo de Core ML.
    public static func resetNeuralAvailability() {
        Neural.markAvailable()
        DiagnosticsLog.record("VISION", "se vuelve a contar con la ANE")
    }

    /// Ejecuta algo con un tope de tiempo.
    ///
    /// Vision no ofrece cancelación ni plazo propio, y una petición atascada no
    /// falla: simplemente no vuelve. Aquí al menos el error dice qué ha pasado.
    static func withTimeout<T: Sendable>(
        _ name: String = "vision",
        seconds: Double,
        neural: Bool = true,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        // Ni se intenta si la anterior se quedó colgada. Es la diferencia entre
        // fallar en un milisegundo y fallar en ocho segundos, por petición.
        if neural, !Neural.isAvailable {
            DiagnosticsLog.record("VISION", "\(name): se salta, la ANE no responde", isProblem: true)
            throw PipelineError.visionUnavailable
        }

        let start = ContinuousClock.now
        DiagnosticsLog.record("VISION", "\(name): empieza")
        do {
            let result = try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask { try await work() }
                group.addTask {
                    try await Task.sleep(for: .seconds(seconds))
                    throw PipelineError.timedOut
                }
                guard let first = try await group.next() else { throw PipelineError.timedOut }
                group.cancelAll()
                return first
            }
            DiagnosticsLog.record("VISION", "\(name): ok en \(start.duration(to: .now))")
            return result
        } catch {
            // Nombrar la etapa que falla es **el** dato: sin esto, un cuelgue
            // en cualquiera de las cinco peticiones de Vision se ve igual desde
            // fuera, y no hay forma de saber cuál arreglar.
            // **Colgada no es lo mismo que cancelada.**
            //
            // Si el error llega en veinte milisegundos, la ANE no tiene la
            // culpa de nada: lo que ha pasado es que alguien de fuera canceló
            // la tarea —la hoja se cerró, el análisis se descartó—. Darla por
            // muerta ahí apaga Vision durante un minuto por un motivo que no
            // era, y las fotos siguientes fallan sin razón.
            //
            // Colgada es cuando se ha consumido el tope entero.
            let elapsed = start.duration(to: .now)
            let exhaustedTimeout = elapsed > .seconds(seconds * 0.8)

            if neural, exhaustedTimeout {
                Neural.markUnavailable()
                DiagnosticsLog.record(
                    "VISION",
                    "\(name): no vuelve en \(Int(seconds))s — la ANE está ocupada. "
                        + "Se salta el resto de Vision durante un minuto.",
                    isProblem: true
                )
            } else if error is CancellationError {
                DiagnosticsLog.record("VISION", "\(name): cancelada a los \(elapsed)")
            } else {
                DiagnosticsLog.record(
                    "VISION", "\(name): falla — \(error.localizedDescription)", isProblem: true
                )
            }
            throw error
        }
    }


    /// Instancias de sujeto en primer plano, con su máscara.
    ///
    /// Es lo que hace el "levantar sujeto" de Fotos. No sabe qué es una prenda:
    /// separa objeto de fondo. La categoría la pone después el esqueleto.
    public static func foregroundInstances(in image: CGImage) async throws -> InstanceMaskObservation? {
        let request = GenerateForegroundInstanceMaskRequest()
        return try await withTimeout("sujeto", seconds: 10) {
            try await request.perform(on: image)
        }
    }

    /// Articulaciones de la persona más prominente.
    public static func bodyLandmarks(in image: CGImage) async throws -> BodyLandmarks? {
        let request = DetectHumanBodyPoseRequest()
        // Con tope. Si el sistema tiene la ANE ocupada —por ejemplo con una
        // sesión de captura todavía viva— esta petición **no vuelve**, y sin
        // esto el análisis se queda pensando para siempre sin decir nada.
        let observations = try await withTimeout("pose", seconds: 8) {
            try await request.perform(on: image)
        }
        guard let pose = observations.first else { return nil }
        return landmarks(from: pose)
    }

    /// Huella visual para deduplicar.
    ///
    /// No es comparable con los embeddings de MobileCLIP: viven en espacios
    /// vectoriales distintos, así que un centroide aprendido con uno no sirve
    /// para el otro.
    public static func featurePrint(of image: CGImage) async throws -> Data? {
        let request = GenerateImageFeaturePrintRequest()
        let observation = try await withTimeout("huella", seconds: 8) {
            try await request.perform(on: image)
        }
        return observation.data
    }

    /// Descarta capturas de pantalla, recibos y documentos.
    ///
    /// Sale gratis y en el escaneo masivo (F8) mata una fracción notable de la
    /// galería antes de gastar un milisegundo en segmentar.
    public static func isUtilityImage(_ image: CGImage) async throws -> Bool {
        let request = CalculateImageAestheticsScoresRequest()
        let observation = try await withTimeout("estética", seconds: 6, neural: false) {
            try await request.perform(on: image)
        }
        return observation.isUtility
    }

    /// Dónde está lo importante de la foto.
    ///
    /// El último recurso cuando nada se puede recortar: la saliencia **siempre
    /// devuelve algo**, porque no busca objetos sino a dónde mira el ojo. El
    /// recorte es peor —lleva fondo— pero es una prenda que el usuario puede
    /// quedarse y arreglar, en vez de un error.
    public static func salientRegion(in image: CGImage) async throws -> CGRect? {
        let request = GenerateAttentionBasedSaliencyImageRequest()
        let observation = try await withTimeout("saliencia", seconds: 6) {
            try await request.perform(on: image)
        }
        guard let salient = observation.salientObjects.first else { return nil }
        return salient.boundingBox.toImageCoordinates(
            CGSize(width: image.width, height: image.height),
            origin: .upperLeft
        )
    }

    /// ¿Hay alguien en la foto?
    ///
    /// Es la puerta barata del escaneo masivo: se ejecuta sobre una miniatura
    /// de 256 px y descarta la mayor parte de una galería típica antes de gastar
    /// un milisegundo en segmentar.
    public static func containsPerson(_ image: CGImage) async throws -> Bool {
        let request = DetectHumanRectanglesRequest()
        return try await withTimeout("persona", seconds: 6) {
            try await !request.perform(on: image).isEmpty
        }
    }

    // MARK: - Articulaciones

    private static func landmarks(from pose: HumanBodyPoseObservation) -> BodyLandmarks? {
        // **Todas de una vez, y no una por una.**
        //
        // `joint(for:)` no existe en iOS 18: es de iOS 26. Compilaba —el SDK
        // es el 26— y el enlazador no dice nada, así que el fallo salía en el
        // sitio más caro posible: al **arrancar** en un iPhone con iOS 18, con
        // dyld matando el proceso por símbolo ausente antes de pintar nada.
        // Un diccionario con todas las articulaciones es la forma que sí está
        // en las dos versiones, y de paso se lee una vez en vez de seis.
        let all = pose.allJoints()

        func averageY(_ names: [HumanBodyPoseObservation.JointName]) -> (Double, Double)? {
            let joints = names.compactMap { all[$0] }.filter { $0.confidence > 0.2 }
            guard !joints.isEmpty else { return nil }
            let y = joints.reduce(0.0) { $0 + $1.location.y } / Double(joints.count)
            let confidence = joints.reduce(0.0) { $0 + Double($1.confidence) } / Double(joints.count)
            return (y, confidence)
        }

        guard
            let shoulders = averageY([.leftShoulder, .rightShoulder]),
            let hips = averageY([.leftHip, .rightHip])
        else { return nil }

        let knees = averageY([.leftKnee, .rightKnee])
        let ankles = averageY([.leftAnkle, .rightAnkle])

        return BodyLandmarks(
            shoulderY: shoulders.0,
            hipY: hips.0,
            kneeY: knees?.0,
            ankleY: ankles?.0,
            confidence: (shoulders.1 + hips.1) / 2
        )
    }
}
