import CoreGraphics
import Foundation
import WKPersistence

/// Máscaras alfa ya calculadas, por clave de imagen.
///
/// Generar una máscara cuesta decodificar la imagen y recorrer 64×64 píxeles.
/// Hacerlo en cada toque sería absurdo; hacerlo en cada `body`, catastrófico.
@MainActor
@Observable
public final class MaskCache {
    private var masks: [String: AlphaMask] = [:]
    private var inFlight: Set<String> = []
    private let store: ImageStore

    public init(store: ImageStore) {
        self.store = store
    }

    public func mask(for key: String) -> AlphaMask? { masks[key] }

    /// Pide la máscara si no está. Idempotente: llamarlo desde varias celdas a
    /// la vez no lanza el trabajo dos veces.
    public func load(key: String) {
        guard masks[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)

        Task {
            defer { inFlight.remove(key) }
            guard let image = try? await store.image(for: key, variant: .thumb) else { return }
            masks[key] = AlphaMask(image)
        }
    }
}
