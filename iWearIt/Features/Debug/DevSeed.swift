#if DEBUG
import CoreGraphics
import Foundation
import SwiftData
import WKCore
import SwiftUI
import WKDesign
import WKPersistence

/// Siembra el armario con prendas dibujadas.
///
/// No son fotos: son siluetas planas con fondo transparente, del mismo tamaño y
/// forma que producirá el pipeline. Bastan para construir y **medir** las
/// baldas (F2) y el canvas (F4) antes de que exista un solo modelo de Core ML,
/// que es justo el orden de construcción que elegimos.
enum DevSeed {

    private struct Spec {
        let kind: GarmentKind
        let noun: String
        let shape: WKGarmentSilhouette
    }

    private static let palette: [(name: String, rgb: (Double, Double, Double))] = [
        ("granate", (0.45, 0.13, 0.16)), ("crema", (0.93, 0.90, 0.83)),
        ("negro", (0.11, 0.11, 0.12)), ("oliva", (0.36, 0.38, 0.24)),
        ("azul", (0.20, 0.29, 0.45)), ("camel", (0.70, 0.56, 0.36)),
        ("blanco", (0.97, 0.97, 0.96)), ("gris", (0.52, 0.52, 0.54)),
    ]

    private static let specs: [Spec] = [
        .init(kind: .outerLayer, noun: "Cazadora", shape: .outer),
        .init(kind: .outerLayer, noun: "Chaqueta", shape: .outer),
        .init(kind: .outerLayer, noun: "Abrigo", shape: .outer),
        .init(kind: .wholeBody, noun: "Vestido", shape: .dress),
        .init(kind: .wholeBody, noun: "Mono", shape: .dress),
        .init(kind: .upperBody, noun: "Camiseta", shape: .top),
        .init(kind: .upperBody, noun: "Camisa", shape: .top),
        .init(kind: .upperBody, noun: "Sudadera", shape: .top),
        .init(kind: .upperBody, noun: "Jersey", shape: .top),
        .init(kind: .lowerBody, noun: "Vaqueros", shape: .pants),
        .init(kind: .lowerBody, noun: "Chinos", shape: .pants),
        .init(kind: .lowerBody, noun: "Shorts", shape: .pants),
        .init(kind: .feet, noun: "Zapatillas", shape: .shoe),
        .init(kind: .feet, noun: "Botas", shape: .shoe),
        .init(kind: .head, noun: "Gorra", shape: .cap),
        .init(kind: .head, noun: "Gorro", shape: .cap),
        .init(kind: .bag, noun: "Bolso", shape: .bag),
    ]

    /// - Returns: cuántas prendas se crearon.
    @discardableResult
    static func populate(
        wardrobe: WardrobeActor,
        imageStore: ImageStore,
        count: Int = 30
    ) async throws -> Int {
        var drafts: [GarmentDraft] = []
        drafts.reserveCapacity(count)

        for index in 0..<count {
            let spec = specs[index % specs.count]
            let color = palette[(index / specs.count + index) % palette.count]
            let image = render(spec.shape, rgb: color.rgb)
            let key = try await imageStore.store(image)

            drafts.append(
                GarmentDraft(
                    kind: spec.kind,
                    subcategory: spec.noun.lowercased(),
                    colors: [NamedColor(
                        nameKey: color.name,
                        red: color.rgb.0, green: color.rgb.1, blue: color.rgb.2,
                        weight: 1
                    )],
                    normalizedImageKey: key,
                    confidence: 1,
                    proposedName: "\(spec.noun) en \(color.name)"
                )
            )
        }

        // Por lotes, igual que hará el escaneo masivo: así el camino de
        // inserción que se ejercita en desarrollo es el mismo que el de producción.
        for start in stride(from: 0, to: drafts.count, by: WardrobeActor.batchSize) {
            let slice = Array(drafts[start..<min(start + WardrobeActor.batchSize, drafts.count)])
            try await wardrobe.insert(slice)
        }
        return drafts.count
    }

    // MARK: - Dibujo

    private static let canvas = 512

    /// Rasteriza la silueta compartida.
    ///
    /// **La misma que usa el armario vacío**, no una copia. Tener dos juegos de
    /// contornos fue exactamente cómo aquí acabaron dibujándose rectángulos
    /// mientras el resto de la app ya tenía prendas.
    private static func render(
        _ silhouette: WKGarmentSilhouette,
        rgb: (Double, Double, Double)
    ) -> CGImage {
        let side = CGFloat(canvas)
        let height = (side / silhouette.aspectRatio).rounded()
        let box = CGRect(x: 0, y: 0, width: side, height: height)

        let context = CGContext(
            data: nil, width: Int(side), height: Int(height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(box)
        // `Path` mide con la y hacia abajo y `CGContext` hacia arriba: sin este
        // volteo las prendas salen del revés.
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        context.addPath(silhouette.path(in: box).cgPath)
        // `winding`, nunca `evenOdd`: con `evenOdd` el trazo que redondea las
        // esquinas se cancelaría contra el contorno que engorda.
        context.fillPath(using: .winding)
        return context.makeImage()!
    }
}
#endif
