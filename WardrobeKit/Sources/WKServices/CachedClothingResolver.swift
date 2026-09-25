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
    /// Qué hacer cuando de verdad se ha reconstruido una prenda.
    ///
    /// Un aviso y no una dependencia: aquí no se sabe qué es una moneda ni
    /// hace falta saberlo. Quien monta esto —la app— apunta el gasto donde
    /// corresponda. Es el **único** sitio por el que pasan todas las
    /// reconstrucciones, así que apuntarlo aquí es apuntarlo una vez.
    private let onRestyled: (@Sendable () -> Void)?
    /// Falló después de cobrar y el servidor lo devolvió: `true` para una
    /// prueba, `false` para una mejora. Ver `NoticeCenter`.
    private let onRefunded: (@Sendable (_ isTryOn: Bool) -> Void)?

    public init(
        base: any ClothingResolving,
        cache: ResolutionCache,
        onRestyled: (@Sendable () -> Void)? = nil,
        onRefunded: (@Sendable (_ isTryOn: Bool) -> Void)? = nil
    ) {
        self.base = base
        self.cache = cache
        self.onRestyled = onRestyled
        self.onRefunded = onRefunded
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
    /// Pasa de largo, y aquí con más motivo: cada probado es una foto
    /// distinta de una persona, así que dos llamadas nunca son la misma.
    public func tryOn(
        personJPEG: Data?,
        bodyJPEGs: [Data],
        personDescription: String,
        garmentsPNG: [Data],
        direction: TryOnDirection
    ) async throws -> Data {
        do {
            return try await base.tryOn(
                personJPEG: personJPEG,
                bodyJPEGs: bodyJPEGs,
                personDescription: personDescription,
                garmentsPNG: garmentsPNG,
                direction: direction
            )
        } catch ClothingResolverError.refunded(let reason) {
            onRefunded?(true)
            throw ClothingResolverError.refunded(reason)
        }
    }

    public func restyle(_ imageJPEG: Data) async throws -> Data {
        let data: Data
        do {
            data = try await base.restyle(imageJPEG)
        } catch ClothingResolverError.refunded(let reason) {
            onRefunded?(false)
            throw ClothingResolverError.refunded(reason)
        }
        // Solo si ha llegado: lo que falla no se cobra.
        onRestyled?()
        return data
    }
}
