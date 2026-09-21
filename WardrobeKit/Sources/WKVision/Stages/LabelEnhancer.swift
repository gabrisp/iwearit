import CoreGraphics
import Foundation
import WKCore

/// Deja la letra pequeña en condiciones de ser leída.
///
/// ## Por qué hace falta una segunda pasada
///
/// El OCR de Vision es bueno con un documento y regular con una etiqueta de
/// ropa, y no es culpa suya: la etiqueta ocupa el 2% del recorte, está impresa
/// en gris sobre blanco roto, arrugada, y a veces bordada del mismo color que
/// la tela. Con esos píxeles no hay reconocedor que valga.
///
/// Lo que sí se puede hacer es darle **más píxeles y más contraste**, que es
/// exactamente lo que le falta:
///
/// 1. **Ampliar.** Vision descarta las regiones de texto por debajo de cierta
///    altura en píxeles. Una etiqueta de 14 px de alto no se intenta siquiera;
///    la misma etiqueta a 42 px sí. Ampliar no inventa detalle, pero pone el
///    texto por encima del umbral con el detalle que ya había.
/// 2. **Estirar el contraste.** Se mide dónde están de verdad los tonos —el
///    percentil 5 y el 95, no el mínimo y el máximo, que los fija cualquier
///    píxel suelto— y se reparten sobre todo el rango. Un gris sobre blanco
///    roto se convierte en negro sobre blanco.
/// 3. **Tirar el color.** El color no ayuda a leer y sí estorba: una etiqueta
///    con tinta azul sobre tela crema tiene poquísimo contraste de luminancia
///    en un canal y mucho en otro. En gris, con el contraste ya estirado, se lee
///    igual de bien venga del canal que venga.
///
/// ## Cuándo se usa
///
/// **Solo si la primera pasada no leyó nada.** Ampliar a tres veces el tamaño y
/// recorrer el bitmap dos veces cuesta, y cuando el logo está bordado grande en
/// el pecho la primera pasada ya lo ha leído. Esto es para el caso en que no
/// hubo nada, que es justo donde gastar tiene sentido.
enum LabelEnhancer {

    /// A qué altura queremos el lado corto para que la letra sea legible.
    static let targetShortSide = 900

    /// Y hasta dónde se permite ampliar.
    ///
    /// Un tope, porque ampliar ocho veces una foto de 100 px no produce texto:
    /// produce manchas grandes y 40 ms de OCR tirados.
    static let maximumUpscale = 3.0

    /// Qué fracción de píxeles se sacrifica por cada extremo al estirar.
    static let clipFraction = 0.05

    /// La misma imagen, ampliada y en gris de alto contraste.
    ///
    /// - Returns: `nil` si no hay nada que ganar —ya es grande y ya tiene
    ///   contraste— para no pagar una segunda pasada de OCR por la misma foto.
    static func enhanced(_ image: CGImage) -> CGImage? {
        let shortSide = min(image.width, image.height)
        guard shortSide > 16 else { return nil }

        let scale = min(maximumUpscale, max(1, Double(targetShortSide) / Double(shortSide)))
        let width = Int(Double(image.width) * scale)
        let height = Int(Double(image.height) * scale)
        guard
            width > 0, height > 0, width * height <= 24_000_000,
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // --- Dónde están de verdad los tonos ---
        var histogram = [Int](repeating: 0, count: 256)
        for y in 0..<height {
            for x in 0..<width {
                histogram[Int(luminance(buffer, x, y))] += 1
            }
        }

        let total = width * height
        let margin = Int(Double(total) * clipFraction)
        var low = 0
        var high = 255
        var seen = 0
        for value in 0..<256 {
            seen += histogram[value]
            if seen > margin { low = value; break }
        }
        seen = 0
        for value in stride(from: 255, through: 0, by: -1) {
            seen += histogram[value]
            if seen > margin { high = value; break }
        }

        // Si el rango útil ya ocupa casi todo, estirarlo no aporta nada y solo
        // quemaría los extremos.
        guard high - low > 12 else { return nil }
        let span = Double(high - low)

        for y in 0..<height {
            for x in 0..<width {
                let stretched = (Double(luminance(buffer, x, y)) - Double(low)) / span
                let value = UInt8(max(0, min(255, stretched * 255)))
                buffer[x, y, 0] = value
                buffer[x, y, 1] = value
                buffer[x, y, 2] = value
                buffer[x, y, 3] = 255
            }
        }

        DiagnosticsLog.record(
            "MARCA",
            String(
                format: "etiqueta realzada: ×%.1f, tonos %d-%d estirados a 0-255",
                scale, low, high
            )
        )
        return context.makeImage()
    }

    /// Luminancia percibida. Los coeficientes son los de Rec. 709: el verde
    /// pesa el doble que el rojo porque el ojo ve así, y usar la media de los
    /// tres canales hunde el contraste de cualquier texto que no sea gris.
    private static func luminance(_ buffer: PixelBuffer, _ x: Int, _ y: Int) -> UInt8 {
        let red = Double(buffer[x, y, 0])
        let green = Double(buffer[x, y, 1])
        let blue = Double(buffer[x, y, 2])
        return UInt8(max(0, min(255, 0.2126 * red + 0.7152 * green + 0.0722 * blue)))
    }
}
