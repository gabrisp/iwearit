import CoreGraphics
import Foundation
import WKCore

/// Convierte un recorte en bruto en la imagen "de catálogo": una sola silueta,
/// derecha, con el borde limpio, centrada y siempre del mismo tamaño.
///
/// La coherencia importa más de lo que parece: si cada prenda trae su propio
/// margen, en la balda unas flotan y otras tocan el tablero. El contrato es
/// silueta ajustada con el margen que le toque a su categoría —ver `Profile`—,
/// y todo lo que entre al armario lo cumple.
///
/// Son tres pasos y cada uno arregla algo que se ve:
///
/// 1. **Despeckle** — se queda con la mancha grande y tira las demás. Una
///    máscara de segmentación siempre trae motas sueltas —un trozo de pared del
///    color de la camiseta, una sombra— y en la balda se ven como suciedad
///    flotando alrededor de la prenda.
/// 2. **Enderezar** — gira la silueta hasta poner su eje principal vertical.
///    Una foto tomada de lado deja la prenda torcida, y diez prendas torcidas
///    cada una en su ángulo es lo que hace que un armario parezca un cajón.
/// 3. **Encajar** — recorta a la silueta y la coloca en el lienzo de su
///    categoría: cuadrado para un top, 4:5 y colgada de arriba para un
///    pantalón, con más aire para un accesorio.
public enum CropNormalizer {

    /// Lado del lienzo cuando no se sabe qué prenda es.
    ///
    /// 1024 y no 768 porque es exactamente el tamaño de la variante `display`
    /// de `ImageStore`: normalizar más pequeño obligaba a estirar el recorte al
    /// mostrarlo en el detalle, y normalizar más grande era guardar píxeles que
    /// nadie llega a ver.
    public static let outputSide = 1024
    /// Margen alrededor de la silueta, como fracción del lado.
    public static let paddingFraction = 0.08

    // MARK: - Perfil por tipo de prenda

    /// Cómo se encaja cada tipo de prenda.
    ///
    /// **Por qué no vale un solo encaje para todo.** Un lienzo cuadrado con el
    /// mismo margen trata igual a una camiseta y a unos vaqueros, y no lo son:
    /// los vaqueros son el doble de altos que anchos, así que al meterlos en un
    /// cuadrado quedan como una tira estrecha en medio de dos franjas vacías —
    /// pequeños en la balda, pequeños en el lienzo, y con un hueco enorme
    /// alrededor que no dice nada.
    ///
    /// El perfil ajusta tres cosas: la proporción del lienzo, el margen, y por
    /// dónde se apoya la prenda. Y una cuarta que no se ve pero importa más:
    /// si se endereza o no.
    public struct Profile: Sendable {
        public let width: Int
        public let height: Int
        /// Margen, como fracción del lado **menor** del lienzo.
        public let padding: Double
        public let anchor: Anchor
        /// Si se aplica el enderezado por eje principal.
        public let deskews: Bool

        /// Dónde se apoya la prenda cuando le sobra sitio.
        public enum Anchor: Sendable {
            case center
            /// Colgada de arriba. Es como se ve una prenda en una percha y en
            /// un catálogo, y es lo que hace que una falda y un pantalón
            /// arranquen a la misma altura en vez de flotar cada uno a la suya.
            case top
        }

        public init(width: Int, height: Int, padding: Double, anchor: Anchor, deskews: Bool) {
            self.width = width
            self.height = height
            self.padding = padding
            self.anchor = anchor
            self.deskews = deskews
        }

        /// El lienzo cuadrado de siempre. Es lo que se usa cuando no se sabe
        /// qué prenda es: las rutas que no pasan por el segmentador no tienen
        /// categoría hasta después de normalizar.
        public static func square(side: Int = outputSide, padding: Double = paddingFraction) -> Profile {
            Profile(width: side, height: side, padding: padding, anchor: .center, deskews: true)
        }

