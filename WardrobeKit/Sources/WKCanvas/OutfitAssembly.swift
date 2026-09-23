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
    /// - Parameter seed: qué variante de reparto se usa. La misma que se
    ///   enseñó en la tarjeta, para que guardar no recoloque nada.
    public static func place(
        _ garments: [Garment],
        in outfit: Outfit,
        context: ModelContext,
        keeping keptIDs: Set<UUID> = [],
        replacingGarments: Bool = true,
        seed: UInt64 = 0
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
        let layout = transforms(
            for: incoming.map { Piece(kind: $0.kind, cut: $0.cut, subcategory: $0.subcategory) },
            occupied: occupied,
            seed: seed
        )
        for (garment, transform) in zip(incoming, layout) {
            let item = CanvasItem(transform: transform, garment: garment)
            item.outfit = outfit
            context.insert(item)
        }
        outfit.modifiedAt = Date()
    }

    /// Lo que hace falta saber de una prenda para colocarla.
    ///
    /// Con el corte y el tipo, no solo la parte del cuerpo: un pantalón corto
    /// y unos vaqueros van al mismo sitio y **no miden lo mismo**. Con la caja
    /// del hueco a secas, el corto se estiraba hasta llenarla y salía tan
    /// grande como el pantalón largo —o más, porque el recorte es casi
    /// cuadrado—, y el conjunto parecía montado por alguien que no ha visto un
    /// short en su vida.
    public struct Piece: Sendable, Hashable {
        public let kind: GarmentKind
        public let cut: String?
        public let subcategory: String?

        public init(kind: GarmentKind, cut: String? = nil, subcategory: String? = nil) {
            self.kind = kind
            self.cut = cut
            self.subcategory = subcategory
        }

        /// Prendas que ocupan menos de lo que su hueco da por hecho.
        var isShort: Bool {
            let words = [cut, subcategory]
                .compactMap { $0?.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
            let shortWords: Set<String> = [
                "corto", "corta", "capri", "short", "shorts", "bermudas", "banador", "mini",
            ]
            return words.contains { shortWords.contains($0) }
        }

        /// Cuánto se encoge su caja.
        ///
        /// Dos tercios y no la mitad: un short sigue siendo la pieza de abajo
        /// y tiene que leerse como tal; encogido de más se convierte en un
        /// complemento colgando entre la camiseta y los zapatos.
        var boxScale: Double { isShort ? 0.66 : 1 }
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
        transforms(for: kinds.map { Piece(kind: $0) }, occupied: occupied, seed: 0)
    }

    /// Lo mismo, sabiendo qué es cada prenda y **con variación**.
    ///
    /// ## Por qué no siempre igual
    ///
    /// Porque con un solo reparto todos los conjuntos se ven iguales: cambia
    /// la ropa y la foto es la misma foto. Un puñado de variantes —el espejo,
    /// el escalonado, una inclinación de un par de grados— hace que dos
    /// propuestas seguidas se distingan de un vistazo sin que ninguna quede
    /// mal colocada.
    ///
    /// La variante sale de la **semilla**, no del azar: el mismo conjunto se
    /// pinta igual cada vez que se mira, y lo que guardas es lo que viste.
    public nonisolated static func transforms(
        for pieces: [Piece],
        occupied: Set<OutfitSlot> = [],
        seed: UInt64
    ) -> [ItemTransform] {
        var taken = occupied
        var z = 10.0
        let variant = Int(seed % 3)

        return pieces.enumerated().map { index, piece in
            let slot = OutfitSlot.slot(for: piece.kind)
            defer { taken.insert(slot) }
            let base = slot.transform
            let isRepeat = taken.contains(slot)

            var x = base.x
            var y = base.y
            var width = base.baseWidth * piece.boxScale
            var height = base.baseHeight * piece.boxScale
            var zIndex = base.zIndex

            if isRepeat {
                // Dos complementos en el mismo hueco se apilarían uno sobre
                // otro: el segundo se corre lo justo para que se vean los dos.
                x -= 210
                y += 120
                width *= 0.8
                height *= 0.8
                z += 1
                zIndex = z
            }

            // Lo corto sube: si se encoge la caja y se deja el centro donde
            // estaba, queda un palmo de aire entre la camiseta y el pantalón.
            if piece.isShort, slot == .bottom {
                y -= base.baseHeight * (1 - piece.boxScale) * 0.45
            }

            switch variant {
            case 1:
                // El espejo: lo que estaba a la izquierda, a la derecha.
                x = CanvasSpace.width - x
            case 2:
                // Escalonado: el torso sube, las piernas bajan y el
                // complemento se va al otro lado.
                if slot == .top || slot == .outer { y -= 50 }
                if slot == .bottom || slot == .shoes { y += 40 }
                if slot == .accessory { x = CanvasSpace.width - x }
            default:
                break
            }

            // Y una inclinación pequeña, distinta por prenda: lo justo para
            // que no parezca un muestrario alineado con regla.
            let tilt = Self.tilt(seed: seed, index: index)

            return ItemTransform(
                x: x,
                y: y,
                baseWidth: width,
                baseHeight: height,
                scale: base.scale,
                rotation: tilt,
                zIndex: zIndex
            )
        }
    }

    /// Radianes, entre -2,5° y 2,5°, siempre los mismos para la misma prenda
    /// del mismo conjunto.
    private nonisolated static func tilt(seed: UInt64, index: Int) -> Double {
        var value = seed &+ UInt64(index &* 2_654_435_761)
        value = (value ^ (value >> 33)) &* 0xFF51_AFD7_ED55_8CCD
        let unit = Double(value % 1000) / 1000 * 2 - 1
        return unit * 2.5 * .pi / 180
    }

    /// Un outfit nuevo con estas prendas dentro.
    public static func make(
        from garments: [Garment],
        name: String?,
        origin: OutfitOrigin?,
        isFavorite: Bool,
        backdropRaw: String?,
        context: ModelContext,
        seed: UInt64 = 0
    ) -> Outfit {
        let outfit = Outfit(name: name)
        outfit.originRaw = origin?.rawValue
        outfit.isFavorite = isFavorite
        outfit.backdropRaw = backdropRaw
        context.insert(outfit)
        place(garments, in: outfit, context: context, seed: seed)
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
