import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// El canvas libre donde se monta un outfit.
///
/// **No tiene estado de gesto.** Cada prenda lleva el suyo, de modo que
/// arrastrar una invalida solo esa vista. Lo único que este contenedor decide
/// es el factor de escala `k` que lleva el espacio lógico fijo de 1000×1400 al
/// tamaño real de la pantalla — y lo aplica una sola vez, a toda la capa.
public struct FreeformCanvas: View {
    private let outfit: Outfit
    private let store: ImageStore

    @Environment(\.modelContext) private var modelContext
    /// La selección la pone el anfitrión.
    ///
    /// Es lo que permite que la pantalla cambie la bandeja de abajo por las
    /// herramientas del elemento cogido: si viviera aquí dentro, nadie fuera
    /// podría saber si hay algo seleccionado sin que el canvas se lo contara.
    private let selection: CanvasSelection
    /// Lo pintado encima, si esta pantalla deja pintar.
    ///
    /// Opcional porque no todas lo dejan: el día del plan y la rejilla enseñan
    /// el lienzo sin poder tocarlo, y pasarles una capa de pintura viva sería
    /// darles un estado que no van a usar.
    private let drawing: CanvasDrawing?
    @State private var masks: MaskCache

    public init(
        outfit: Outfit,
        store: ImageStore,
        selection: CanvasSelection,
        drawing: CanvasDrawing? = nil
    ) {
        self.outfit = outfit
        self.store = store
        self.selection = selection
        self.drawing = drawing
        _masks = State(initialValue: MaskCache(store: store))
    }

