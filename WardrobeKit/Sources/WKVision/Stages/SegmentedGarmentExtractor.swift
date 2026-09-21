import CoreGraphics
import Foundation
import WKCore

/// Saca prendas de una foto a partir del mapa de clases de SegFormer.
///
/// Esta es la ruta buena. El modo degradado corta la silueta de la persona por
/// las articulaciones porque no tiene nada mejor; aquí cada píxel viene ya
/// etiquetado, así que el recorte sigue la prenda de verdad — incluido el hueco
/// entre las piernas de un pantalón o el cuello de una camiseta.
///
/// ## De semántico a instancias
///
/// SegFormer es un segmentador **semántico**: etiqueta clases, no objetos. Dos
/// camisetas dobladas sobre la cama son las dos `upper-clothes`, y quedarse con
/// la caja de toda la clase producía **una** prenda con las dos dentro y un
/// trozo de colcha en medio. Aquí cada clase se parte en componentes conexas
/// (`ConnectedComponents`) y cada grupo de componentes se vuelve una prenda.
///
/// El riesgo del camino contrario —partir de más— es igual de real: un brazo
/// cruzado sobre el torso divide la camiseta en dos mitades que no se tocan.
/// Por eso las componentes se vuelven a juntar cuando sus cajas se solapan o
/// cuando están casi pegadas: eso no son dos prendas, es una prenda tapada.
enum SegmentedGarmentExtractor {

    /// Fracción mínima del mapa que debe ocupar una prenda para contar.
    ///
    /// Por debajo es ruido: un borde mal clasificado, el reflejo de una hebilla.
    /// Crear una prenda a partir de 200 píxeles sueltos llena el armario de
    /// basura que el usuario tiene que ir borrando.
    static let minimumAreaFraction = 0.004

    /// Lo que se le exige a la **segunda** prenda de una clase para existir.
    ///
    /// Mucho más alto que el mínimo general, y a propósito: decir "aquí hay dos
    /// camisetas" a partir de una mancha pequeña es la forma de duplicar el
    /// armario con recortes de fondo mal clasificado. Una prenda de verdad que
    /// esté en la foto a la vez que otra de su misma clase ocupa su sitio.
    ///
    /// La primera —la mayor de la clase— no pasa por aquí: una prenda pequeña
    /// que sea la única de su clase (unas gafas, un cinturón) sigue entrando
    /// con el mínimo general.
    static let additionalInstanceFraction = 0.015

    /// Manchas por debajo de esto no llegan ni a considerarse.
    ///
    /// Es el dentado del borde entre clases: píxeles sueltos de camiseta
    /// pegados al cuello, la sombra bajo una manga. Se quitan antes de decidir
    /// nada para que no ensucien ni las cajas ni el conteo.
    static let specklePixelFraction = 0.0005

    /// Cuánto se tienen que solapar dos cajas de la misma clase para que sean
    /// la misma prenda, como fracción del área de la menor.
    ///
    /// Un brazo cruzado sobre el torso parte la camiseta en dos trozos cuyas
    /// cajas se montan casi por completo. Dos camisetas distintas ocupan sitios
    /// distintos.
    static let occlusionOverlapFraction = 0.40

    /// Y si no se solapan, cuánto pueden separarse y seguir siendo la misma
    /// prenda, como fracción del lado del mapa.
    ///
    /// Ajustado corto: a 512 son unos 15 píxeles. Lo suficiente para coser una
    /// prenda partida por un cinturón, no tanto como para fundir dos prendas
    /// dobladas una al lado de la otra.
    static let contactGapFraction = 0.03

    /// Cuánto tienen que compartir dos trozos en un eje para considerarlos
    /// alineados.
    static let alignmentOverlapFraction = 0.55

    /// Y cuánto pueden separarse en el **otro** eje, medido contra su propio
    /// tamaño — no contra el mapa.
    ///
    /// Aquí está la diferencia entre un pantalón y dos camisetas. Las dos
    /// perneras comparten toda su altura y el hueco entre ellas es una fracción
    /// de lo que mide una pernera de ancho. Dos prendas distintas puestas una
    /// al lado de la otra dejan entre ellas un hueco del orden de su propio
    /// tamaño, porque nadie las apoya pegadas.
    ///
    /// Medirlo contra el mapa y no contra la prenda era el fallo: un umbral
    /// fijo de quince píxeles parte un pantalón fotografiado de cerca —donde
    /// el hueco entre perneras son cincuenta— y funde dos prendas
    /// fotografiadas de lejos.
    static let alignedGapFraction = 0.6

