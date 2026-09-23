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

    /// Dónde cae cada prenda. Se calcula una vez por conjunto y no por
    /// fotograma: es aritmética barata, pero dentro del `body` se repetiría en
    /// cada scroll.
    private var placed: [(garment: Garment, transform: ItemTransform)] {
        let ordered = garments.sorted {
            StylistRole($0.kind).sortOrder < StylistRole($1.kind).sortOrder
        }
        let layout = OutfitAssembly.transforms(for: ordered.map { $0.kind })
        return zip(ordered, layout).map { (garment: $0, transform: $1) }
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = CanvasSpace.scaleToFit(in: proxy.size)
            ZStack {
                backdrop
                DotGridBackground(spacing: CanvasSpace.gridSpacing * 3)
                    .opacity(0.5)

                ForEach(placed, id: \.garment.id) { entry in
                    LookGarmentImage(garment: entry.garment, transform: entry.transform, store: store)
                }
            }
            .frame(width: CanvasSpace.width, height: CanvasSpace.height)
            .scaleEffect(scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(CanvasSpace.width / CanvasSpace.height, contentMode: .fit)
        .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
    }
}

/// Una prenda de la tarjeta. Vista propia para que cargar su imagen no dé
/// estado a la tarjeta entera.
private struct LookGarmentImage: View {
    let garment: Garment
    let transform: ItemTransform
    let store: ImageStore

    var body: some View {
        StoredImage(
            key: garment.normalizedImageKey,
            variant: .display,
            store: store,
            shadow: .init(opacity: 0.5, radius: 18, y: 11)
        )
        .frame(width: transform.baseWidth, height: transform.baseHeight)
        .scaleEffect(transform.scale)
        .rotationEffect(.radians(transform.rotation))
        .position(x: transform.x, y: transform.y)
        .zIndex(transform.zIndex)
    }
}