    public var body: some View {
        #if DEBUG
        let _ = Self._logChanges()
        #endif
        return GeometryReader { proxy in
            let scale = CanvasSpace.scaleToFit(in: proxy.size)
            ZStack {
                // El papel, **detrás de todo**, es quien deselecciona.
                //
                // Con el toque puesto en el contenedor entero, tocar otra
                // prenda disparaba las dos cosas: la prenda se seleccionaba y
                // el contenedor la deselectaba acto seguido, así que cambiar de
                // prenda acababa sin ninguna. Detrás, el toque solo llega aquí
                // cuando de verdad no ha habido nada delante — y eso incluye
                // las zonas transparentes de un recorte, que es lo correcto.
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { selection.clear() }
                    .allowsHitTesting(!(drawing?.isActive ?? false))

                // `visibleItems` y no `items`: una prenda marcada para
                // borrar sigue colocada en el outfit —a propósito, por si
                // vuelve— pero no se pinta. Ver `SoftDeletion.swift`.
                ForEach(outfit.visibleItems) { item in
                    CanvasGarmentItem(
                        item: item,
                        isSelected: selection.isSelected(item.id),
                        isDimmed: selection.selectedID != nil && !selection.isSelected(item.id),
                        canvasScale: scale,
                        store: store,
                        masks: masks,
                        onSelect: { selection.select(item.id) },
                        onCentering: { selection.centering = $0 }
                    )
                }
                // Mientras se pinta, las prendas no responden: el mismo
                // arrastre pintaría la raya **y** movería la prenda de debajo.
                .allowsHitTesting(!(drawing?.isActive ?? false))

                // **Sin guías de centrado.** Se quedan comentadas, no
                // borradas: el imán sigue funcionando —centrar a ojo acaba
                // centrado de verdad, y el háptico lo confirma—, lo que ya no
                // se dibuja son las dos líneas cruzando el papel.
                //
                // CanvasCenteringGuides(centering: selection.centering)
                // .allowsHitTesting(false)

                // **La pintura, encima de todo.** Es una anotación sobre el
                // conjunto —para rodear, tachar, apuntar— y no un elemento
                // más: por eso no se selecciona ni se mueve con las prendas.
                // **Lo pintado se ve siempre.** Con capa viva en el editor,
                // y estática en todas las demás pantallas: el plan, la rejilla
                // y la maleta también enseñan el lienzo, y sin esto lo que
                // dibujaste desaparecía en cuanto salías de editar.
                Group {
                    if let drawing {
                        CanvasDrawingLayer(drawing: drawing)
                    } else {
                        CanvasStrokesView(strokes: CanvasDrawing.decode(outfit.drawingData))
                    }
                }
                .frame(width: CanvasSpace.width, height: CanvasSpace.height)
                // Por encima de todo, sin excepción: ver
                // `CanvasItemMetrics.drawingZIndex`.
                .zIndex(CanvasItemMetrics.drawingZIndex)
            }
            .frame(width: CanvasSpace.width, height: CanvasSpace.height)
            // El único `scaleEffect` de toda la jerarquía. Lo que se persiste
            // no depende del tamaño de la vista, así que el outfit se ve igual
            // en un iPhone SE y en un iPad, y vuelve exacto.
            .scaleEffect(scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            // La retícula va **fuera** de la capa escalada, a tamaño de
            // pantalla. Dentro se escalaba con el lienzo, así que los puntos
            // del editor salían de otro tamaño que los de la pantalla de
            // planificar — y es literalmente el mismo papel.
            .background(alignment: .center) {
                DotGridBackground()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        // Y otra vez en el contenedor, para las franjas de fuera del lienzo:
        // el papel es 1000×1400 y la pantalla no tiene esa proporción, así que
        // quedan bandas a los lados o arriba que no pertenecen a la capa. Sin
        // esto, deseleccionar fallaba "a veces" — dependía de dónde cayera el
        // dedo.
        .contentShape(.rect)
        .onTapGesture { selection.clear() }
        // **Sin fondo propio.** El color del lienzo lo decide quien lo aloja:
        // el día del plan, la maleta o el editor. Pintarlo aquí tapaba el color
        // elegido con un blanco fijo, y por eso cambiar el color del outfit no
        // se veía por ninguna parte.
    }
}

/// Una prenda del canvas: junta imagen, máscara y persistencia.
///
/// Vista aparte porque necesita cargar su miniatura, y meter esa carga en
/// `FreeformCanvas` le daría estado al contenedor.
private struct CanvasGarmentItem: View {
    let item: CanvasItem
    let isSelected: Bool
    let isDimmed: Bool
    let canvasScale: Double
    let store: ImageStore
    let masks: MaskCache
    let onSelect: () -> Void
    var onCentering: (CanvasMath.Centering) -> Void = { _ in }

    /// Qué elemento no se dibuja porque se está editando en otra pantalla.
    @Environment(\.canvasHiddenItemID) private var hiddenItemID

    var body: some View {
        #if DEBUG
        let _ = Self._logChanges()
        #endif
        let key = item.garment?.normalizedImageKey ?? ""
        // Escondido mientras se edita en otra pantalla: si no, se ve dos veces
        // —el de aquí quieto y el del editor cambiando—. Ver
        // `canvasHiddenItemID`.
        let isHidden = hiddenItemID == AnyHashable(item.persistentModelID)

        CanvasItemView(
            transform: item.transform,
            isSelected: isSelected,
            isDimmed: isDimmed,
            canvasScale: canvasScale,
            mask: item.sticker == nil ? masks.mask(for: key) : nil,
            onSelect: onSelect,
            // Una sola escritura, al soltar. Durante el gesto no se toca la
            // base de datos.
            onCommit: { item.apply($0) },
            onCentering: onCentering
        ) {
            CanvasItemContent(item: item, store: store)
                .scaleEffect(x: item.isFlipped ? -1 : 1)
                .opacity(isHidden ? 0 : 1)
        }
        // Un sticker no tiene máscara alfa que cargar: es una caja, y su forma
        // de toque es su rectángulo.
        .task(id: key) { if item.sticker == nil { masks.load(key: key) } }
    }
}

/// Lo que va dentro de la caja: una prenda o un sticker.
///
/// `CanvasItemView` no sabe cuál de los dos es —mueve, gira y apila una caja y
/// nada más—, y por eso un sticker se manipula exactamente igual que una
/// prenda sin duplicar una línea de gestos.
private struct CanvasItemContent: View {
    let item: CanvasItem
    let store: ImageStore

    var body: some View {
        if let sticker = item.sticker {
            CanvasStickerView(sticker: sticker, store: store)
        } else {
            StoredImage(
                key: item.garment?.normalizedImageKey ?? "",
                variant: .display,
                store: store
            )
        }
    }
}


// /// Las líneas del medio del papel.
// ///
// /// Aparecen solo mientras algo está centrado y se van al soltar: una guía
// /// permanente sería una retícula más, y lo que dice esto no es "aquí está el
// /// medio" sino "lo que llevas en el dedo está en el medio".
// struct CanvasCenteringGuides: View {
//     let centering: CanvasMath.Centering
// 
//     var body: some View {
//         ZStack {
//             if centering.vertically {
//                 Rectangle()
//                     .fill(WK.Palette.accent)
//                     .frame(height: 1)
//                     .transition(.opacity)
//             }
//             if centering.horizontally {
//                 Rectangle()
//                     .fill(WK.Palette.accent)
//                     .frame(width: 1)
//                     .transition(.opacity)
//             }
//         }
//         .frame(width: CanvasSpace.width, height: CanvasSpace.height)
//         .animation(WKAnimation.selection, value: centering)
//         // Un toque al enganchar: es lo que confirma el imán sin tener que
//         // mirar si la línea ha salido.
//         .sensoryFeedback(.selection, trigger: centering)
//     }
// }