    /// Cuánto se difumina el borde de la máscara, en píxeles **del mapa**.
    ///
    /// Dos y no diez: el objetivo es redondear el dentado, no desdibujar la
    /// prenda. Con un radio grande la camiseta acaba con el contorno lechoso y
    /// se nota más que el escalón que venía a arreglar.
    static let edgeBlurRadius = 2

    /// Dónde empieza y acaba la transición, sobre la cobertura ya difuminada.
    ///
    /// Recortado hacia dentro a propósito (`0.35`–`0.80` y no `0`–`1`): el
    /// mapa de clases tiende a pasarse un píxel hacia fuera, y sin esto el
    /// recorte se lleva un filete del fondo alrededor de toda la prenda — el
    /// halo blanco que se ve al ponerla sobre un lienzo de color.
    static let edgeLow = 0.35
    static let edgeHigh = 0.80

    /// Qué píxeles del mapa pertenecen a **una** prenda, y **cuánto**.
    ///
    /// Cobertura de 0 a 255 y no un sí/no.
    ///
    /// ## Por qué el borde salía dentado
    ///
    /// El mapa de clases mide 512 y la foto de trabajo 1280, así que cada
    /// píxel de máscara cubre dos y medio de salida. Consultado como binario y
    /// por vecino más cercano, eso es literalmente una escalera: bloques de
    /// dos píxeles y medio con el canto a pelo, que es lo que se ve como
    /// "pixelado feo" alrededor de la prenda.
    ///
    /// Aquí se guarda la cobertura ya suavizada en la retícula del mapa, y el
    /// recorte la muestrea **interpolando**. El canto pasa de ser un escalón a
    /// ser una rampa de un par de píxeles, que es lo que hace que una prenda
    /// recortada parezca recortada y no troquelada con tijeras de uñas.
    struct InstanceMask: Sendable {
        let width: Int
        let height: Int
        /// 0 = fuera, 255 = dentro del todo.
        private let coverage: [UInt8]

        init(width: Int, height: Int, inside: [UInt8]) {
            self.width = width
            self.height = height
            self.coverage = Self.soften(inside, width: width, height: height)
        }

        @inline(__always)
        func contains(x: Int, y: Int) -> Bool {
            guard x >= 0, x < width, y >= 0, y < height else { return false }
            return coverage[y * width + x] > 127
        }

        /// Cobertura interpolada, en coordenadas continuas del mapa.
        ///
        /// Bilineal: los cuatro vecinos pesados por lo cerca que está el punto
        /// de cada uno. Es lo que convierte el escalón en rampa.
        @inline(__always)
        func coverage(atX x: Double, y: Double) -> Double {
            let clampedX = min(Double(width - 1), max(0, x))
            let clampedY = min(Double(height - 1), max(0, y))
            let x0 = Int(clampedX), y0 = Int(clampedY)
            let x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
            let fx = clampedX - Double(x0), fy = clampedY - Double(y0)

            let top = Double(coverage[y0 * width + x0]) * (1 - fx)
                + Double(coverage[y0 * width + x1]) * fx
            let bottom = Double(coverage[y1 * width + x0]) * (1 - fx)
                + Double(coverage[y1 * width + x1]) * fx
            return (top * (1 - fy) + bottom * fy) / 255
        }

        /// Difumina la máscara binaria con una media móvil separable.
        ///
        /// Separable —una pasada horizontal y otra vertical— y con suma
        /// acumulada: el coste no depende del radio, que es lo que permite
        /// hacerlo por prenda sin que se note en el escaneo.
        private static func soften(_ inside: [UInt8], width: Int, height: Int) -> [UInt8] {
            let radius = edgeBlurRadius
            guard radius > 0, width > 2 * radius, height > 2 * radius else { return inside }

            let window = Double(radius * 2 + 1)
            var horizontal = [Double](repeating: 0, count: width * height)
            for y in 0..<height {
                let row = y * width
                var sum = 0.0
                for x in 0...radius { sum += inside[row + x] == 0 ? 0 : 1 }
                for x in 0..<width {
                    horizontal[row + x] = sum / window
                    let leaving = x - radius
                    let entering = x + radius + 1
                    if leaving >= 0 { sum -= inside[row + leaving] == 0 ? 0 : 1 }
                    if entering < width { sum += inside[row + entering] == 0 ? 0 : 1 }
                }
            }

            var result = [UInt8](repeating: 0, count: width * height)
            for x in 0..<width {
                var sum = 0.0
                for y in 0...radius { sum += horizontal[y * width + x] }
                for y in 0..<height {
                    // La curva que aprieta el borde: por debajo de `edgeLow`
                    // es fondo, por encima de `edgeHigh` es prenda, y en medio
                    // una transición suave. Sin ella, la media móvil deja la
                    // prenda entera medio transparente por el contorno.
                    let value = (sum / window - edgeLow) / (edgeHigh - edgeLow)
                    let clamped = min(1, max(0, value))
                    // Smoothstep: entra y sale sin canto, que es lo que hace
                    // que la rampa no se lea como una segunda línea.
                    let eased = clamped * clamped * (3 - 2 * clamped)
                    result[y * width + x] = UInt8(eased * 255)

                    let leaving = y - radius
                    let entering = y + radius + 1
                    if leaving >= 0 { sum -= horizontal[leaving * width + x] }
                    if entering < height { sum += horizontal[entering * width + x] }
                }
            }
            return result
        }
    }

