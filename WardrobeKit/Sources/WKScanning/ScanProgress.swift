import Foundation
import WKVision

/// Lo que la pantalla de escaneo necesita saber.
///
/// Es un valor y no una referencia observable: el escaneo corre en un actor
/// propio y lo que cruza al hilo principal tiene que ser `Sendable`.
public struct ScanProgress: Sendable, Equatable {
    public var photosProcessed = 0
    public var totalPhotos = 0
    public var garmentsFound = 0
    public var outfitsFound = 0
    /// Fotos que solo existen en iCloud. Se cuentan aparte y se ofrecen luego.
    public var skippedInCloud = 0
    public var isPaused = false
    public var pauseReason: String?

    public var fraction: Double {
        totalPhotos > 0 ? Double(photosProcessed) / Double(totalPhotos) : 0
    }

    public init() {}
}

/// Un recorte recién encontrado, para la animación de la pantalla de escaneo.
public struct ScanDiscovery: Sendable {
    public let image: ImmutableImage
    public let categorySlug: String

    public init(image: ImmutableImage, categorySlug: String) {
        self.image = image
        self.categorySlug = categorySlug
    }
}
