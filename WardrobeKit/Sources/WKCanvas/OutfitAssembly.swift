import Foundation
import SwiftData
import WKCore
import WKPersistence

/// Poner prendas en un lienzo **sin que nadie las coloque a mano**.
///
/// Lo usan tres sitios: la inspiración al guardar un conjunto, el estilista
/// del editor al rehacer un look, y el botón de "añadir un outfit entero".
/// Los tres hacen lo mismo —meter varias prendas de golpe, cada una en su
/// sitio— y por eso está escrito una vez: si cada uno colocara a su manera, el
/// mismo conjunto se vería distinto según por dónde entró.
@MainActor
public enum OutfitAssembly {

    /// Coloca prendas en un outfit, cada una en el hueco que le toca por tipo.
    ///
    /// - Parameters:
    ///   - keeping: prendas que ya están puestas y **no se tocan**: lo que el
    ///     usuario ha colocado a mano o ha dicho que quiere llevar. Sus
    ///     posiciones se respetan tal cual.
    ///   - replacingGarments: si las demás prendas que hubiera se van. Los
    ///     stickers y la pintura no se tocan nunca: son anotaciones tuyas
    ///     sobre el día, no parte del conjunto.
    public static func place(
        _ garments: [Garment],
        in outfit: Outfit,
        context: ModelContext,
        keeping keptIDs: Set<UUID> = [],
        replacingGarments: Bool = true
    ) {
        if replacingGarments {
            for item in outfit.items where item.sticker == nil {
                guard let garment = item.garment else { continue }
                guard !keptIDs.contains(garment.id) else { continue }
                context.delete(item)
            }
        }

        // Los huecos que ya están ocupados por lo que se conserva: una prenda
        // nueva no puede caer encima de la que el usuario quiso dejar.
        let occupied = Set(
            outfit.items
                .compactMap(\.garment)
                .filter { keptIDs.contains($0.id) }
                .map { OutfitSlot.slot(for: $0.kind) }
        )

        let incoming = garments.filter { !keptIDs.contains($0.id) }
        let layout = transforms(for: incoming.map(\.kind), occupied: occupied)
        for (garment, transform) in zip(incoming, layout) {
            let item = CanvasItem(transform: transform, garment: garment)
            item.outfit = outfit
            context.insert(item)
        }
        outfit.modifiedAt = Date()
    }

    /// Dónde va cada prenda de un conjunto, **sin tocar nada**.
    ///
    /// La misma cuenta que usa el lienzo al colocarlas de verdad, para que la
    /// tarjeta de inspiración enseñe exactamente el conjunto que vas a
    /// guardar. Si cada uno hiciera su reparto, guardar un look cambiaría lo
    /// que estabas mirando.
    ///
    /// - Parameter occupied: huecos que ya están pillados.
    public nonisolated static func transforms(
        for kinds: [GarmentKind],
        occupied: Set<OutfitSlot> = []
    ) -> [ItemTransform] {
        var taken = occupied
        var z = 10.0
        return kinds.map { kind in
            let slot = OutfitSlot.slot(for: kind)
            defer { taken.insert(slot) }
            let base = slot.transform
            guard taken.contains(slot) else { return base }
            // Dos complementos en el mismo hueco se apilarían uno sobre otro:
            // el segundo se corre lo justo para que se vean los dos.
            z += 1
            return ItemTransform(
                x: base.x - 210,
                y: base.y + 120,
                baseWidth: base.baseWidth * 0.8,
                baseHeight: base.baseHeight * 0.8,
                scale: base.scale,
                rotation: base.rotation,
                zIndex: z
            )
        }
    }

    /// Un outfit nuevo con estas prendas dentro.
    public static func make(
        from garments: [Garment],
        name: String?,
        origin: OutfitOrigin?,
        isFavorite: Bool,
        backdropRaw: String?,
        context: ModelContext
    ) -> Outfit {
        let outfit = Outfit(name: name)
        outfit.originRaw = origin?.rawValue
        outfit.isFavorite = isFavorite
        outfit.backdropRaw = backdropRaw
        context.insert(outfit)
        place(garments, in: outfit, context: context)
        return outfit
    }

    /// Añade **un outfit entero** encima del que se está editando.
    ///
    /// Se copian las transformadas del original y no los huecos por tipo: si
    /// guardaste ese conjunto con la chaqueta girada y el bolso en una
    /// esquina, así es como lo recuerdas y así tiene que llegar. Lo que sí
    /// cambia es la altura: entra por delante de lo que ya había.
    public static func append(
        _ source: Outfit,
        to target: Outfit,
        context: ModelContext
    ) {
        var z = target.nextZIndex
        for item in source.items where item.garment?.deletedAt == nil {
            guard let garment = item.garment else { continue }
            var transform = item.transform
            transform = ItemTransform(
                x: transform.x,
                y: transform.y,
                baseWidth: transform.baseWidth,
                baseHeight: transform.baseHeight,
                scale: transform.scale,
                rotation: transform.rotation,
                zIndex: z
            )
            z += 1
            let copy = CanvasItem(transform: transform, garment: garment)
            copy.isFlipped = item.isFlipped
            copy.outfit = target
            context.insert(copy)
        }
        target.modifiedAt = Date()
    }
}