        public static func profile(for kind: GarmentKind) -> Profile {
            switch kind {
            // Anchas y más o menos cuadradas: el cuadrado les va bien.
            case .upperBody, .outerLayer:
                Profile(width: 1024, height: 1024, padding: 0.08, anchor: .center, deskews: true)

            // **Altas.** Lienzo 4:5 y colgadas de arriba, que es como se ven
            // en una percha. Y sin enderezar: el eje principal de un pantalón
            // con las perneras abiertas apunta a cualquier sitio, así que el
            // enderezado lo tumba en vez de ponerlo recto.
            case .lowerBody, .wholeBody:
                Profile(width: 1024, height: 1280, padding: 0.08, anchor: .top, deskews: false)

            // El par entero como una sola cosa, con algo más de aire: dos
            // zapatos juntos llenan el lienzo a lo ancho y con el margen de una
            // camiseta quedan apretados contra el borde. Sin enderezar por la
            // misma razón que los pantalones — el eje de un par apunta a donde
            // apunten las punteras.
            case .feet:
                Profile(width: 1024, height: 1024, padding: 0.10, anchor: .center, deskews: false)

            // Pequeños y de formas muy distintas entre sí. Más margen porque
            // una gorra ocupando el 92% del lienzo al lado de una camiseta
            // ocupando el 84% parece más grande que la camiseta.
            case .head, .bag, .other:
                Profile(width: 1024, height: 1024, padding: 0.12, anchor: .center, deskews: true)
            }
        }
    }
    /// Cuánto se permite enderezar.
    ///
    /// Acotado a propósito: si una prenda sale con un eje principal casi
    /// horizontal —un cinturón, unas gafas— girarla 80 grados no la endereza,
    /// la tumba. Por encima de esto se deja como está.
    static let maximumDeskewDegrees = 22.0
    /// Fracción del área de la mancha mayor por debajo de la cual una mancha
    /// es basura.
    ///
    /// Generoso: un zapato fotografiado de frente puede partirse en dos
    /// manchas de tamaño parecido, y tirar una lo mutilaría.
    static let specklesFraction = 0.18

    /// Aplica la máscara al recorte y lo encaja en un lienzo cuadrado.
    ///
    /// - Parameters:
    ///   - image: el recorte con alfa ya aplicado.
    ///   - side: lado del lienzo de salida.
    public static func normalize(_ image: CGImage, side: Int = outputSide) -> CGImage? {
        normalize(image, profile: .square(side: side))
    }

    /// El encaje que le corresponde a esa categoría.
    ///
    /// Se llama con lo que dijo el segmentador, no con lo que acabe diciendo el
    /// embedder: la diferencia entre los dos es camiseta contra chaqueta, y las
    /// dos usan el mismo perfil.
    public static func normalize(_ image: CGImage, for kind: GarmentKind) -> CGImage? {
        normalize(image, profile: .profile(for: kind))
    }

    public static func normalize(_ image: CGImage, profile: Profile) -> CGImage? {
        // Cada paso devuelve `nil` cuando no hay nada que hacer, y entonces
        // se sigue con la imagen anterior. Así un fallo en la limpieza nunca
        // se lleva por delante el recorte entero.
        // Un solo análisis para las dos decisiones. Antes cada paso recorría
        // la máscara por su cuenta.
        guard let analysis = analyse(image) else {
            guard let bounds = opaqueBounds(of: image) else { return nil }
            return render(image, cropping: bounds, into: profile)
        }
        let cleaned = despeckled(image, using: analysis) ?? image
        let straight = profile.deskews
            ? (deskewed(cleaned, by: analysis.angle) ?? cleaned)
            : cleaned

        guard let bounds = opaqueBounds(of: straight) else { return nil }
        return render(straight, cropping: bounds, into: profile)
    }

    /// Caja mínima que contiene todos los píxeles no transparentes.
    ///
    /// Sin esto, el margen del 8% se mediría contra el rectángulo original —que
    /// puede ser casi todo transparente— y la prenda saldría diminuta.
    static func opaqueBounds(of image: CGImage, alphaThreshold: UInt8 = 12) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        guard
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where buffer[x, y, 3] > alphaThreshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: - Análisis de la silueta

