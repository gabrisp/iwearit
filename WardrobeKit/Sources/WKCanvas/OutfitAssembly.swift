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
        // **Repartir el papel según lo que hay, sin pisarse.**
        //
        // Antes cada tipo tenía una caja fija, grande y solapada con las
        // demás: las gafas caían sobre la camiseta, el bolso sobre el
        // pantalón, y dos complementos se apilaban casi en el mismo sitio.
        // Ahora la ropa va en una columna, cada cosa en su banda —arriba, las
        // piernas, el calzado—, y si hay complementos tienen **su propio
        // carril** a un lado, uno debajo de otro: lo de la cabeza arriba, el
        // bolso abajo. La chaqueta sigue un poco detrás de la camiseta, que es
        // como se ve un conjunto; lo demás no se toca.
        let variant = Int(seed % 3)
        let width = CanvasSpace.width
        let slots = pieces.map { OutfitSlot.slot(for: $0.kind) }
        let accessoryIndices = pieces.indices.filter { slots[$0] == .accessory }
        let hasRail = !accessoryIndices.isEmpty
        let railWidth = 290.0
        // La columna de la ropa: todo el ancho, o lo que deja el carril.
        // **El carril, a la izquierda**: a la derecha las tarjetas llevan sus
        // botones —favorito, planificar, maleta— y los complementos quedaban
        // debajo.
        let columnMin = hasRail ? railWidth + 30 : 20.0
        let columnMax = width - 20
        let columnWidth = columnMax - columnMin
        let columnCenter = (columnMin + columnMax) / 2

        let present = Set(slots).union(occupied)
        let hasDress = pieces.contains { $0.kind == .wholeBody }
        let layered = present.contains(.outer) && (present.contains(.top) || hasDress)

        // Los complementos, en su orden por el carril: cabeza, lo de en medio,
        // y lo que se lleva en la mano al fondo.
        let railOrder = accessoryIndices.sorted { lhs, rhs in
            func rank(_ kind: GarmentKind) -> Int {
                switch kind { case .head: 0; case .bag: 2; default: 1 }
            }
            return (rank(pieces[lhs].kind), lhs) < (rank(pieces[rhs].kind), rhs)
        }
        let railTop = 80.0
        let railBottom = CanvasSpace.height - 80
        let railStep = min(330, (railBottom - railTop) / Double(max(1, railOrder.count)))

        var seen: [OutfitSlot: Int] = [:]
        return pieces.enumerated().map { index, piece in
            let slot = slots[index]
            let repeatCount = seen[slot, default: 0]
            seen[slot] = repeatCount + 1

            var x = columnCenter
            var y = 0.0
            var box = 0.0
            var zIndex = 1.0

            switch slot {
            case .outer:
                // Detrás, y hacia un lado si hay algo delante.
                box = min(columnWidth * (layered ? 0.74 : 0.9), 640)
                x = layered ? columnMin + columnWidth * 0.37 : columnCenter
                y = hasDress ? 420 : 340
                zIndex = 0
            case .top:
                if piece.kind == .wholeBody {
                    // Un vestido ocupa el torso y las piernas: una caja alta.
                    box = min(columnWidth * 0.92, 900)
                    x = layered ? columnMin + columnWidth * 0.62 : columnCenter
                    y = 620
                } else {
                    box = min(columnWidth * (layered ? 0.66 : 0.86), layered ? 540 : 600)
                    x = layered ? columnMin + columnWidth * 0.66 : columnCenter
                    y = layered ? 380 : 340
                }
                zIndex = 1
            case .bottom:
                box = min(columnWidth * 0.84, 580) * piece.boxScale
                x = columnCenter
                // Lo corto sube, pegado al torso.
                y = piece.isShort ? 780 : 910
                zIndex = 1
            case .shoes:
                box = min(columnWidth * 0.52, 330)
                x = columnCenter
                y = CanvasSpace.height - 150
                zIndex = 2
            case .accessory:
                let order = railOrder.firstIndex(of: index) ?? 0
                box = min(railWidth - 20, railStep * 0.86) * (piece.kind == .bag ? 1.05 : 1)
                x = railWidth / 2 + 15
                // Uno solo: donde le toca por lo que es.
                if railOrder.count == 1 {
                    y = switch piece.kind {
                    case .head: 280
                    case .bag: CanvasSpace.height - 360
                    default: 700
                    }
                } else {
                    y = railTop + railStep * (Double(order) + 0.5)
                }
                zIndex = 3
            }

            // Dos de lo mismo en la columna —dos camisetas—: la segunda se
            // corre lo justo para que se vean las dos.
            if repeatCount > 0, slot != .accessory {
                x += 140 * Double(repeatCount)
                y += 90 * Double(repeatCount)
                box *= 0.82
                zIndex += Double(repeatCount)
            }

            switch variant {
            case 1:
                // El espejo, **dentro de la columna**: la chaqueta cambia de
                // lado con la camiseta; el carril se queda donde está.
                if slot != .accessory { x = columnMin + columnMax - x }
            case 2:
                // Escalonado: el torso sube un poco y las piernas bajan.
                if slot == .top || slot == .outer { y -= 30 }
                if slot == .bottom || slot == .shoes { y += 20 }
            default:
                break
            }

            return ItemTransform(
                x: x,
                y: y,
                baseWidth: box,
                baseHeight: box,
                scale: 1,
                rotation: Self.tilt(seed: seed, index: index),
                zIndex: zIndex
            )
        }
    }

    // El reparto de antes, con una caja fija y solapada por tipo:
    // public nonisolated static func transforms(
    //     for pieces: [Piece],
    //     occupied: Set<OutfitSlot> = [],
    //     seed: UInt64
    // ) -> [ItemTransform] {
    //     var taken = occupied
    //     var z = 10.0
    //     let variant = Int(seed % 3)
    //
    //     return pieces.enumerated().map { index, piece in
    //         let slot = OutfitSlot.slot(for: piece.kind)
    //         defer { taken.insert(slot) }
    //         let base = slot.transform
    //         let isRepeat = taken.contains(slot)
    //
    //         var x = base.x
    //         var y = base.y
    //         var width = base.baseWidth * piece.boxScale
    //         var height = base.baseHeight * piece.boxScale
    //         var zIndex = base.zIndex
    //
    //         if isRepeat {
    //             // Dos complementos en el mismo hueco se apilarían uno sobre
    //             // otro: el segundo se corre lo justo para que se vean los dos.
    //             x -= 210
    //             y += 120
    //             width *= 0.8
    //             height *= 0.8
    //             z += 1
    //             zIndex = z
    //         }
    //
    //         // Lo corto sube: si se encoge la caja y se deja el centro donde
    //         // estaba, queda un palmo de aire entre la camiseta y el pantalón.
    //         if piece.isShort, slot == .bottom {
    //             y -= base.baseHeight * (1 - piece.boxScale) * 0.45
    //         }
    //
    //         switch variant {
    //         case 1:
    //             // El espejo: lo que estaba a la izquierda, a la derecha.
    //             x = CanvasSpace.width - x
    //         case 2:
    //             // Escalonado: el torso sube y las piernas bajan.
    //             if slot == .top || slot == .outer { y -= 50 }
    //             if slot == .bottom || slot == .shoes { y += 40 }
    //         default:
    //             break
    //         }
    //
    //         // **El complemento, donde le toca por lo que es.**
    //         //
    //         // Iba siempre arriba a la derecha, y ahí una mochila queda
    //         // flotando sobre el hombro como si se hubiera caído del cielo. Un
    //         // gorro sí va arriba —es donde se lleva—, pero un bolso o una
    //         // mochila van al suelo, junto a las piernas y el calzado, que es
    //         // donde los deja cualquiera. Y dentro de su zona, la semilla
    //         // reparte entre un par de sitios para que no salgan todos
    //         // calcados.
    //         if slot == .accessory {
    //             let spot = Self.accessorySpot(kind: piece.kind, variant: variant)
    //             x = spot.x
    //             y = spot.y
    //             width *= spot.scale
    //             height *= spot.scale
    //         }
    //
    //         // Y una inclinación pequeña, distinta por prenda: lo justo para
    //         // que no parezca un muestrario alineado con regla.
    //         let tilt = Self.tilt(seed: seed, index: index)
    //
    //         return ItemTransform(
    //             x: x,
    //             y: y,
    //             baseWidth: width,
    //             baseHeight: height,
    //             scale: base.scale,
    //             rotation: tilt,
    //             zIndex: zIndex
    //         )
    //     }
    // }

    /// Dónde cae un complemento, según qué sea.
    ///
    /// Lo de la cabeza arriba, lo que se lleva en la mano o al hombro abajo, y
    /// lo demás —una bufanda, un cinturón— a media altura, que es por donde
    /// pasa. Dos sitios por zona para que dos conjuntos seguidos no lo pongan
    /// en el mismo punto.
    private nonisolated static func accessorySpot(
        kind: GarmentKind,
        variant: Int
    ) -> (x: Double, y: Double, scale: Double) {
        let alternate = variant == 1
        switch kind {
        case .head:
            // Sobre el hombro, a un lado del torso: puesto en el centro tapa
            // el cuello de la prenda de arriba.
            return alternate
                ? (x: 250, y: 300, scale: 0.85)
                : (x: 770, y: 300, scale: 0.85)
        case .bag:
            // En el suelo, al lado del calzado. Un poco más grande que el
            // resto de complementos porque un bolso lo es.
            return alternate
                ? (x: 815, y: 1215, scale: 1.05)
                : (x: 195, y: 1215, scale: 1.05)
        default:
            // Bufandas, cinturones y demás: a la altura del torso, al borde.
            return alternate
                ? (x: 215, y: 780, scale: 0.9)
                : (x: 800, y: 780, scale: 0.9)
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
