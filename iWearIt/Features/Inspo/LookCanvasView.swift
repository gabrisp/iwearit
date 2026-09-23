import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// Un conjunto propuesto, pintado **como el lienzo lo pintaría**.
///
/// Mismo espacio lógico, mismos huecos y mismo reparto que al colocarlo de
/// verdad: lo que ves en la tarjeta es exactamente lo que se guarda si te
/// gusta. Una miniatura hecha aparte, con su propia colocación, sería enseñar
/// una cosa y guardar otra.
struct LookCanvasView: View {
    let garments: [Garment]
    let store: ImageStore
    var backdrop: Color = WK.Palette.canvas
    /// Cuando la propuesta ya es un outfit de verdad, **manda él**.
    ///
    /// Lo editado vuelve a la tarjeta de la que salió: si moviste la chaqueta
    /// y giraste la gorra, eso es lo que hay que ver aquí, no el reparto por
    /// huecos de la propuesta original.
    var outfit: Outfit?
    /// Un filo alrededor, para que se vea dónde empieza y dónde acaba.
    ///
    /// El fondo del lienzo es el mismo de la pantalla —a propósito: la ropa
    /// tiene que mandar—, y sin borde un conjunto flota sin que se sepa cuánto
    /// papel ocupa ni dónde acaba uno y empieza el siguiente.
    var showsBorder = false
    /// Tocar una prenda para ver **qué prenda es**.
    ///
    /// Sin esto, la tarjeta enseña un conjunto y no dice de qué está hecho: la
    /// chaqueta que te gusta es una silueta a la que no le puedes preguntar
    /// nada —ni cuál de las tres parecidas es, ni de qué marca—. Con esto, la
    /// tarjeta es el armario visto desde otro sitio.
    ///
    /// Opcional a propósito: donde el lienzo es una miniatura —una celda de
    /// rejilla, una tarjeta de chat— no hay sitio para acertar una prenda con
    /// el dedo, y el toque solo estorbaría al scroll.
    var onSelectGarment: ((Garment) -> Void)?
    /// Qué hace el doble toque **sobre una prenda**.
    ///
    /// Hay que pasarlo aquí y no dejarlo en la tarjeta de fuera: en cuanto la
    /// prenda escucha el toque simple, el doble toque de la tarjeta ya no
    /// llega a lo que hay pintado, solo al papel de alrededor.
    var onDoubleTap: (() -> Void)?

    /// La última escala con la que se pintó de verdad. Ver el cuerpo.
    @State private var lastScale: CGFloat = 1
    /// Las siluetas para acertar el toque. Solo si hay algo que tocar: con el
    /// lienzo mudo es trabajo —decodificar cada prenda y recorrerla— para
    /// nada.
    @State private var masks: MaskCache?
    /// Dónde cae cada prenda. Se calcula una vez por conjunto y no por
    /// fotograma: es aritmética barata, pero dentro del `body` se repetiría en
    /// cada scroll.
    private var placed: [(garment: Garment, transform: ItemTransform)] {
        if let outfit {
            return outfit.items
                .filter { $0.sticker == nil }
                .compactMap { item in
                    guard let garment = item.garment, garment.deletedAt == nil else { return nil }
                    return (garment: garment, transform: item.transform)
                }
        }
        let ordered = garments.sorted {
            StylistRole($0.kind).sortOrder < StylistRole($1.kind).sortOrder
        }
        let layout = OutfitAssembly.transforms(for: ordered.map { $0.kind })
        return zip(ordered, layout).map { (garment: $0, transform: $1) }
    }

