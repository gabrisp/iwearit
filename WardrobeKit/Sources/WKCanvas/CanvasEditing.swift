import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Las operaciones sobre un elemento del canvas.
///
/// Funciones y no métodos de una vista: las usa la barra de herramientas, que
/// vive en la pantalla anfitriona, y el canvas, que vive en el paquete. Tenerlas
/// dentro de una de las dos obligaría a la otra a pedírselas.
public enum CanvasEditing {

    /// Quita el elemento del outfit.
    ///
    /// Sin confirmación: la prenda sigue en el armario, esto solo la saca del
    /// outfit. Preguntar por algo que no destruye nada es ruido.
    public static func delete(_ item: CanvasItem, in context: ModelContext) {
        withAnimation(WKAnimation.content) { context.delete(item) }
    }

    /// Duplica, desplazada.
    ///
    /// Una copia exactamente debajo del original es indistinguible de que no
    /// haya pasado nada.
    @discardableResult
    public static func duplicate(
        _ item: CanvasItem,
        in outfit: Outfit,
        context: ModelContext
    ) -> CanvasItem {
        var transform = item.transform
        transform.x += 40
        transform.y += 40
        transform.zIndex = outfit.nextZIndex

        let copy = CanvasItem(transform: transform, garment: item.garment)
        if let sticker = item.sticker { copy.apply(sticker) }
        copy.isFlipped = item.isFlipped
        copy.outfit = outfit
        context.insert(copy)
        return copy
    }

    /// Sube o baja una capa.
    ///
    /// Suma sobre el extremo en vez de reindexar el array: reindexar es la
    /// forma clásica de perder el orden exacto al recargar.
    public static func restack(_ item: CanvasItem, in outfit: Outfit, toFront: Bool) {
        withAnimation(WKAnimation.selection) {
            var transform = item.transform
            transform.zIndex = toFront ? outfit.nextZIndex : outfit.lowestZIndex
            item.apply(transform)
        }
    }

    /// Espejo horizontal.
    ///
    /// Es la operación que hace falta de verdad en un collage: un zapato
    /// recortado mira hacia un lado, y para poner el par mirando hacia dentro
    /// no vale girarlo —girándolo queda tumbado—, hay que voltearlo.
    public static func flip(_ item: CanvasItem) {
        withAnimation(WKAnimation.arrival) { item.isFlipped.toggle() }
    }

    public static func center(_ item: CanvasItem) {
        mutate(item) { $0.x = CanvasSpace.center.x; $0.y = CanvasSpace.center.y }
    }

    public static func straighten(_ item: CanvasItem) {
        mutate(item) { $0.rotation = 0 }
    }

    public static func resetScale(_ item: CanvasItem) {
        mutate(item) { $0.scale = 1 }
    }

    /// Añade una prenda, centrada y al frente.
    ///
    /// **Del tamaño que le toca por su tipo**, no de uno fijo. Estaba clavado
    /// en 240×320 sobre un papel de 1000 de ancho: una camiseta añadida desde
    /// la bandeja entraba a menos de la cuarta parte del lienzo, y había que
    /// agrandarla a mano cada vez. Ahora entra midiendo lo mismo que si la
    /// hubiera colocado el compositor —ver `OutfitSlot`—, solo que en el
    /// centro, que es donde se espera lo que acabas de añadir.
    @discardableResult
    public static func insert(
        garment: Garment,
        in outfit: Outfit,
        context: ModelContext
    ) -> CanvasItem {
        let slot = OutfitSlot.slot(for: garment.kind).transform
        let transform = ItemTransform(
            x: CanvasSpace.center.x,
            y: CanvasSpace.center.y,
            baseWidth: slot.baseWidth,
            baseHeight: slot.baseHeight,
            scale: 1,
            rotation: 0,
            zIndex: outfit.nextZIndex
        )
        let item = CanvasItem(transform: transform, garment: garment)
        item.outfit = outfit
        context.insert(item)
        return item
    }

    /// Añade un sticker, centrado y al frente.
    @discardableResult
    public static func insert(
        sticker: CanvasSticker,
        size: CGSize,
        in outfit: Outfit,
        context: ModelContext
    ) -> CanvasItem {
        let transform = ItemTransform(
            x: CanvasSpace.center.x,
            y: CanvasSpace.center.y,
            baseWidth: size.width,
            baseHeight: size.height,
            scale: 1,
            rotation: 0,
            zIndex: outfit.nextZIndex
        )
        let item = CanvasItem(transform: transform, garment: nil)
        item.apply(sticker)
        item.outfit = outfit
        context.insert(item)
        return item
    }

    private static func mutate(_ item: CanvasItem, _ change: (inout ItemTransform) -> Void) {
        withAnimation(WKAnimation.arrival) {
            var transform = item.transform
            change(&transform)
            item.apply(transform)
        }
    }
}
