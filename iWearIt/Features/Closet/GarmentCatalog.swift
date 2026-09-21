import Foundation
import UIKit
import WKCore
import WKPersistence
import WKVision

/// Pedir la versión de catálogo de una prenda ya guardada.
///
/// En un sitio y no copiada en cada pantalla: la piden la ficha, la hoja de
/// editar y el reemplazo de foto, y son exactamente el mismo cuatro pasos
/// —cargar, codificar, pedir, guardar—. Con tres copias, la primera que
/// cambiara dejaría a las otras dos generando de otra manera.
enum GarmentCatalog {

    /// - Returns: `true` si se generó y se guardó.
    @discardableResult
    static func regenerate(
        for key: String,
        store: ImageStore,
        resolver: (any ClothingResolving)?
    ) async -> Bool {
        guard let resolver else {
            DiagnosticsLog.record("CATÁLOGO", "sin resolutor: no se puede generar", isProblem: true)
            return false
        }
        guard
            let source = try? await store.image(for: key, variant: .display),
            let jpeg = NormalizedJPEG.encode(source)
        else {
            DiagnosticsLog.record("CATÁLOGO", "no se pudo leer el recorte", isProblem: true)
            return false
        }

        do {
            let data = try await resolver.restyle(jpeg)
            guard let decoded = UIImage(data: data)?.cgImage else {
                DiagnosticsLog.record("CATÁLOGO", "la respuesta no era una imagen", isProblem: true)
                return false
            }
            // El croma se quita **aquí**, como en la importación: lo que se
            // guarda es la prenda sola con alfa de verdad, nunca la imagen tal
            // cual la devuelve el modelo.
            let cut = await CatalogExtractor.extract(decoded, kind: .other) ?? decoded
            try await store.storeCatalog(cut, for: key)
            DiagnosticsLog.record("CATÁLOGO", "regenerado para \(key.prefix(8))")
            return true
        } catch {
            DiagnosticsLog.record(
                "CATÁLOGO", "falló la generación: \(error)", isProblem: true
            )
            return false
        }
    }
}