    struct Region {
        let kind: GarmentKind
        let label: ClothesSegmenter.Label
        /// En coordenadas del mapa de clases.
        let bounds: CGRect
        let pixelCount: Int
        /// Cuál de las prendas de esta clase es, de arriba abajo. 0 cuando solo
        /// hay una, que es el caso normal.
        let instanceIndex: Int
        /// Los píxeles de **esta** prenda, no los de su clase.
        let mask: InstanceMask
    }

    /// Agrupa el mapa en prendas utilizables.
    ///
    /// Los zapatos izquierdo y derecho se fusionan en una sola región: un par
    /// es **una** prenda, y tratarlos por separado duplicaría toda la balda de
    /// calzado con falsos distintos. Es también la única clase que nunca se
    /// parte en instancias — dos zapatos que no se tocan siguen siendo un par.
    /// - Parameter splitting: si una clase puede dar **más de una** prenda.
    ///
    ///   Apagado, cada clase da una sola región con todos sus píxeles. Es lo
    ///   correcto al añadir una prenda a mano: ahí el usuario está
    ///   fotografiando **una** cosa, así que partir solo puede equivocarse —y
    ///   se equivocaba: un pantalón cuya cinturilla y perneras quedan separadas
    ///   por un cinturón o por una sombra volvía en tres.
    ///
    ///   Encendido —el escaneo de la galería— sí hace falta: ahí una foto
    ///   puede traer dos camisetas dobladas sobre la cama y meterlas en la
    ///   misma prenda las pierde las dos.
    /// Radio del cierre, en píxeles del mapa de clases.
    ///
    /// Tres sobre un mapa de 512 es aproximadamente medio centímetro de tela en
    /// una foto de cuerpo entero: tapa arrugas y cinturones, y no llega a unir
    /// una camiseta con un pantalón que se tocan.
    static let closingRadius = 3

