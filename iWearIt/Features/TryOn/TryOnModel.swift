import Foundation
import Observation
import SwiftData
import UIKit
import WKCore
import WKPersistence
import WKVision

/// Probarse un outfit: la foto tuya con esa ropa puesta.
///
/// ## Qué sale del teléfono y con qué permiso
///
/// Una foto tuya y los recortes de las prendas. Nada más — ni nombre, ni
/// armario, ni de quién es la cuenta. Y **no sale sin que lo digas**: la
/// primera vez hay que aceptar, la fecha se guarda en el `BodyProfile`, y
/// quitar la foto lo revoca. Es el único sitio de la app donde una foto de una
/// persona viaja a un servidor, así que se trata como lo que es.
///
/// ## Por qué en servidor
///
/// Porque los modelos que saben vestir a alguien son de difusión clase SDXL:
/// dos gigas en disco, picos de tres de memoria y cuarenta segundos por imagen
/// en el mejor iPhone. On-device no es "más lento", es que no cabe.
@MainActor
@Observable
final class TryOnModel {

    enum State: Equatable {
        case idle
        case working
        case done
        case failed(String)
    }

    private(set) var state: State = .idle
    /// La imagen generada, mientras la hoja viva. No se guarda sola: guardarla
    /// es una decisión tuya, y una foto tuya menos en el disco es una foto
    /// tuya menos que perder.
    private(set) var result: UIImage?

    private let resolver: (any ClothingResolving)?
    private let imageStore: ImageStore

    init(resolver: (any ClothingResolving)?, imageStore: ImageStore) {
        self.resolver = resolver
        self.imageStore = imageStore
    }

    var canGenerate: Bool { resolver != nil }

    /// Genera la prueba.
    ///
    /// - Parameters:
    ///   - profile: tu foto, con el consentimiento ya aceptado.
    ///   - garments: las prendas del conjunto, de arriba abajo.
    /// - Returns: `true` si salió algo, para que quien llama apunte el gasto.
    @discardableResult
    func generate(for profile: BodyProfile, garments: [Garment]) async -> Bool {
        guard let resolver else {
            state = .failed("Esto necesita conexión con el servidor.")
            return false
        }
        guard profile.canLeaveDevice else {
            // No debería llegar aquí: la hoja pide el permiso antes. Pero si
            // llega, no se manda nada.
            state = .failed("Falta aceptar que la foto salga del teléfono.")
            return false
        }
        guard !garments.isEmpty else {
            state = .failed("Este conjunto no tiene prendas.")
            return false
        }

        state = .working
        result = nil

        guard
            let person = try? await imageStore.image(for: profile.imageKey, variant: .display),
            let personJPEG = Self.jpeg(from: person, maxSide: 1024)
        else {
            state = .failed("No se pudo preparar tu foto.")
            return false
        }

        var pieces: [Data] = []
        for garment in garments.prefix(6) {
            guard
                let image = try? await imageStore.image(
                    for: garment.normalizedImageKey, variant: .display
                ),
                let png = Self.png(from: image)
            else { continue }
            pieces.append(png)
        }
        guard !pieces.isEmpty else {
            state = .failed("No se pudieron preparar las prendas.")
            return false
        }

        do {
            let data = try await resolver.tryOn(personJPEG: personJPEG, garmentsPNG: pieces)
            guard let image = UIImage(data: data) else {
                state = .failed("El servidor devolvió algo que no es una imagen.")
                return false
            }
            result = image
            state = .done
            DiagnosticsLog.record("PROBADOR", "listo · \(pieces.count) prenda(s)")
            return true
        } catch {
            DiagnosticsLog.record("PROBADOR", "falla: \(error)", isProblem: true)
            state = .failed(Self.describe(error))
            return false
        }
    }

    /// **El recorte va en PNG**, que es lo único que conserva el alfa: en JPEG
    /// la prenda llegaría dentro de un rectángulo blanco y el modelo lo
    /// pintaría como parte de la ropa.
    private static func png(from image: CGImage) -> Data? {
        UIImage(cgImage: image).pngData()
    }

    /// Tu foto, **sin cuadrarla**.
    ///
    /// El encoder de las prendas encaja en un cuadrado, que para un recorte
    /// está bien y para una persona no: la deformaría. Aquí se reduce por el
    /// lado largo y se guarda la proporción.
    private static func jpeg(from image: CGImage, maxSide: Int) -> Data? {
        let longest = max(image.width, image.height)
        let scale = longest > maxSide ? Double(maxSide) / Double(longest) : 1
        let size = CGSize(
            width: Double(image.width) * scale,
            height: Double(image.height) * scale
        )
        let renderer = UIGraphicsImageRenderer(size: size)
        let drawn = renderer.image { context in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
            _ = context
        }
        return drawn.jpegData(compressionQuality: 0.9)
    }

    private static func describe(_ error: Error) -> String {
        guard let resolverError = error as? ClothingResolverError else {
            return "No se pudo generar la prueba."
        }
        switch resolverError {
        case .rateLimited:
            return "El servidor está saturado. Prueba en un minuto."
        case let .badResponse(reason) where reason.contains("no_image"):
            return "El modelo no ha querido generar esta imagen."
        case .notConfigured:
            return "Esto necesita conexión con el servidor."
        case let .transport(reason):
            return "No se pudo conectar: \(reason)"
        case .badResponse:
            return "No se pudo generar la prueba."
        }
    }
}