    var body: some View {
        GeometryReader { proxy in
            // **El último tamaño bueno manda.**
            //
            // Un hueco de cero puntos —que es lo que se propone durante un
            // cambio de tamaño en el iPad, o mientras una transición coloca la
            // tarjeta— da escala cero, y a escala cero el lienzo entero
            // desaparece: fondo, papel y prendas. Quedarse con la escala
            // anterior mientras dura ese fotograma es la diferencia entre una
            // tarjeta que parpadea y una que se queda en blanco.
            let measured = CanvasSpace.scaleToFit(in: proxy.size)
            let scale = measured > 0 ? measured : lastScale
            ZStack {
                backdrop
                DotGridBackground(spacing: CanvasSpace.gridSpacing * 3)
                    .opacity(0.5)

                ForEach(placed, id: \.garment.id) { entry in
                    LookGarmentImage(
                        garment: entry.garment,
                        transform: entry.transform,
                        store: store,
                        masks: masks,
                        onSelect: onSelectGarment.map { select in { select(entry.garment) } },
                        onDoubleTap: onDoubleTap
                    )
                }
            }
            .frame(width: CanvasSpace.width, height: CanvasSpace.height)
            .scaleEffect(scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .onChange(of: measured, initial: true) { _, newValue in
                guard newValue > 0, newValue != lastScale else { return }
                lastScale = newValue
            }
        }
        .task {
            guard onSelectGarment != nil, masks == nil else { return }
            masks = MaskCache(store: store)
        }
        .aspectRatio(CanvasSpace.width / CanvasSpace.height, contentMode: .fit)
        .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
        .overlay {
            if showsBorder {
                RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
                    .stroke(WK.Palette.ink(0.12), lineWidth: 1)
            }
        }
    }
}

/// Una prenda de la tarjeta. Vista propia para que cargar su imagen no dé
/// estado a la tarjeta entera.
private struct LookGarmentImage: View {
    let garment: Garment
    let transform: ItemTransform
    let store: ImageStore
    var masks: MaskCache?
    var onSelect: (() -> Void)?
    var onDoubleTap: (() -> Void)?

    var body: some View {
        StoredImage(
            key: garment.normalizedImageKey,
            variant: .display,
            store: store,
            shadow: .init(opacity: 0.5, radius: 18, y: 11)
        )
        .frame(width: transform.baseWidth, height: transform.baseHeight)
        // **El área de toque es la silueta, no el rectángulo.** Una chaqueta
        // recortada tiene media esquina transparente: por bounding box, tocar
        // el hueco de al lado del cuello abriría la chaqueta en vez de la
        // camiseta que se ve debajo. Es la misma pieza que usa el editor.
        //
        // Antes de escalar y girar: así la silueta se transforma con la
        // prenda en lugar de quedarse quieta sobre ella.
        .modifier(GarmentTouchArea(mask: masks?.mask(for: garment.normalizedImageKey), isActive: onSelect != nil))
        .scaleEffect(transform.scale)
        .rotationEffect(.radians(transform.rotation))
        .position(x: transform.x, y: transform.y)
        .zIndex(transform.zIndex)
        .task(id: garment.normalizedImageKey) {
            guard onSelect != nil else { return }
            masks?.load(key: garment.normalizedImageKey)
        }
        // **El doble toque gana, y el simple espera.**
        //
        // Con dos `onTapGesture` encadenados no basta: el de un toque se lleva
        // el primer contacto y el doble no llega a formarse nunca, así que
        // desde una prenda no se podía entrar a editar. Un gesto exclusivo lo
        // dice de verdad — primero se intenta el de dos toques y el de uno
        // solo se resuelve cuando aquel ha fallado.
        .gesture(
            TapGesture(count: 2).onEnded { onDoubleTap?() }
                .exclusively(before: TapGesture().onEnded { onSelect?() })
        )
    }
}

/// El área de toque de una prenda: su silueta, o nada si el lienzo es mudo.
///
/// En un modificador y no suelto en la cadena porque `contentShape` **siempre**
/// define un área —también la vacía—, y aplicarlo donde no se escucha ningún
/// toque le robaría los gestos a lo que haya debajo.
private struct GarmentTouchArea: ViewModifier {
    let mask: AlphaMask?
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.contentShape(AnyShape(AlphaShape(mask: mask)))
        } else {
            content
        }
    }
}