    static func regions(in map: ClassMap, splitting: Bool = true) -> [Region] {
        let width = map.width
        let height = map.height
        let total = Double(width * height)
        guard total > 0 else { return [] }

        // Una sola pasada por el mapa para saber qué grupos hay y con cuántos
        // píxeles. Recorrerlo una vez por cada una de las 18 clases sería
        // dieciocho veces el trabajo para responder lo mismo.
        let groupCount = 18
        var counts = [Int](repeating: 0, count: groupCount)
        var groupOf = [Int8](repeating: -1, count: width * height)
        for index in 0..<(width * height) {
            let raw = map.rawValue(at: index)
            guard
                let label = ClothesSegmenter.Label(rawValue: raw),
                label.kind != nil
            else { continue }
            let group = label.mergeGroup
            guard group >= 0, group < groupCount else { continue }
            groupOf[index] = Int8(group)
            counts[group] += 1
        }

        let speckleFloor = max(8, Int(total * specklePixelFraction))
        var regions: [Region] = []

        for group in 0..<groupCount {
            guard
                Double(counts[group]) / total >= minimumAreaFraction,
                let label = ClothesSegmenter.Label(rawValue: group),
                let kind = label.kind
            else { continue }

            var mask = [UInt8](repeating: 0, count: width * height)
            for index in 0..<(width * height) where groupOf[index] == Int8(group) {
                mask[index] = 1
            }

            // **Cerrar los agujeros antes de contar manchas.**
            //
            // Es lo que arregla el pantalón que se detectaba como tres prendas.
            // Una arruga marcada, la sombra de un pliegue o el cinturón cambian
            // el color lo justo para que una franja de píxeles salga con otra
            // clase, y esa grieta parte la máscara en dos. El contador de
            // componentes hace lo que debe —ve dos manchas— pero la prenda era
            // una.
            //
            // El cierre engorda la máscara y la vuelve a adelgazar: los huecos
            // más finos que el radio desaparecen y el contorno se queda donde
            // estaba.
            Morphology.close(&mask, width: width, height: height, radius: closingRadius)

            let labelled = ConnectedComponents.label(mask: mask, width: width, height: height)
            let pieces = labelled.components.filter { $0.pixelCount >= speckleFloor }
            guard !pieces.isEmpty else { continue }

            // El par de zapatos no se parte nunca. Y si no se está partiendo
            // en instancias, ninguna clase lo hace: todo lo de esa clase es
            // una prenda.
            let clusters = !splitting || label.mergeGroup == ClothesSegmenter.Label.leftShoe.rawValue
                ? [pieces]
                : cluster(pieces, mapSide: Double(max(width, height)))

            // De arriba abajo dentro de la clase: si hay dos camisetas, la de
            // arriba es la instancia 0. Es el orden en el que se ven.
            let ordered = clusters
                .map { InstanceDraft(pieces: $0) }
                .sorted { ($0.bounds.minY, $0.bounds.minX) < ($1.bounds.minY, $1.bounds.minX) }

            let largest = ordered.map(\.pixelCount).max() ?? 0
            var instanceIndex = 0
            for draft in ordered {
                let fraction = Double(draft.pixelCount) / total
                guard fraction >= minimumAreaFraction else { continue }
                // Solo la mayor de la clase entra con el mínimo general. Las
                // demás tienen que justificar que son otra prenda.
                if draft.pixelCount != largest, fraction < additionalInstanceFraction { continue }

                // Pertenencia por etiqueta en una tabla, no en un `Set`: aquí
                // hay una consulta por píxel del mapa y hashear un `Int32`
                // doscientas mil veces cuesta más que toda la fusión junta.
                var isMember = [Bool](repeating: false, count: labelled.components.count + 1)
                for piece in draft.pieces { isMember[Int(piece.label)] = true }

                var inside = [UInt8](repeating: 0, count: width * height)
                for index in 0..<(width * height) {
                    let label = Int(labelled.labels[index])
                    if label > 0, isMember[label] { inside[index] = 1 }
                }

                regions.append(
                    Region(
                        kind: kind,
                        label: label,
                        bounds: draft.bounds,
                        pixelCount: draft.pixelCount,
                        instanceIndex: instanceIndex,
                        mask: InstanceMask(width: width, height: height, inside: inside)
                    )
                )
                instanceIndex += 1
            }
        }

        // De arriba abajo: es el orden en el que se lleva la ropa y en el que
        // el usuario espera verla en la pantalla de revisión.
        return regions.sorted { $0.bounds.minY < $1.bounds.minY }
    }

    // MARK: - Volver a juntar lo que era una sola prenda

    /// Un candidato a prenda mientras se decide si lo es.
    private struct InstanceDraft {
        let pieces: [ConnectedComponents.Component]
        let bounds: CGRect
        let pixelCount: Int

        init(pieces: [ConnectedComponents.Component]) {
            self.pieces = pieces
            self.pixelCount = pieces.reduce(0) { $0 + $1.pixelCount }
            self.bounds = pieces.dropFirst().reduce(pieces[0].bounds) { $0.union($1.bounds) }
        }
    }

    /// Junta las componentes que son trozos de la misma prenda.
    ///
    /// Se repite hasta que no cambia nada porque fusionar cambia la caja: dos
    /// trozos que no se tocaban pueden quedar dentro de la caja del grupo
    /// resultante, y pararse en la primera pasada dejaría el resultado
    /// dependiendo del orden en que se miraran.
    private static func cluster(
        _ pieces: [ConnectedComponents.Component],
        mapSide: Double
    ) -> [[ConnectedComponents.Component]] {
        guard pieces.count > 1 else { return [pieces] }

        var groups = pieces.map { [$0] }
        var boxes = pieces.map(\.bounds)
        let gap = mapSide * contactGapFraction

        var merged = true
        while merged {
            merged = false
            outer: for i in 0..<groups.count {
                for j in (i + 1)..<groups.count where belongTogether(boxes[i], boxes[j], gap: gap) {
                    groups[i].append(contentsOf: groups[j])
                    boxes[i] = boxes[i].union(boxes[j])
                    groups.remove(at: j)
                    boxes.remove(at: j)
                    merged = true
                    break outer
                }
            }
        }
        return groups
    }

