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
    /// Las burbujas de lo seleccionado. Ver `CanvasBubble`.
    private let bubbles: (CanvasItem) -> [CanvasBubble]
    @State private var masks: MaskCache
    /// La última escala con la que se pintó de verdad.
    @State private var lastScale: Double = 1

    public init(
        outfit: Outfit,
        store: ImageStore,
        selection: CanvasSelection,
        drawing: CanvasDrawing? = nil,
        bubbles: @escaping (CanvasItem) -> [CanvasBubble] = { _ in [] }
    ) {
        self.outfit = outfit
        self.store = store
        self.selection = selection
        self.drawing = drawing
        self.bubbles = bubbles
        _masks = State(initialValue: MaskCache(store: store))
    }

    public var body: some View {
        #if DEBUG
        let _ = Self._logChanges()
        #endif
        return GeometryReader { proxy in
            // La última escala buena mientras el hueco no mide nada: en un
            // iPad que cambia de tamaño se proponen ceros durante un
            // fotograma, y a escala cero desaparece el lienzo entero —papel y
            // prendas—. Ver `LookCanvasView`, que tiene el mismo guardia.
            let measured = CanvasSpace.scaleToFit(in: proxy.size)
            let scale = measured > 0 ? measured : lastScale
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
                        // Coger y soltar con el mismo gesto: si ya está
                        // cogida, tocarla la suelta. Ver `Live.isTap`.
                        onSelect: {
                            if selection.isSelected(item.id) {
                                selection.clear()
                            } else {
                                selection.select(item.id)
                            }
                        },
                        onCentering: { selection.centering = $0 },
                        // Solo el seleccionado cuenta: es el que lleva
                        // burbujas.
                        onLive: { live in
                            if selection.isSelected(item.id) { selection.liveTransform = live }
                        }
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
            .onChange(of: measured, initial: true) { _, newValue in
                guard newValue > 0, newValue != lastScale else { return }
                lastScale = newValue
            }
            // La retícula va **fuera** de la capa escalada, a tamaño de
            // pantalla. Dentro se escalaba con el lienzo, así que los puntos
            // del editor salían de otro tamaño que los de la pantalla de
            // planificar — y es literalmente el mismo papel.
            .background(alignment: .center) {
                DotGridBackground()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            // Las burbujas, **a tamaño de pantalla** y fuera de la capa
            // escalada: dentro saldrían del tamaño que tuviera el lienzo.
            .overlay(alignment: .bottom) {
                CanvasBubbleLayer(
                    outfit: outfit,
                    selection: selection,
                    bubbles: bubbles,
                    size: proxy.size,
                    scale: scale
                )
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

/// La capa de burbujas, **vista propia**: es la única que lee dónde está lo
/// seleccionado mientras se mueve, así que seguir al dedo la reevalúa a ella
/// sola y no al lienzo entero.
private struct CanvasBubbleLayer: View {
    let outfit: Outfit
    let selection: CanvasSelection
    let bubbles: (CanvasItem) -> [CanvasBubble]
    let size: CGSize
    let scale: Double

    /// Cuánto miden, para ponerlas al lado sin salirse de la pantalla.
    @State private var bubblesSize: CGSize = .zero

    var body: some View {
        bubbleLayer(in: size, scale: scale)
    }

    /// **Las burbujas, al lado de lo seleccionado**: a su derecha si cabe, si
    /// no a su izquierda, y a la altura de su centro. De cristal y dentro de un
    /// contenedor, así que aparecen fundiéndose. **Siguen a la foto** mientras
    /// la mueves, giras o escalas: ver `CanvasSelection.liveTransform`.
    @ViewBuilder
    private func bubbleLayer(in size: CGSize, scale: Double) -> some View {
        let item = selection.selectedID.flatMap { id in outfit.visibleItems.first { $0.id == id } }
        let list = item.map(bubbles) ?? []
        AdaptiveGlassContainer(spacing: WK.Spacing.s) {
            if let item, !list.isEmpty {
                // **Quietas, abajo en el centro**, encima de la barra de
                // herramientas: pegadas a la foto la perseguían, caían donde
                // va el segundo dedo y tapaban lo que movías.
                // let t = selection.liveTransform ?? item.transform
                // // Media anchura y media altura de la caja ya girada, en
                // // pantalla.
                // let cosine = abs(cos(t.rotation)), sine = abs(sin(t.rotation))
                // let halfWidth = (cosine * t.baseWidth + sine * t.baseHeight) / 2 * t.scale * scale
                // let halfHeight = (sine * t.baseWidth + cosine * t.baseHeight) / 2 * t.scale * scale
                // let centerX = (t.x - CanvasSpace.width / 2) * scale + size.width / 2
                // let centerY = (t.y - CanvasSpace.height / 2) * scale + size.height / 2
                // let gap: CGFloat = 10
                // let margin = WK.Spacing.s
                // let right = centerX + halfWidth + gap
                // let left = centerX - halfWidth - gap - bubblesSize.width
                // // **Al lado si cabe; si no, debajo** —o encima—: encima de la
                // // foto tapaba justo lo que se va a recortar.
                // let placement: CGPoint = {
                //     if right + bubblesSize.width <= size.width - margin {
                //         return CGPoint(x: right, y: centerY - bubblesSize.height / 2)
                //     }
                //     if left >= margin {
                //         return CGPoint(x: left, y: centerY - bubblesSize.height / 2)
                //     }
                //     let below = centerY + halfHeight + gap
                //     let y = below + bubblesSize.height <= size.height - margin
                //         ? below
                //         : centerY - halfHeight - gap - bubblesSize.height
                //     return CGPoint(x: centerX - bubblesSize.width / 2, y: y)
                // }()
                // let x = min(max(margin, placement.x), size.width - bubblesSize.width - margin)
                // let y = min(max(margin, placement.y), size.height - bubblesSize.height - margin)

                VStack(alignment: .leading, spacing: WK.Spacing.s) {
                    ForEach(list) { bubble in
                        CanvasBubbleButton(bubble: bubble)
                    }
                }
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { bubblesSize = $0 }
                // .offset(x: x, y: y)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, WK.Spacing.m)
                // **Mientras la mueves, no se tocan.** Van pegadas a la foto,
                // justo donde cae el segundo dedo al pellizcar: se quedaban
                // el toque, el gesto se cancelaba a medias y hasta saltaba
                // "Separar sujeto" solo.
                .allowsHitTesting(selection.liveTransform == nil)
                .opacity(selection.liveTransform == nil ? 1 : 0.55)
            }
        }
        .animation(.smooth(duration: 0.35), value: selection.selectedID)
    }
}

/// **Algo que hacer con lo seleccionado**, en una burbuja a su lado. Quien
/// aloja el lienzo decide cuáles hay: el lienzo solo las coloca.
public struct CanvasBubble: Identifiable {
    public let id: String
    public let symbol: String
    public let title: String
    /// Trabajando: la burbuja enseña que está en ello y no se deja tocar.
    public var isWorking: Bool
    public let action: () -> Void

    public init(id: String, symbol: String, title: String, isWorking: Bool = false, action: @escaping () -> Void) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.isWorking = isWorking
        self.action = action
    }
}

/// Una burbuja: cristal interactivo que entra con la transición del cristal.
private struct CanvasBubbleButton: View {
    let bubble: CanvasBubble

    var body: some View {
        Button(action: bubble.action) {
            HStack(spacing: 6) {
                if bubble.isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: bubble.symbol)
                }
                Text(bubble.title)
            }
            .font(WK.Font.captionMedium)
            .foregroundStyle(WK.Palette.primaryText)
            .padding(.horizontal, WK.Spacing.m)
            .padding(.vertical, WK.Spacing.s + 2)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(bubble.isWorking)
        .adaptiveGlassInteractive(in: .capsule)
        .adaptiveGlassTransition()
        .animation(WKAnimation.content, value: bubble.isWorking)
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
    var onLive: (ItemTransform?) -> Void = { _ in }

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
            onCentering: onCentering,
            onLive: onLive
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
