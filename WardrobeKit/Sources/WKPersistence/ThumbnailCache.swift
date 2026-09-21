import Foundation
import UIKit

/// Caché en memoria de miniaturas ya decodificadas.
///
/// Decodificar un HEIC cuesta milisegundos; hacerlo en cada `body` de una balda
/// con scroll horizontal cuesta el frame. `NSCache` se purga sola bajo presión
/// de memoria, que es exactamente lo que hace falta durante el escaneo masivo.
@MainActor
public final class ThumbnailCache {
    public static let shared = ThumbnailCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // Coste en bytes, no en número de objetos: una miniatura de 256 px y un
        // display de 1024 px no pesan lo mismo ni de lejos.
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    private init() {}

    public func image(for key: String, variant: ImageStore.Variant) -> UIImage? {
        cache.object(forKey: Self.cacheKey(key, variant) as NSString)
    }

    public func insert(_ image: UIImage, for key: String, variant: ImageStore.Variant) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: Self.cacheKey(key, variant) as NSString, cost: cost)
    }

    public func removeAll() { cache.removeAllObjects() }

    private static func cacheKey(_ key: String, _ variant: ImageStore.Variant) -> String {
        "\(key).\(variant.rawValue)"
    }
}
