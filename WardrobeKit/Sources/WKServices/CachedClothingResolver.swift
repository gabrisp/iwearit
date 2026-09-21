import Foundation
import WKCore

/// El resolutor remoto, con memoria.
///
/// Decorador y no un parámetro más del resolutor: quien pregunta —el pipeline,
/// en `WKVision`— no tiene por qué saber que existe una caché, ni `WKVision`
/// tiene por qué depender de `WKServices` para enterarse. Los dos ven el mismo
/// `ClothingResolving` y uno de ellos resulta que se acuerda de lo que ya
/// preguntó.
///
/// La clave es el sha256 del JPEG que se iba a mandar, así que dos fotos
/// distintas de la misma prenda —que producen el mismo recorte normalizado—
/// comparten respuesta sin que nadie lo programe.
public struct CachedClothingResolver: ClothingResolving {
    private let base: any ClothingResolving
    private let cache: ResolutionCache

    public init(base: any ClothingResolving, cache: ResolutionCache) {
        self.base = base
        self.cache = cache
    }

    public func resolve(_ query: RemoteGarmentQuery) async throws -> RemoteGarmentAnswer {
        let key = ResolutionCache.key(for: query.imageJPEG)
        if let cached = await cache.answer(for: key) {
            DiagnosticsLog.record("REMOTO", "ya resuelta antes (\(key.prefix(8))), no se vuelve a preguntar")
            return cached
        }

        let answer = try await base.resolve(query)
        await cache.store(answer, for: key)
        return answer
    }

    /// Pasa de largo: la imagen generada no se guarda aquí sino en el
    /// `ImageStore`, como una variante más de la prenda. Meter imágenes en esta
    /// caché sería tener dos sitios donde vive la misma imagen, y dos sitios
    /// que limpiar al borrar una prenda.
    public func restyle(_ imageJPEG: Data) async throws -> Data {
        try await base.restyle(imageJPEG)
    }
}