    /// Si dos cajas de la misma clase son la misma prenda partida.
    static func belongTogether(_ a: CGRect, _ b: CGRect, gap: Double) -> Bool {
        // 1. Cajas montadas: una prenda tapada por un brazo cruzado.
        let intersection = a.intersection(b)
        if !intersection.isNull {
            let overlap = intersection.width * intersection.height
            let smaller = min(a.width * a.height, b.width * b.height)
            if smaller > 0, overlap / smaller >= occlusionOverlapFraction { return true }
        }

        // Separación entre cajas, por eje. Cero en un eje significa que se
        // solapan en ese eje.
        let dx = max(0, max(a.minX, b.minX) - min(a.maxX, b.maxX))
        let dy = max(0, max(a.minY, b.minY) - min(a.maxY, b.maxY))

        // 2. Casi tocándose, en términos absolutos.
        if (dx * dx + dy * dy).squareRoot() <= gap { return true }

        // 3. **Dos trozos alineados de la misma prenda.**
        //
        // Las perneras de un pantalón: comparten toda su altura y el hueco que
        // las separa es una fracción de lo que mide una pernera de ancho. La
        // cinturilla y las perneras, igual en el otro eje. Esto es lo que
        // faltaba, y por lo que un pantalón sobre fondo blanco salía partido
        // en tres.
        let sharedY = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        if sharedY >= alignmentOverlapFraction * min(a.height, b.height),
           dx <= alignedGapFraction * min(a.width, b.width) {
            return true
        }

        let sharedX = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        if sharedX >= alignmentOverlapFraction * min(a.width, b.width),
           dy <= alignedGapFraction * min(a.height, b.height) {
            return true
        }

        return false
    }

    /// Recorta la prenda de la foto original, con el fondo a transparente.
    ///
    /// El mapa está a 512² y la foto puede ser de 4000 px, así que la máscara se
    /// consulta escalando cada píxel de destino al mapa. Es una interpolación
    /// por vecino más cercano, que para una máscara es lo correcto: interpolar
    /// suavizaría los bordes entre clases e inventaría píxeles a medio camino
    /// entre "camiseta" y "brazo".
    ///
    /// La máscara que se consulta es la de **esta** prenda, no la de su clase:
    /// si hay dos camisetas, el recorte de la primera no puede arrastrar un
    /// trozo de la segunda por estar dentro de su caja.
    static func crop(region: Region, from image: CGImage) -> CGImage? {
        let mask = region.mask
        let scaleX = Double(image.width) / Double(mask.width)
        let scaleY = Double(image.height) / Double(mask.height)

        let box = CGRect(
            x: (region.bounds.minX * scaleX).rounded(.down),
            y: (region.bounds.minY * scaleY).rounded(.down),
            width: (region.bounds.width * scaleX).rounded(.up),
            height: (region.bounds.height * scaleY).rounded(.up)
        ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

        guard !box.isNull, box.width >= 8, box.height >= 8 else { return nil }
        guard let cropped = image.cropping(to: box) else { return nil }

        let width = cropped.width
        let height = cropped.height
        guard
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return nil }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        // La coordenada del mapa para cada columna del recorte, **calculada una
        // vez**. Antes había una división en coma flotante por píxel: en un
        // recorte de un millón de píxeles son un millón de divisiones para
        // recorrer una tabla de 512 valores distintos.
        //
        // En coma flotante y no redondeada: es lo que la interpolación
        // necesita para saber entre qué dos píxeles del mapa cae.
        var columns = [Double](repeating: 0, count: width)
        for x in 0..<width {
            columns[x] = (Double(x) + box.minX) / scaleX
        }

        for y in 0..<height {
            // El buffer de un CGBitmapContext guarda la primera fila arriba, la
            // misma convención que el mapa de clases. No hay que invertir nada.
            let mapY = (Double(y) + box.minY) / scaleY
            for x in 0..<width {
                let coverage = mask.coverage(atX: columns[x], y: mapY)
                if coverage >= 0.999 { continue }
                if coverage <= 0.001 {
                    for component in 0..<4 { buffer[x, y, component] = 0 }
                    continue
                }
                // **Los cuatro canales**, no solo el alfa. El contexto es
                // premultiplicado: dejar el color a tope y bajar solo el alfa
                // deja un fantasma del color original asomando al componer.
                for component in 0..<4 {
                    buffer[x, y, component] = UInt8(Double(buffer[x, y, component]) * coverage)
                }
            }
        }
        return context.makeImage()
    }
}
