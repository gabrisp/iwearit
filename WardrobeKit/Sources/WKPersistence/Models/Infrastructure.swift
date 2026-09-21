import Foundation
import SwiftData

/// Una cara o cuerpo subido por el usuario para el try-on. Máximo 3.
@Model
public final class BodyProfile {
    public var id: UUID = UUID()
    public var label: String = ""
    public var imageKey: String = ""
    public var createdAt: Date = Date()

    /// Sin esta fecha, **la imagen no sale del dispositivo**. El try-on corre en
    /// servidor, y una foto de cuerpo es dato personal de categoría sensible:
    /// el consentimiento es explícito, separado y revocable.
    public var consentAcceptedAt: Date?

    public init(label: String, imageKey: String) {
        self.id = UUID()
        self.label = label
        self.imageKey = imageKey
        self.createdAt = Date()
    }

    public static let maximumProfiles = 3
    public var canLeaveDevice: Bool { consentAcceptedAt != nil }
}

/// Un modelo de Core ML ya descargado, verificado y compilado.
@Model
public final class DownloadedModel {
    #Unique<DownloadedModel>([\.modelID])

    public var modelID: String = ""
    public var version: Int = 0
    public var sha256: String = ""
    /// Relativo a Application Support, no absoluto: la ruta del contenedor
    /// cambia entre instalaciones y un absoluto deja de resolver.
    public var compiledPath: String = ""
    public var sizeBytes: Int = 0
    public var downloadedAt: Date = Date()
    public var lastValidatedAt: Date?

    public init(modelID: String, version: Int, sha256: String, compiledPath: String, sizeBytes: Int) {
        self.modelID = modelID
        self.version = version
        self.sha256 = sha256
        self.compiledPath = compiledPath
        self.sizeBytes = sizeBytes
        self.downloadedAt = Date()
    }
}

/// Una sesión de escaneo de galería, reanudable.
///
/// iOS no da CPU sostenida en segundo plano para visión, así que el escaneo se
/// pausa al salir de la app. Esto es lo que permite volver y continuar donde se
/// quedó en vez de empezar de cero.
@Model
public final class ScanSession {
    public var id: UUID = UUID()
    public var startedAt: Date = Date()
    /// Último `PHAsset.localIdentifier` procesado.
    public var cursorAssetID: String?
    public var cursorIndex: Int = 0
    public var totalAssets: Int = 0
    public var photosProcessed: Int = 0
    public var garmentsFound: Int = 0
    public var outfitsFound: Int = 0
    public var stateRaw: String = State.running.rawValue

    public enum State: String, Sendable {
        case running, paused, finished, skipped
    }

    public init(totalAssets: Int) {
        self.id = UUID()
        self.startedAt = Date()
        self.totalAssets = totalAssets
    }

    public var state: State {
        get { State(rawValue: stateRaw) ?? .paused }
        set { stateRaw = newValue.rawValue }
    }

    public var fractionComplete: Double {
        totalAssets > 0 ? Double(photosProcessed) / Double(totalAssets) : 0
    }
}