    /// Lado máximo al que se analiza.
    ///
    /// **Todo el análisis se hace en pequeño.** Decidir qué manchas sobran y
    /// cuánto hay que girar no necesita resolución: son decisiones sobre la
    /// forma general, y a 256 píxeles la forma es la misma. Hacerlo a tamaño
    /// completo significaba recorrer más de un millón de píxeles varias veces
    /// por prenda, y eso se notaba —mucho— en un escaneo de galería.
    static let analysisSide = 256

    /// Lo que se saca de la máscara en **una sola pasada barata**.
    struct SilhouetteAnalysis {
        /// Etiqueta de componente por píxel, en la retícula reducida.
        let labels: [Int32]
        let width: Int
        let height: Int
        /// Qué componentes se conservan.
        let keep: Set<Int32>
        /// Cuánto falta para poner el eje principal vertical, en radianes.
        let angle: Double
        /// Si alguna componente se descarta. Si no, no hay que redibujar nada.
        let hasDiscardedComponents: Bool
    }

    static func analyse(_ image: CGImage) -> SilhouetteAnalysis? {
        let scale = min(
            1.0,
            Double(analysisSide) / Double(max(image.width, image.height))
        )
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard width > 2, height > 2 else { return nil }

        guard
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // La máscara de pertenencia, en bytes. El etiquetado vive en
        // `ConnectedComponents` porque lo necesita también el separador de
        // instancias: dos camisetas dobladas se distinguen exactamente igual
        // que una mota de suciedad, mirando qué píxeles se tocan.
        var mask = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where buffer[x, y, 3] > 12 {
                mask[row + x] = 1
            }
        }

        let labelled = ConnectedComponents.label(mask: mask, width: width, height: height)
        let labels = labelled.labels

        // Momentos de primer orden sobre **todos** los píxeles de la máscara:
        // los acumula el etiquetado, así que sumarlos aquí no vuelve a
        // recorrer nada.
        var count = 0.0, sumX = 0.0, sumY = 0.0
        for component in labelled.components {
            count += Double(component.pixelCount)
            sumX += component.sumX
            sumY += component.sumY
        }

        guard
            !labelled.components.isEmpty,
            count > 32,
            let largest = labelled.components.map(\.pixelCount).max()
        else { return nil }

        let threshold = Double(largest) * specklesFraction
        var keep: Set<Int32> = []
        for component in labelled.components where Double(component.pixelCount) >= threshold {
            keep.insert(component.label)
        }

        // Segundo orden, solo sobre lo que se conserva: incluir las motas que
        // vamos a tirar sesgaría el ángulo hacia ellas.
        let meanX = sumX / count
        let meanY = sumY / count
        var xx = 0.0, yy = 0.0, xy = 0.0
        for index in 0..<(width * height) {
            let label = labels[index]
            guard label > 0, keep.contains(label) else { continue }
            let dx = Double(index % width) - meanX
            let dy = Double(index / width) - meanY
            xx += dx * dx
            yy += dy * dy
            xy += dx * dy
        }

        let theta = 0.5 * atan2(2 * xy, xx - yy)
        let angle = theta > 0 ? theta - .pi / 2 : theta + .pi / 2

