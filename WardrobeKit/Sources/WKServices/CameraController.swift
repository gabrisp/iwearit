import AVFoundation
import CoreGraphics
import Foundation
import WKCore
import Observation

/// Cámara propia sobre AVFoundation.
///
/// No se usa `UIImagePickerController`: la captura de prendas quiere su propia
/// pantalla —guías de encuadre, disparo sin salir del flujo, control de la
/// resolución que entra al pipeline— y el picker del sistema no deja ninguna
/// de esas cosas.
@MainActor
@Observable
public final class CameraController {

    public enum State: Equatable {
        case idle
        case preparing
        case running
        case denied
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var isFlashOn = false
    public private(set) var isUsingFrontCamera = false

    /// La sesión la consume la capa de preview. Se expone tal cual porque
    /// `AVCaptureVideoPreviewLayer` la necesita por referencia.
    public let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private var captureDelegate: PhotoCaptureDelegate?

    public init() {}

    // MARK: - Ciclo de vida

    public func start() async {
        guard state == .idle || state == .denied else { return }
        state = .preparing

        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else {
            state = .denied
            return
        }

        do {
            try configure(front: isUsingFrontCamera)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        // `startRunning` bloquea: fuera del hilo principal o se come frames de
        // la animación de presentación.
        let box = SessionBox(session)
        await Task.detached(priority: .userInitiated) { box.session.startRunning() }.value
        state = .running
    }

    public func stop() {
        let box = SessionBox(session)
        Task.detached(priority: .utility) { box.session.stopRunning() }
        state = .idle
    }

    // MARK: - Controles

    public func toggleFlash() { isFlashOn.toggle() }

    public func switchCamera() {
        isUsingFrontCamera.toggle()
        try? configure(front: isUsingFrontCamera)
    }

    /// Dispara y devuelve la foto ya en `CGImage`.
    public func capture() async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            if photoOutput.supportedFlashModes.contains(.on) {
                settings.flashMode = isFlashOn ? .on : .off
            }
            // El delegate se retiene aquí: AVFoundation solo lo guarda débil y,
            // sin esta referencia, se libera antes de que llegue la foto.
            let delegate = PhotoCaptureDelegate { result in
                continuation.resume(with: result)
            }
            captureDelegate = delegate
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    // MARK: - Configuración

    private func configure(front: Bool) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        for input in session.inputs { session.removeInput(input) }

        guard
            let device = AVCaptureDevice.default(
                front ? .builtInWideAngleCamera : .builtInDualWideCamera,
                for: .video,
                position: front ? .front : .back
            ) ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            throw CameraError.noCamera
        }
        session.addInput(input)

        if session.outputs.isEmpty, session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
    }

    public enum CameraError: Error, LocalizedError {
        case noCamera
        case captureFailed

        public var errorDescription: String? {
            switch self {
            case .noCamera: "No se encontró ninguna cámara disponible."
            case .captureFailed: "No se pudo procesar la foto."
            }
        }
    }
}

/// Caja para arrancar y parar la sesión fuera del hilo principal.
///
/// Apple documenta que `startRunning` y `stopRunning` son seguros desde
/// cualquier hilo —y **recomienda** no llamarlos en el principal porque
/// bloquean—, pero `AVCaptureSession` no está marcada `Sendable`. Se envuelve
/// aquí con la justificación a la vista en lugar de esparcir
/// `nonisolated(unsafe)` por la clase.
private struct SessionBox: @unchecked Sendable {
    let session: AVCaptureSession
    init(_ session: AVCaptureSession) { self.session = session }
}

/// Puente entre el delegate de AVFoundation y `async/await`.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: (Result<CGImage, Error>) -> Void

    init(completion: @escaping (Result<CGImage, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(.failure(error))
            return
        }
        // Desde los datos y no desde `cgImageRepresentation()`: esa devuelve
        // los píxeles del sensor, con la orientación aparte en los metadatos,
        // y a Vision le llegaría la foto tumbada.
        guard
            let data = photo.fileDataRepresentation(),
            let image = UprightImage.cgImage(from: data)
        else {
            completion(.failure(CameraController.CameraError.captureFailed))
            return
        }
        completion(.success(image))
    }
}
