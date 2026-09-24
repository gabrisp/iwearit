import SwiftUI
import UIKit
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// Lo que sale de la app —una prueba, un outfit— **con la marca "Snazzy"
/// abajo a la derecha**, siempre.
///
/// Se dibuja con `UIGraphicsImageRenderer` y no con `ImageRenderer` de
/// SwiftUI: las prendas se cargan de disco de forma asíncrona, y un
/// `ImageRenderer` pinta lo que haya en ese instante —el papel vacío—. Aquí se
/// cargan primero y se dibujan después.
enum SnazzyExport {

    /// **Todo lo exportado, en 3:4 vertical y del mismo tamaño**: pruebas y
    /// lienzos se ven iguales una al lado de otra en el carrete o en un post.
    static let size = CGSize(width: 1200, height: 1600)

    // MARK: Pruebas

    /// Una prueba lista para compartir.
    ///
    /// - Parameter paper: el color del outfit si la prueba es "sin fondo": la
    ///   persona recortada va sola sobre el papel, como en la app. `nil` para
    ///   las escenas, que ya traen su fondo.
    static func tryOn(_ image: UIImage, paper: UIColor?) -> UIImage {
        let size = Self.size
        let bounds = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if let paper {
                // Sin fondo: la persona entera, encajada sobre el papel.
                drawPaper(paper, in: bounds, dotSpacing: size.width / 18, in: context.cgContext)
                image.draw(in: fit(image.size, in: bounds.insetBy(dx: 0, dy: size.height * 0.03)))
            } else {
                // Con escena: la foto llena el 3:4, recortada al centro si
                // no viniera exacta.
                image.draw(in: fill(image.size, in: bounds))
            }
            // Sobre el papel, oscura si es claro; sobre una escena, blanca.
            drawWatermark(in: CGRect(origin: .zero, size: size), onLight: paper.map(isLight) ?? false)
        }
    }

    // MARK: Outfits

    /// Algo del lienzo listo para dibujar: su imagen, dónde va y cómo.
    private struct Piece {
        let image: CGImage
        let transform: ItemTransform
        let isFlipped: Bool
        /// Las prendas llevan sombra, para que no parezcan pegatinas; los
        /// stickers no, como en el lienzo.
        let hasShadow: Bool
        /// Las fotos van recortadas en redondo, como en `CanvasStickerView`.
        let cornerRadius: CGFloat?
    }

    /// El lienzo de un outfit **entero** —prendas, fecha, tiempo, textos,
    /// fotos y pruebas— en 3:4 y con la marca. Lo que se ve en la tarjeta es
    /// lo que sale: si algo del lienzo faltara en lo exportado, no sería ese
    /// outfit.
    static func outfit(_ outfit: Outfit, backdrop: UIColor, store: ImageStore) async -> UIImage? {
        let elements: [Element] = outfit.items.compactMap { item in
            if let sticker = item.sticker { return .sticker(sticker, item.transform, flipped: item.isFlipped) }
            guard let garment = item.garment, garment.deletedAt == nil else { return nil }
            return .garment(garment, item.transform, flipped: item.isFlipped)
        }
        return await canvas(
            elements,
            strokes: CanvasDrawing.decode(outfit.drawingData),
            backdrop: backdrop,
            store: store
        )
    }

    /// Una propuesta de la inspiración que aún no es un outfit: sus prendas,
    /// colocadas como en la tarjeta. Ver `LookCanvasView.layout`.
    static func look(_ garments: [Garment], seed: UInt64, backdrop: UIColor, store: ImageStore) async -> UIImage? {
        let elements = LookCanvasView.layout(garments, seed: seed).map {
            Element.garment($0.garment, $0.transform, flipped: false)
        }
        return await canvas(elements, strokes: [], backdrop: backdrop, store: store)
    }

    /// Lo que hay en un lienzo.
    private enum Element {
        case garment(Garment, ItemTransform, flipped: Bool)
        case sticker(CanvasSticker, ItemTransform, flipped: Bool)

        var transform: ItemTransform {
            switch self {
            case let .garment(_, transform, _), let .sticker(_, transform, _): transform
            }
        }

        /// Dado la vuelta en el editor. Ver `CanvasEditing.flip`.
        var isFlipped: Bool {
            switch self {
            case let .garment(_, _, flipped), let .sticker(_, _, flipped): flipped
            }
        }
    }

    private static func canvas(
        _ elements: [Element], strokes: [CanvasStroke], backdrop: UIColor, store: ImageStore
    ) async -> UIImage? {
        let canvas = CGSize(width: CanvasSpace.width, height: CanvasSpace.height)
        let output = Self.size
        // El lienzo entero encajado en el 3:4; el papel sigue por los lados.
        let placed = fit(canvas, in: CGRect(origin: .zero, size: output))
        let scale = placed.width / canvas.width

        // Todo cargado **antes** de dibujar, y en el orden del lienzo: un
        // sticker puede ir debajo de una prenda y encima de otra.
        var pieces: [Piece] = []
        // `sorted` es estable: a igual `zIndex`, el orden de siempre.
        for element in elements.sorted(by: { $0.transform.zIndex < $1.transform.zIndex }) {
            let transform = element.transform
            switch element {
            case let .sticker(sticker, _, _):
                guard let image = await stickerImage(sticker, transform: transform, scale: scale, store: store) else { continue }
                let isPhoto = if case .photo = sticker { true } else { false }
                pieces.append(Piece(image: image, transform: transform, isFlipped: element.isFlipped, hasShadow: false, cornerRadius: isPhoto ? 18 : nil))
            case let .garment(garment, _, _):
                // La versión de catálogo si existe, que es la que se ve en la
                // app. Ver `StoredImage`.
                let key = garment.normalizedImageKey
                let variant: ImageStore.Variant = await store.hasCatalog(for: key) ? .catalog : .display
                guard let image = try? await store.image(for: key, variant: variant) else { continue }
                pieces.append(Piece(image: image, transform: transform, isFlipped: element.isFlipped, hasShadow: true, cornerRadius: nil))
            }
        }

        // **Lo pintado a mano**, encima de todo como en el lienzo. Con la
        // misma vista que lo pinta allí: ver `CanvasStrokesView`.
        var drawing: CGImage?
        if !strokes.isEmpty {
            let renderer = ImageRenderer(
                content: CanvasStrokesView(strokes: strokes).frame(width: canvas.width, height: canvas.height)
            )
            renderer.scale = scale
            drawing = renderer.cgImage
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: output, format: format).image { context in
            let cg = context.cgContext
            drawPaper(backdrop, in: CGRect(origin: .zero, size: output), dotSpacing: CanvasSpace.gridSpacing * 3 * scale, in: cg)
            cg.translateBy(x: placed.minX, y: placed.minY)
            cg.scaleBy(x: scale, y: scale)

            for piece in pieces {
                let transform = piece.transform
                let box = CGSize(width: transform.baseWidth, height: transform.baseHeight)
                let fitted = aspectFit(
                    CGSize(width: piece.image.width, height: piece.image.height), in: box
                )
                cg.saveGState()
                cg.translateBy(x: transform.x, y: transform.y)
                cg.rotate(by: transform.rotation)
                cg.scaleBy(x: transform.scale, y: transform.scale)
                // Dado la vuelta, como en el editor: el espejo va dentro de
                // la caja, después de girarla.
                if piece.isFlipped { cg.scaleBy(x: -1, y: 1) }
                if piece.hasShadow {
                    // La sombra de siempre, para que no parezcan pegatinas.
                    cg.setShadow(offset: CGSize(width: 0, height: 11), blur: 36, color: UIColor.black.withAlphaComponent(0.5).cgColor)
                }
                if let radius = piece.cornerRadius {
                    // Como en el lienzo: la caja del sticker, redondeada.
                    let frame = CGRect(x: -box.width / 2, y: -box.height / 2, width: box.width, height: box.height)
                    cg.addPath(UIBezierPath(roundedRect: frame, cornerRadius: radius).cgPath)
                    cg.clip()
                }
                UIImage(cgImage: piece.image).draw(
                    in: CGRect(x: -fitted.width / 2, y: -fitted.height / 2, width: fitted.width, height: fitted.height)
                )
                cg.restoreGState()
            }

            if let drawing {
                UIImage(cgImage: drawing).draw(in: CGRect(origin: .zero, size: canvas))
            }

            // La marca, en las coordenadas del 3:4 y no del lienzo.
            cg.scaleBy(x: 1 / scale, y: 1 / scale)
            cg.translateBy(x: -placed.minX, y: -placed.minY)
            drawWatermark(in: CGRect(origin: .zero, size: output), onLight: isLight(backdrop))
        }
    }

    /// Un sticker hecho imagen.
    ///
    /// Las fotos —las pruebas incluidas— se leen de disco tal cual. El resto
    /// —fecha, tiempo, texto— son vistas, y se pintan con **la misma vista**
    /// del lienzo: dibujarlas otra vez a mano acabaría en dos fechas que no se
    /// parecen.
    private static func stickerImage(
        _ sticker: CanvasSticker, transform: ItemTransform, scale: CGFloat, store: ImageStore
    ) async -> CGImage? {
        if case let .photo(key) = sticker {
            return try? await store.image(for: key, variant: .display)
        }
        let box = CGSize(width: transform.baseWidth, height: transform.baseHeight)
        let renderer = ImageRenderer(
            content: CanvasStickerView(sticker: sticker, store: store)
                .frame(width: box.width, height: box.height)
                .environment(\.colorScheme, .light)
        )
        // A la resolución a la que acaba dibujado, y un poco más: el texto
        // tiene que salir nítido.
        renderer.scale = max(1, transform.scale * scale) * 2
        return renderer.cgImage
    }

    // MARK: Dibujo

    /// La marca: "Snazzy". En blanco con sombra sobre fotos y fondos oscuros;
    /// en tinta sobre papel claro, donde el blanco no se leía.
    private static func drawWatermark(in bounds: CGRect, onLight: Bool) {
        let fontSize = max(16, bounds.width * 0.055)
        let font = UIFont(name: "PlusJakartaSans-Bold", size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .bold)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(onLight ? 0 : 0.35)
        shadow.shadowBlurRadius = fontSize * 0.3
        shadow.shadowOffset = CGSize(width: 0, height: fontSize * 0.06)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: onLight
                ? UIColor.black.withAlphaComponent(0.55)
                : UIColor.white.withAlphaComponent(0.92),
            .shadow: shadow,
            // Aire entre letras: aplastada, las letras se juntan y se montaban.
            .kern: fontSize * 0.06,
        ]
        let text = NSAttributedString(string: "Snazzy", attributes: attributes)
        let size = text.size()
        // **Aplastada**: ancha y baja, como un sello. Ver `SnazzyWatermark`.
        let squash = watermarkSquash
        let drawn = CGSize(width: size.width, height: size.height * squash)
        let margin = bounds.width * 0.04
        let origin = CGPoint(x: bounds.maxX - drawn.width - margin, y: bounds.maxY - drawn.height - margin)

        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.saveGState()
        cg.translateBy(x: origin.x, y: origin.y)
        cg.scaleBy(x: 1, y: squash)
        text.draw(at: .zero)
        cg.restoreGState()
    }

    /// Cuánto se aplasta la marca en vertical.
    static let watermarkSquash: CGFloat = 0.72

    /// El hueco que ocupa la marca, para no dibujar puntos debajo.
    private static func watermarkClearance(in bounds: CGRect) -> CGRect {
        let fontSize = max(16, bounds.width * 0.055)
        let width = fontSize * 4.6
        let height = fontSize * 1.3 * watermarkSquash
        let margin = bounds.width * 0.04
        return CGRect(
            x: bounds.maxX - width - margin, y: bounds.maxY - height - margin,
            width: width, height: height
        ).insetBy(dx: -fontSize * 0.6, dy: -fontSize * 0.5)
    }

    /// El papel de los lienzos: su color y la retícula de puntos.
    private static func drawPaper(_ color: UIColor, in rect: CGRect, dotSpacing: CGFloat, in cg: CGContext) {
        cg.setFillColor(color.cgColor)
        cg.fill(rect)
        let diameter = dotSpacing * 0.18
        cg.setFillColor(UIColor.black.withAlphaComponent(0.08).cgColor)
        let clear = watermarkClearance(in: rect)
        var y = dotSpacing
        while y < rect.maxY {
            var x = dotSpacing
            while x < rect.maxX {
                let dot = CGRect(x: x, y: y, width: diameter, height: diameter)
                if !clear.intersects(dot) { cg.fillEllipse(in: dot) }
                x += dotSpacing
            }
            y += dotSpacing
        }
    }

    /// Si un color es claro: por su luminancia percibida.
    static func isLight(_ color: UIColor) -> Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return true }
        return 0.299 * red + 0.587 * green + 0.114 * blue > 0.6
    }

    /// Un tamaño encajado entero dentro de un rectángulo, centrado.
    private static func fit(_ size: CGSize, in rect: CGRect) -> CGRect {
        let fitted = aspectFit(size, in: rect.size)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }

    /// Un tamaño que llena un rectángulo, centrado y desbordando lo justo.
    private static func fill(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let filled = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - filled.width / 2, y: rect.midY - filled.height / 2, width: filled.width, height: filled.height)
    }

    private static func aspectFit(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// La marca en pantalla, igual que en lo exportado.
struct SnazzyWatermark: View {
    /// Sobre papel claro, en tinta. Ver `SnazzyExport.drawWatermark`.
    var onLight = false

    var body: some View {
        Text("Snazzy")
            .font(.custom("PlusJakartaSans-Bold", size: 17, relativeTo: .footnote))
            .tracking(1)
            .foregroundStyle(onLight ? Color.black.opacity(0.55) : .white.opacity(0.92))
            .shadow(color: .black.opacity(onLight ? 0 : 0.35), radius: 4, y: 1)
            // Aplastada, como en lo exportado.
            .scaleEffect(x: 1, y: SnazzyExport.watermarkSquash, anchor: .bottomTrailing)
            .padding(WK.Spacing.m)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// La hoja de compartir del sistema, para una imagen ya preparada.
struct ShareImageSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