        return SilhouetteAnalysis(
            labels: labels,
            width: width,
            height: height,
            keep: keep,
            angle: angle,
            hasDiscardedComponents: keep.count < labelled.components.count
        )
    }

    // MARK: - Despeckle

    /// Borra las manchas pequeñas y deja las grandes.
    ///
    /// La decisión se toma en la retícula reducida y se **aplica** a tamaño
    /// completo: una pasada con una consulta por píxel, sin volver a etiquetar.
    static func despeckled(_ image: CGImage, using analysis: SilhouetteAnalysis) -> CGImage? {
        // Nada que tirar: ahorrarse el redibujado entero, que es una pasada
        // por más de un millón de píxeles.
        guard analysis.hasDiscardedComponents else { return nil }

        let width = image.width
        let height = image.height
        guard
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let scaleX = Double(analysis.width) / Double(width)
        let scaleY = Double(analysis.height) / Double(height)

        for y in 0..<height {
            let sourceY = min(analysis.height - 1, Int(Double(y) * scaleY))
            for x in 0..<width where buffer[x, y, 3] > 0 {
                let sourceX = min(analysis.width - 1, Int(Double(x) * scaleX))
                let label = analysis.labels[sourceY * analysis.width + sourceX]
                guard label == 0 || !analysis.keep.contains(label) else { continue }
                // A transparente. Se escribe el píxel entero: con alfa
                // premultiplicado, dejar el color y poner alfa 0 deja un
                // fantasma de color al volver a componer.
                for component in 0..<4 { buffer[x, y, component] = 0 }
            }
        }
        return context.makeImage()
    }

    // MARK: - Enderezar

    /// Gira la silueta hasta poner su eje principal vertical.
    ///
    /// El ángulo sale de los **momentos de segundo orden** de la máscara, que
    /// es el eje sobre el que la silueta está más estirada. No hace falta red
    /// neuronal: son tres sumas sobre una máscara de 256 píxeles de lado, y
    /// para una prenda —que es larga en una dirección— acierta.
    ///
    /// Con dos excepciones, que el perfil desactiva: **pantalones y calzado**.
    /// Un pantalón con las perneras abiertas y un par de zapatos con las
    /// punteras hacia fuera no tienen un eje principal que signifique nada, y
    /// enderezarlos por él los tuerce en vez de ponerlos rectos.
    static func deskewed(_ image: CGImage, by angle: Double) -> CGImage? {
        let degrees = angle * 180 / .pi
        guard abs(degrees) > 1.5, abs(degrees) <= maximumDeskewDegrees else { return nil }

        let width = Double(image.width)
        let height = Double(image.height)
        // El lienzo crece para que la silueta girada quepa entera; recortar lo
        // que sobra es trabajo del encaje final.
        let side = Int((width * abs(cos(angle)) + height * abs(sin(angle))).rounded(.up))
        let tall = Int((width * abs(sin(angle)) + height * abs(cos(angle))).rounded(.up))

        guard let context = CGContext(
            data: nil,
            width: side, height: tall,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: side, height: tall))
        context.translateBy(x: Double(side) / 2, y: Double(tall) / 2)
        context.rotate(by: -angle)
        context.draw(
            image,
            in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        )
        return context.makeImage()
    }

    // MARK: - 3. Borde
    //
    // **Pendiente a propósito.** Suavizar el alfa a mano exige desmultiplicar
    // el color, difuminar solo el canal alfa y volver a multiplicar: hacerlo a
    // medias arrastra el fondo hacia dentro de la prenda o deja un filete
    // oscuro en el contorno, que se ve peor que el borde dentado que intenta
    // arreglar. Con lo que ya hacen el despeckle y el enderezado el recorte
    // pasa; esto es pulido y merece hacerse bien, no rápido.

    // MARK: - 4. Encajar

    private static func render(_ image: CGImage, cropping bounds: CGRect, into profile: Profile) -> CGImage? {
        guard let cropped = image.cropping(to: bounds) else { return nil }

        let canvasWidth = CGFloat(profile.width)
        let canvasHeight = CGFloat(profile.height)
        // El margen se mide contra el lado **menor**. Contra cada lado por
        // separado, un lienzo 4:5 dejaría arriba y abajo un margen un 25% más
        // grande que a los lados, y el pantalón se vería flotando.
        let margin = min(canvasWidth, canvasHeight) * profile.padding
        let scale = min(
            (canvasWidth - 2 * margin) / bounds.width,
            (canvasHeight - 2 * margin) / bounds.height
        )
        let drawWidth = bounds.width * scale
        let drawHeight = bounds.height * scale

        guard let context = CGContext(
            data: nil,
            width: profile.width, height: profile.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: profile.width, height: profile.height))

        // CoreGraphics cuenta la `y` desde abajo, así que "colgada de arriba"
        // es la `y` **mayor**. Escribirlo al revés no da error: deja la prenda
        // apoyada en el suelo del lienzo, que parece un fallo de recorte.
        let y: CGFloat = switch profile.anchor {
        case .center: (canvasHeight - drawHeight) / 2
        case .top: canvasHeight - margin - drawHeight
        }

        context.draw(cropped, in: CGRect(
            x: (canvasWidth - drawWidth) / 2,
            y: y,
            width: drawWidth,
            height: drawHeight
        ))
        return context.makeImage()
    }
}
