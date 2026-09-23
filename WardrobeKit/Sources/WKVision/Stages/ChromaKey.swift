import CoreGraphics
import Foundation
import WKCore

/// Quita el fondo de croma de la imagen reconstruida.
///
/// ## Por qué croma y no blanco
///
/// La primera versión pedía la prenda sobre **blanco** y la recortaba
/// levantando el sujeto. Falla justo donde más duele: una camiseta blanca sobre
/// fondo blanco no tiene frontera que encontrar, y la sombra de estudio —gris,
/// no blanca— se queda dentro del recorte.
///
/// Con un magenta puro el problema desaparece, porque **no hay ropa magenta
/// pura**. `#FF00FF` está en la esquina del espacio de color: saturación
/// máxima, rojo y azul al tope y verde a cero. Una prenda rosa, por fucsia que
/// sea, tiene verde y no llega a esa esquina. Así el fondo se identifica por lo
/// que es y no por adivinar dónde acaba la prenda.
///
/// ## Las dos cosas que hay que hacer, no una
///
/// 1. **Recortar** — alfa a cero donde el píxel es fondo.
/// 2. **Quitar el derrame** — el magenta rebota en los bordes de la prenda y
///    deja un filete rosado alrededor. Se corrige bajando los canales rojo y
///    azul al nivel del verde en los píxeles del borde. Sin este paso, cada
///    prenda sale con un halo de color que se ve en cuanto se pone sobre un
///    lienzo claro.
public enum ChromaKey {

    /// El fondo que se le pide al modelo.
    public static let keyRed = 1.0
    public static let keyGreen = 0.0
    public static let keyBlue = 1.0

    /// Por debajo de esta distancia al croma, el píxel es fondo.
    ///
    /// Generoso porque el JPEG del modelo no devuelve el magenta exacto:
    /// comprime en 4:2:0 y los bordes del fondo llegan con el color desviado.
    /// Con un umbral estricto quedaba un marco de puntos sueltos.
    static let backgroundDistance = 0.38

    /// Y por encima de esta, es prenda del todo. En medio, transición.
    ///
    /// La banda se ensancha junto con el umbral: el anillo de píxeles medio
    /// teñidos del contorno es más grueso de lo que parece —el JPEG del modelo
    /// lo difumina— y una transición corta lo dejaba casi entero dentro.
    static let garmentDistance = 0.66

    /// Recorta la prenda dejando el fondo transparente.
    ///
    /// - Returns: `nil` si la imagen no parece tener fondo de croma — por
    ///   ejemplo si el modelo lo ignoró y lo devolvió sobre blanco. Quien llama
    ///   se queda entonces con el recorte de siempre en vez de destrozar la
    ///   imagen buscando un color que no está.
    public static func cutout(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        guard
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var background = 0
        for y in 0..<height {
            for x in 0..<width {
                let red = Double(buffer[x, y, 0]) / 255
                let green = Double(buffer[x, y, 1]) / 255
                let blue = Double(buffer[x, y, 2]) / 255
                let distance = distanceToKey(red: red, green: green, blue: blue)

                if distance <= backgroundDistance {
                    for component in 0..<4 { buffer[x, y, component] = 0 }
                    background += 1
                    continue
                }

                // **El derrame se quita en toda la prenda, no solo en el
                // borde.**
                //
                // Aquí estaba el reborde magenta: la corrección se aplicaba
                // únicamente a la banda de transición, y el magenta rebota
                // sobre la tela **un par de píxeles hacia dentro** —más en las
                // zonas claras, que reflejan más—. Esos píxeles pasaban el
                // umbral de "prenda" y se quedaban teñidos, dibujando un filete
                // rosa alrededor de todo el recorte.
                //
                // Cuesta nada aplicarlo siempre: solo cambia los píxeles donde
                // rojo **y** azul superan al verde, que es la firma del
                // magenta y no la de una tela rosa normal.
                let despilled = suppressSpill(
                    red: Double(buffer[x, y, 0]),
                    green: Double(buffer[x, y, 1]),
                    blue: Double(buffer[x, y, 2])
                )

                guard distance < garmentDistance else {
                    buffer[x, y, 0] = UInt8(despilled.red)
                    buffer[x, y, 1] = UInt8(despilled.green)
                    buffer[x, y, 2] = UInt8(despilled.blue)
                    continue
                }

                // Y en la banda, además, la transición de alfa.
                let coverage = (distance - backgroundDistance)
                    / (garmentDistance - backgroundDistance)
                let eased = coverage * coverage * (3 - 2 * coverage)

                // Premultiplicado: el color va escalado por el alfa.
                buffer[x, y, 0] = UInt8(despilled.red * eased)
                buffer[x, y, 1] = UInt8(despilled.green * eased)
                buffer[x, y, 2] = UInt8(despilled.blue * eased)
                buffer[x, y, 3] = UInt8(255 * eased)
            }
        }

        // **Se comprueba que había fondo.** Si el modelo devolvió la prenda
        // sobre blanco —pasa— no se ha borrado nada, y devolver la imagen tal
        // cual haría creer que el recorte salió bien.
        let fraction = Double(background) / Double(width * height)
        guard fraction > 0.05 else {
            DiagnosticsLog.record(
                "CATÁLOGO",
                "la imagen no trae fondo de croma (\(Int(fraction * 100))%)",
                isProblem: true
            )
            return nil
        }
        DiagnosticsLog.record("CATÁLOGO", "croma quitado · fondo \(Int(fraction * 100))%")

        // Y se limpia: fuera las motas sueltas y el borde suavizado.
        clean(buffer, width: width, height: height)
        return context.makeImage()
    }

