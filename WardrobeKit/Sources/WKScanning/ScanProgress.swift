import CoreGraphics
import Foundation
import WKCore
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

/// Una foto de la galería con prendas, para la animación del escaneo.
///
/// **Una por foto, no por prenda**: lo que se enseña es la foto de verdad, en
/// pequeño, y las prendas saliendo de ella desde el sitio exacto en el que
/// estaban. Las fotos sin prendas —o con recortes que no valen— no llegan aquí.
public struct ScanDiscovery: Sendable, Identifiable {
    public struct Piece: Sendable, Identifiable {
        public let id = UUID()
        /// El recorte tal cual sale de la foto, reducido para la pantalla.
        public let image: ImmutableImage
        /// Dónde estaba dentro de la foto, 0-1 con el origen arriba a la
        /// izquierda. `nil` = no se pudo situar; sale del centro.
        public let sourceRect: CGRect?
        public let kind: GarmentKind

        public init(image: ImmutableImage, sourceRect: CGRect?, kind: GarmentKind) {
            self.image = image
            self.sourceRect = sourceRect
            self.kind = kind
        }
    }

    public let id = UUID()
    /// De qué foto de la galería sale: el mismo que el de su `ScanLook`.
    public let photoID: String
    /// La foto, pequeña.
    public let photo: ImmutableImage
    public let pieces: [Piece]

    public init(photoID: String = "", photo: ImmutableImage, pieces: [Piece]) {
        self.photoID = photoID
        self.photo = photo
        self.pieces = pieces
    }
}

/// Una foto que **se empieza a analizar**.
///
/// Se avisa antes de saber si tiene ropa: esperar al resultado hacía que la
/// pantalla estuviera quieta mientras el escáner trabajaba, y las fotos
/// aparecían tarde y de golpe. Si luego da prendas, llega su `ScanDiscovery`
/// con el mismo `photoID`; si no, no llega nada.
public struct ScanLook: Sendable, Identifiable {
    public let photoID: String
    public let photo: ImmutableImage
    public var id: String { photoID }

    public init(photoID: String, photo: ImmutableImage) {
        self.photoID = photoID
        self.photo = photo
    }
}
