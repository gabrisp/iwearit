import Foundation
import Photos

/// Acceso a la fototeca.
///
/// Detrás de un protocolo para poder mockearlo: los tests no pueden pedir
/// permisos, y el modo `.limited` es casi imposible de reproducir a mano.
public protocol PhotoLibraryServing: Sendable {
    func authorizationStatus() async -> PhotoLibraryAccess
    func requestAuthorization() async -> PhotoLibraryAccess
}

/// Estado del permiso, con `limited` como ciudadano de primera.
///
/// iOS lo devuelve desde iOS 14 y es **el caso más común** en usuarios que ya
/// han dicho que no una vez. Tratarlo como "denegado" deja fuera a mucha gente
/// que sí quiere usar la app, solo que con las fotos que ella elija.
public enum PhotoLibraryAccess: Sendable, Equatable {
    case notDetermined
    case authorized
    /// El usuario eligió un subconjunto de fotos. Se puede escanear ese
    /// subconjunto y ofrecerle ampliarlo.
    case limited
    case denied
    case restricted

    public var canRead: Bool { self == .authorized || self == .limited }

    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .authorized
        case .limited: self = .limited
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }
}

public struct PhotoLibraryService: PhotoLibraryServing {
    public init() {}

    public func authorizationStatus() async -> PhotoLibraryAccess {
        PhotoLibraryAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestAuthorization() async -> PhotoLibraryAccess {
        PhotoLibraryAccess(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }
}

/// Siempre concede acceso. Para previews y tests.
public struct StubPhotoLibraryService: PhotoLibraryServing {
    private let access: PhotoLibraryAccess
    public init(access: PhotoLibraryAccess = .authorized) { self.access = access }
    public func authorizationStatus() async -> PhotoLibraryAccess { access }
    public func requestAuthorization() async -> PhotoLibraryAccess { access }
}