    /// Cuánto tiene que medir una mancha, respecto a la mayor, para quedarse.
    ///
    /// Las motas que deja el croma son diminutas —una sombra, un reflejo del
    /// magenta en un pliegue— así que con un 2% se van todas sin tocar nada
    /// real. Y se compara contra la mayor y no contra la imagen: una prenda
    /// pequeña en un lienzo grande tiene todas sus partes pequeñas.
    static let minimumBlobFraction = 0.02

    /// Radio del suavizado del borde, en píxeles.
    static let edgeBlurRadius = 2

    /// Quita lo que sobra fuera de la prenda y suaviza el contorno.
    ///
    /// Dos cosas que se ven y una sola pasada:
    ///
    /// 1. **Las motas.** Por muy bien que separe el croma, quedan píxeles
    ///    sueltos flotando alrededor — trocitos de sombra, reflejos del fondo
    ///    en un pliegue. En la balda se leen como suciedad alrededor de la
    ///    prenda. Se quedan solo las manchas grandes.
    /// 2. **El canto.** El alfa del croma es duro: cada píxel entra o no
    ///    entra, así que el contorno sale en escalera. Una media móvil corta
    ///    con una curva que aprieta los extremos lo convierte en una rampa de
    ///    un par de píxeles, que es lo que hace que parezca recortado y no
    ///    troquelado.
    private static func clean(_ buffer: PixelBuffer, width: Int, height: Int) {
        // --- 1. Fuera las motas ---
        var mask = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where buffer[x, y, 3] > 24 {
                mask[row + x] = 1
            }
        }

        let labelled = ConnectedComponents.label(mask: mask, width: width, height: height)
        guard let largest = labelled.components.map(\.pixelCount).max(), largest > 0 else {
            return
        }
        let floor = Int(Double(largest) * minimumBlobFraction)
        var keep = [Bool](repeating: false, count: labelled.components.count + 1)
        for component in labelled.components where component.pixelCount >= floor {
            keep[Int(component.label)] = true
        }

        for index in 0..<(width * height) {
            let label = Int(labelled.labels[index])
            guard label == 0 || !keep[label] else { continue }
            let x = index % width, y = index / width
            for component in 0..<4 { buffer[x, y, component] = 0 }
        }

        // --- 2. El contorno, mordido un píxel ---
        choke(buffer, width: width, height: height)

        // --- 3. El borde, suavizado ---
        smoothEdge(buffer, width: width, height: height)

        // --- 4. Y el color del borde, traído de dentro ---
        extendEdgeColour(buffer, width: width, height: height)

