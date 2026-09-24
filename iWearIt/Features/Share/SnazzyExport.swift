import SwiftUI
import UIKit
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

    // MARK: Pruebas

    /// Una prueba lista para compartir.
    ///
    /// - Parameter paper: el color del outfit si la prueba es "sin fondo": la
    ///   persona recortada va sola sobre el papel, como en la app. `nil` para
    ///   las escenas, que ya traen su fondo.
    static func tryOn(_ image: UIImage, paper: UIColor?) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if let paper {
                drawPaper(paper, in: CGRect(origin: .zero, size: size), dotSpacing: size.width / 18, in: context.cgContext)
            }
            image.draw(in: CGRect(origin: .zero, size: size))
            // Sobre el papel, oscura si es claro; sobre una escena, blanca.
            drawWatermark(in: CGRect(origin: .zero, size: size), onLight: paper.map(isLight) ?? false)
        }
    }

    // MARK: Outfits

    /// El lienzo de un outfit, a su tamaño lógico —1000 × 1400— y con la marca.
    static func outfit(_ outfit: Outfit, backdrop: UIColor, store: ImageStore) async -> UIImage? {
        let canvas = CGSize(width: CanvasSpace.width, height: CanvasSpace.height)

        // Las prendas, cargadas **antes** de dibujar. La versión de catálogo si
        // existe, que es la que se ve en la app. Ver `StoredImage`.
        var pieces: [(image: CGImage, transform: ItemTransform)] = []
        let items = outfit.items
            .filter { $0.sticker == nil }
            .sorted { $0.transform.zIndex < $1.transform.zIndex }
        for item in items {
            guard let garment = item.garment, garment.deletedAt == nil else { continue }
            let key = garment.normalizedImageKey
            let variant: ImageStore.Variant = await store.hasCatalog(for: key) ? .catalog : .display
            guard let image = try? await store.image(for: key, variant: variant) else { continue }
            pieces.append((image, item.transform))
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            let cg = context.cgContext
            drawPaper(backdrop, in: CGRect(origin: .zero, size: canvas), dotSpacing: CanvasSpace.gridSpacing * 3, in: cg)

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
                // La sombra de siempre, para que no parezcan pegatinas.
                cg.setShadow(offset: CGSize(width: 0, height: 11), blur: 36, color: UIColor.black.withAlphaComponent(0.5).cgColor)
                UIImage(cgImage: piece.image).draw(
                    in: CGRect(x: -fitted.width / 2, y: -fitted.height / 2, width: fitted.width, height: fitted.height)
                )
                cg.restoreGState()
            }

            drawWatermark(in: CGRect(origin: .zero, size: canvas), onLight: isLight(backdrop))
        }
    }

    // MARK: Dibujo

    /// La marca: "Snazzy". En blanco con sombra sobre fotos y fondos oscuros;
    /// en tinta sobre papel claro, donde el blanco no se leía.
    private static func drawWatermark(in bounds: CGRect, onLight: Bool) {
        let fontSize = max(14, bounds.width * 0.045)
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
            .kern: fontSize * 0.02,
        ]
        let text = NSAttributedString(string: "Snazzy", attributes: attributes)
        let size = text.size()
        let margin = bounds.width * 0.04
        text.draw(at: CGPoint(x: bounds.maxX - size.width - margin, y: bounds.maxY - size.height - margin))
    }

    /// El papel de los lienzos: su color y la retícula de puntos.
    private static func drawPaper(_ color: UIColor, in rect: CGRect, dotSpacing: CGFloat, in cg: CGContext) {
        cg.setFillColor(color.cgColor)
        cg.fill(rect)
        let diameter = dotSpacing * 0.18
        cg.setFillColor(UIColor.black.withAlphaComponent(0.08).cgColor)
        var y = dotSpacing
        while y < rect.maxY {
            var x = dotSpacing
            while x < rect.maxX {
                cg.fillEllipse(in: CGRect(x: x, y: y, width: diameter, height: diameter))
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
            .font(.custom("PlusJakartaSans-Bold", size: 15, relativeTo: .footnote))
            .foregroundStyle(onLight ? Color.black.opacity(0.55) : .white.opacity(0.92))
            .shadow(color: .black.opacity(onLight ? 0 : 0.35), radius: 4, y: 1)
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
