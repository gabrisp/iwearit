import Foundation

/// Una entrada del manifiesto: un modelo disponible para descargar.
public struct ModelManifestEntry: Sendable, Hashable, Codable {
    public let modelID: String
    public let task: ModelTask
    public let version: Int
    /// Primer (o único) trozo. Para modelos de un solo fichero, el fichero.
    public let fileID: String
    /// sha256 del **paquete reensamblado**, no de cada trozo.
    public let sha256: String
    public let sizeBytes: Int
    public let minIOSVersion: String
    public let inputWidth: Int
    public let inputHeight: Int
    public let labels: [String]
    /// Trozos en orden. Vacío si el modelo cabe en un solo fichero.
    public let partFileIDs: [String]

    public init(
        modelID: String, task: ModelTask, version: Int, fileID: String,
        sha256: String, sizeBytes: Int, minIOSVersion: String,
        inputWidth: Int, inputHeight: Int, labels: [String], partFileIDs: [String]
    ) {
        self.modelID = modelID
        self.task = task
        self.version = version
        self.fileID = fileID
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
        self.minIOSVersion = minIOSVersion
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.labels = labels
        self.partFileIDs = partFileIDs
    }

    /// Todos los trozos a descargar, en orden.
    public var orderedFileIDs: [String] {
        partFileIDs.isEmpty ? [fileID] : partFileIDs
    }
}

public enum ModelTask: String, Sendable, Codable, CaseIterable {
    case segmentation
    case embedding
    case promptBank
}

/// De dónde salen los modelos.
///
/// Detrás de un protocolo para poder cambiar de backend sin tocar el resto de
/// la app, y —más útil a diario— para poder desarrollar contra ficheros locales
/// o sin modelos en absoluto.
public protocol ModelRepository: Sendable {
    /// Qué hay disponible ahora mismo.
    func manifest() async throws -> [ModelManifestEntry]

    /// Descarga un trozo a disco y devuelve dónde quedó.
    ///
    /// Se devuelve una URL y no `Data` a propósito: un modelo de 28 MB en
    /// memoria durante el escaneo masivo es justo lo que no hace falta.
    func downloadPart(
        fileID: String,
        progress: @Sendable (Double) -> Void
    ) async throws -> URL
}

public enum ModelRepositoryError: Error, Sendable, LocalizedError {
    case notConfigured
    case network(String)
    case checksumMismatch(expected: String, actual: String)
    case compilationFailed(String)
    case unsupportedDevice(minimumIOS: String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "wkcore.modelrepository.noModelSourceIsConfigured", defaultValue: "No model source is configured.", bundle: .module)
        case let .network(detail):
            String(localized: "wkcore.modelrepository.couldnTReachTheModel", defaultValue: "Couldn't reach the model server: \(String(describing: detail))", bundle: .module)
        case .checksumMismatch:
            String(localized: "wkcore.modelrepository.theDownloadedModelDoesnT", defaultValue: "The downloaded model doesn't match the expected one.", bundle: .module)
        case let .compilationFailed(detail):
            String(localized: "wkcore.modelrepository.couldnTPrepareTheModel", defaultValue: "Couldn't prepare the model for this device: \(String(describing: detail))", bundle: .module)
        case let .unsupportedDevice(minimum):
            String(localized: "wkcore.modelrepository.thisModelNeedsIosOr", defaultValue: "This model needs iOS \(String(describing: minimum)) or later.", bundle: .module)
        }
    }
}

/// No hay modelos. Fuerza el modo degradado.
///
/// No es un apaño para tests: es la ruta real cuando el usuario declina la
/// descarga o no hay red, y tiene que funcionar.
public struct UnavailableModelRepository: ModelRepository {
    public init() {}
    public func manifest() async throws -> [ModelManifestEntry] { [] }
    public func downloadPart(fileID: String, progress: @Sendable (Double) -> Void) async throws -> URL {
        throw ModelRepositoryError.notConfigured
    }
}