        // --- 5. Y el filete que queda pegado por dentro ---
        scrubEdgeSpill(buffer, width: width, height: height)
    }

    /// Por encima de este alfa, un píxel es prenda de verdad y su color es de
    /// fiar. Por debajo, es mezcla.
    private static let opaqueFloor: UInt8 = 250

    /// Sustituye el color de los píxeles del borde por el de la tela de al
    /// lado.
    ///
    /// ## Lo que queda cuando ya has hecho todo lo demás
    ///
    /// Recortar, quitar el derrame y morder un píxel dejan el contorno limpio
    /// de fondo, pero el suavizado vuelve a crear una rampa de píxeles medio
    /// transparentes — y esos píxeles siguen llevando **su** color, que es el
    /// que tenían en el JPEG del modelo: una mezcla de tela y fondo. Sobre un
    /// lienzo claro no se nota; sobre uno oscuro, ese anillo es exactamente el
    /// halo que se ve.
    ///
    /// Es la operación estándar de "extender el borde": el píxel medio
    /// transparente se queda con su alfa y toma el color del primer píxel
    /// opaco que tenga cerca. Así ningún píxel de la imagen final lleva un
    /// gramo de color de fondo, y el suavizado sigue estando.
    private static func extendEdgeColour(_ buffer: PixelBuffer, width: Int, height: Int) {
        // Una copia del color de los opacos: se lee mientras se escribe, y sin
        // copia un píxel ya corregido serviría de fuente para el siguiente.
        var red = [UInt8](repeating: 0, count: width * height)
        var green = [UInt8](repeating: 0, count: width * height)
        var blue = [UInt8](repeating: 0, count: width * height)
        var opaque = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where buffer[x, y, 3] >= opaqueFloor {
                red[row + x] = buffer[x, y, 0]
                green[row + x] = buffer[x, y, 1]
                blue[row + x] = buffer[x, y, 2]
                opaque[row + x] = true
            }
        }

        let radius = edgeBlurRadius + 1
        for y in 0..<height {
            for x in 0..<width {
                let alpha = buffer[x, y, 3]
                guard alpha > 0, alpha < opaqueFloor else { continue }

                var sum = (red: 0, green: 0, blue: 0, count: 0)
                for dy in -radius...radius {
                    let ny = y + dy
                    guard ny >= 0, ny < height else { continue }
                    for dx in -radius...radius {
                        let nx = x + dx
                        guard nx >= 0, nx < width, opaque[ny * width + nx] else { continue }
                        sum.red += Int(red[ny * width + nx])
                        sum.green += Int(green[ny * width + nx])
                        sum.blue += Int(blue[ny * width + nx])
                        sum.count += 1
                    }
                }
                guard sum.count > 0 else {
                    // Ni un vecino opaco: es una mota suelta que el suavizado
                    // dejó a medias. Fuera, que es lo que habría pasado si la
                    // limpieza la hubiera cogido.
                    for component in 0..<4 { buffer[x, y, component] = 0 }
                    continue
                }

                // El color va premultiplicado: se escribe la tela de al lado
                // escalada por el alfa que le toca a este píxel.
                let scale = Double(alpha) / 255 / Double(sum.count)
                buffer[x, y, 0] = UInt8(min(255, Double(sum.red) * scale))
                buffer[x, y, 1] = UInt8(min(255, Double(sum.green) * scale))
                buffer[x, y, 2] = UInt8(min(255, Double(sum.blue) * scale))
            }
        }
    }

    /// Come un píxel del contorno.
    ///
    /// El anillo exterior del recorte es el peor de todos: son píxeles que el
    /// JPEG del modelo dejó a medio camino entre la prenda y el fondo, con algo
    /// de los dos colores mezclado. Por muy bien que se les quite el derrame,
    /// siguen siendo una mezcla — y en el borde de una prenda clara sobre un
    /// lienzo claro, esa mezcla es justo lo que se ve.
    ///
    /// Una erosión de un píxel los quita de un plumazo. Se pierde un píxel de
    /// prenda de verdad; a cambio no queda ninguno de fondo, y a esa escala lo
    /// primero no se nota y lo segundo sí.
    ///
    /// El color va premultiplicado, así que se reescala con el alfa nuevo: sin
    /// eso queda un fantasma de color donde ya no hay opacidad.
    private static func choke(_ buffer: PixelBuffer, width: Int, height: Int) {
        var alpha = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width { alpha[row + x] = buffer[x, y, 3] }
        }

        for y in 0..<height {
            for x in 0..<width where alpha[y * width + x] > 0 {
                var minimum = alpha[y * width + x]
                // En el borde de la imagen se considera que fuera hay fondo:
                // una prenda que toca el canto llega recortada de origen.
                if x == 0 || y == 0 || x == width - 1 || y == height - 1 {
                    minimum = 0
                } else {
                    minimum = min(minimum, alpha[y * width + x - 1])
                    minimum = min(minimum, alpha[y * width + x + 1])
                    minimum = min(minimum, alpha[(y - 1) * width + x])
                    minimum = min(minimum, alpha[(y + 1) * width + x])
                }
                guard minimum < buffer[x, y, 3] else { continue }

                let previous = Double(buffer[x, y, 3])
                let ratio = Double(minimum) / previous
                for component in 0..<3 {
                    buffer[x, y, component] = UInt8(Double(buffer[x, y, component]) * ratio)
                }
                buffer[x, y, 3] = minimum
            }
        }
    }

    /// Difumina el alfa con una media móvil separable y le aplica una curva.
    ///
    /// Separable y con suma acumulada: el coste no depende del radio. Y la
    /// curva —`smoothstep` entre 0,35 y 0,80— es lo que impide que el
    /// difuminado deje la prenda entera medio transparente por el contorno:
    /// por dentro vuelve a opaco enseguida y por fuera cae a cero.
    private static func smoothEdge(_ buffer: PixelBuffer, width: Int, height: Int) {
        let radius = edgeBlurRadius
        guard width > 2 * radius, height > 2 * radius else { return }
        let window = Double(radius * 2 + 1)

        var alpha = [Double](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            alpha[index] = Double(buffer[index % width, index / width, 3]) / 255
        }

        var horizontal = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = y * width
            var sum = 0.0
            for x in 0...radius { sum += alpha[row + x] }
            for x in 0..<width {
                horizontal[row + x] = sum / window
                if x - radius >= 0 { sum -= alpha[row + x - radius] }
                if x + radius + 1 < width { sum += alpha[row + x + radius + 1] }
            }
        }

        for x in 0..<width {
            var sum = 0.0
            for y in 0...radius { sum += horizontal[y * width + x] }
            for y in 0..<height {
                let value = (sum / window - 0.35) / (0.80 - 0.35)
                let clamped = min(1, max(0, value))
                let eased = clamped * clamped * (3 - 2 * clamped)

                // El color va premultiplicado, así que se reescala con el alfa
                // nuevo respecto al que tenía. Sin esto, bajar solo el alfa
                // deja un fantasma del color al componer.
                let previous = Double(buffer[x, y, 3]) / 255
                if previous > 0.001 {
                    let ratio = eased / previous
                    for component in 0..<3 {
                        buffer[x, y, component] = UInt8(
                            min(255, Double(buffer[x, y, component]) * ratio)
                        )
                    }
                }
                buffer[x, y, 3] = UInt8(eased * 255)

                if y - radius >= 0 { sum -= horizontal[(y - radius) * width + x] }
                if y + radius + 1 < height { sum += horizontal[(y + radius + 1) * width + x] }
            }
        }
    }

    /// Distancia al croma, 0 = exactamente el fondo.
    ///
    /// Pesa **el verde el doble**: es el canal que separa el magenta puro de
    /// cualquier rosa o morado real, y tratarlo igual que los otros dos hacía
    /// que una prenda fucsia cayera dentro del umbral.
    static func distanceToKey(red: Double, green: Double, blue: Double) -> Double {
        let dr = red - keyRed
        let dg = (green - keyGreen) * 2
        let db = blue - keyBlue
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    /// Cuánto pueden pasarse rojo y azul del verde antes de considerarlo
    /// derrame, en la escala 0-255.
    ///
    /// No es cero porque hay colores reales que tienen los dos canales por
    /// encima del verde: un burdeos, un lavanda, un rosa palo. Con tolerancia
    /// cero, esas prendas salían desaturadas.
    static let spillTolerance = 26.0

    /// Le quita a rojo y azul el exceso que tienen sobre el verde.
    ///
    /// ## Aquí estaba el magenta que no se iba
    ///
    /// La versión anterior decía: `limit = max(green, min(red, blue))` y luego
    /// recortaba rojo y azul a ese límite. Parece razonable y **no hace nada en
    /// el caso que importa**: en un píxel bien teñido de magenta, `min(red,
    /// blue)` ya es el valor alto, así que el límite salía igual al propio
    /// canal y el recorte lo dejaba intacto. Cuanto más magenta tenía un píxel,
    /// menos se le corregía. Por eso quedaba el filete rosa por mucho que se
    /// aplicara a toda la prenda.
    ///
    /// Lo correcto es restar el **exceso común** sobre el canal que el croma no
    /// usa —el verde— a los dos canales que sí usa. Así un magenta puro se cae
    /// a negro, un píxel con derrame se desatura hacia el gris conservando su
    /// tono, y un burdeos (rojo 115, verde 30, azul 45) ni se entera: su exceso
    /// está por debajo de la tolerancia.
    static func suppressSpill(
        red: Double, green: Double, blue: Double,
        tolerance: Double = spillTolerance
    ) -> (red: Double, green: Double, blue: Double) {
        let excess = min(red, blue) - green - tolerance
        guard excess > 0 else { return (red, green, blue) }
        return (max(0, red - excess), green, max(0, blue - excess))
    }

    /// Hasta dónde llega el derrame hacia dentro de la prenda, en píxeles.
    ///
    /// El JPEG del modelo comprime el color en bloques y a media resolución,
    /// así que el magenta del fondo se cuela dos o tres píxeles por debajo del
    /// contorno aunque el alfa ya esté al máximo.
    static let edgeSpillRadius = 3

    /// Limpia el magenta que queda **pegado por dentro del contorno**.
    ///
    /// ## Por qué hace falta otra pasada
    ///
    /// Porque el derrame se quita con tolerancia: rojo y azul pueden pasarse
    /// del verde unos 26 niveles sin que se toque nada, y eso protege a un
    /// burdeos, a un lavanda o a un rosa palo de salir desaturados. El precio
    /// es que en el anillo del borde —donde el píxel es medio fondo— queda
    /// permitido justo ese 10% de magenta, y diez por ciento de magenta a lo
    /// largo de todo el contorno es el filete rosa que se ve.
    ///
    /// ## Y por qué solo en el borde
    ///
    /// Porque ahí el magenta **no puede ser de la prenda**: es el fondo que se
    /// ha corrido. Dentro sí puede serlo, así que dentro se mantiene la
    /// tolerancia. La regla es la misma de siempre, aplicada donde la duda no
    /// existe.
    private static func scrubEdgeSpill(_ buffer: PixelBuffer, width: Int, height: Int) {
        // Qué píxeles no son prenda del todo: el fondo y la rampa del borde.
        var soft = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where buffer[x, y, 3] < opaqueFloor {
                soft[row + x] = true
            }
        }

        // Y cuáles están a tiro de ellos. Se dilata por pasadas de cuatro
        // vecinos —tres pasadas, tres píxeles— en vez de mirar un cuadrado por
        // píxel: es la misma vecindad y cuesta una fracción.
        var near = soft
        for _ in 0..<edgeSpillRadius {
            var grown = near
            for y in 0..<height {
                let row = y * width
                for x in 0..<width where near[row + x] {
                    if x > 0 { grown[row + x - 1] = true }
                    if x < width - 1 { grown[row + x + 1] = true }
                    if y > 0 { grown[row - width + x] = true }
                    if y < height - 1 { grown[row + width + x] = true }
                }
            }
            near = grown
        }

        var scrubbed = 0
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where near[row + x] && !soft[row + x] {
                let cleaned = suppressSpill(
                    red: Double(buffer[x, y, 0]),
                    green: Double(buffer[x, y, 1]),
                    blue: Double(buffer[x, y, 2]),
                    // Sin tolerancia: aquí el magenta es del fondo.
                    tolerance: 0
                )
                guard cleaned.red < Double(buffer[x, y, 0]) else { continue }
                buffer[x, y, 0] = UInt8(cleaned.red)
                buffer[x, y, 1] = UInt8(cleaned.green)
                buffer[x, y, 2] = UInt8(cleaned.blue)
                scrubbed += 1
            }
        }
        if scrubbed > 0 {
            DiagnosticsLog.record("CATÁLOGO", "filete del borde limpiado en \(scrubbed) píxeles")
        }
    }
}
