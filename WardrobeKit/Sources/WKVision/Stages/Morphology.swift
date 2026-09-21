import Foundation

/// Operaciones de forma sobre una máscara binaria.
///
/// ## El problema que resuelve
///
/// El segmentador no falla en el contorno de la prenda: falla **por dentro**.
/// Una arruga marcada, la sombra de un pliegue o el cinturón cambian el color
/// lo bastante como para que unos cuantos píxeles salgan con otra clase, y eso
/// abre una grieta que parte la prenda en dos manchas.
///
/// Luego el contador de componentes hace su trabajo —ve dos manchas— y el
/// resultado es un pantalón convertido en dos prendas. El usuario lo ve como
/// "detecta mal"; lo que pasa es que el mapa de clases tiene agujeros de cuatro
/// píxeles.
///
/// El cierre morfológico es la herramienta exacta para eso: engorda la máscara
/// y la vuelve a adelgazar. Los huecos más pequeños que el radio se rellenan
/// —porque al engordar se tocan los dos lados— y todo lo demás vuelve a su
/// tamaño. El contorno no se mueve.
enum Morphology {

    /// Rellena huecos de hasta `radius` píxeles sin engordar la silueta.
    static func close(_ mask: inout [UInt8], width: Int, height: Int, radius: Int = 3) {
        guard radius > 0, width > 2 * radius, height > 2 * radius else { return }
        var swollen = mask
        dilate(from: mask, into: &swollen, width: width, height: height, radius: radius)
        erode(from: swollen, into: &mask, width: width, height: height, radius: radius)
    }

    /// Rellena los huecos **encerrados** por la máscara, del tamaño que sean.
    ///
    /// El cierre de arriba tapa grietas finas; esto tapa agujeros. Son fallos
    /// distintos: un pliegue con sombra en mitad de un pantalón sale como
    /// fondo, y puede ser un agujero de cien píxeles que ningún radio
    /// razonable cierra. Pero es un agujero **rodeado de tela**, y eso se
    /// reconoce sin saber nada de ropa.
    ///
    /// La forma barata de encontrarlos es al revés: lo que no es prenda y
    /// **toca el borde** de la imagen es fondo de verdad; todo lo demás que no
    /// es prenda está encerrado, así que es prenda mal clasificada.
    static func fillHoles(_ mask: inout [UInt8], width: Int, height: Int) {
        guard width > 2, height > 2 else { return }

        // Inundación desde los cuatro cantos sobre lo que **no** es prenda.
        var outside = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []
        stack.reserveCapacity(width * 2 + height * 2)

        func seed(_ x: Int, _ y: Int) {
            let index = y * width + x
            guard mask[index] == 0, !outside[index] else { return }
            outside[index] = true
            stack.append(index)
        }

        for x in 0..<width {
            seed(x, 0)
            seed(x, height - 1)
        }
        for y in 0..<height {
            seed(0, y)
            seed(width - 1, y)
        }

        while let index = stack.popLast() {
            let x = index % width
            let y = index / width
            if x > 0 { seed(x - 1, y) }
            if x < width - 1 { seed(x + 1, y) }
            if y > 0 { seed(x, y - 1) }
            if y < height - 1 { seed(x, y + 1) }
        }

        // Lo que no es prenda y no se alcanzó desde fuera estaba encerrado.
        for index in 0..<(width * height) where mask[index] == 0 && !outside[index] {
            mask[index] = 1
        }
    }

    /// Alisa el contorno: quita los escalones sin comerse la prenda.
    ///
    /// ## Qué se ve cuando falta esto
    ///
    /// Un borde a escalones. La máscara sale de decidir píxel a píxel, así que
    /// el contorno de una manga en diagonal es una escalera de un píxel, y
    /// cada píxel mal clasificado del borde es una muesca. En la miniatura no
    /// se nota; a tamaño de lienzo, el recorte parece roto.
    ///
    /// ## Cómo se alisa
    ///
    /// Promediando la vecindad y volviendo a decidir. Un píxel rodeado de
    /// prenda pasa a ser prenda aunque estuviera fuera; uno rodeado de fondo
    /// se va. Los escalones de un píxel desaparecen porque su vecindad está
    /// medio llena, y el contorno grande no se mueve porque el suyo sigue
    /// estando claro.
    ///
    /// ## Y por qué corta de menos
    ///
    /// El listón está **por debajo de la mitad**. En la duda —un píxel con la
    /// vecindad repartida— se queda dentro. Pasarse un poco deja un reborde de
    /// fondo de un par de píxeles, que no se ve; quedarse corto muerde la
    /// prenda, y eso sí se ve. Entre las dos formas de equivocarse, esta es la
    /// barata.
    static func smooth(_ mask: inout [UInt8], width: Int, height: Int, radius: Int = 2) {
        guard radius > 0, width > 2 * radius, height > 2 * radius else { return }

        // Suma por filas y luego por columnas: la ventana cuadrada cuesta el
        // radio al cuadrado por píxel, y esto se corre sobre medio millón.
        let side = 2 * radius + 1
        var horizontal = [Int](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var total = 0
                for dx in -radius...radius {
                    let nx = min(max(x + dx, 0), width - 1)
                    total += Int(mask[row + nx])
                }
                horizontal[row + x] = total
            }
        }

        // 0,42 y no 0,5: ver la nota de arriba.
        let threshold = Double(side * side) * 0.42
        for y in 0..<height {
            for x in 0..<width {
                var total = 0
                for dy in -radius...radius {
                    let ny = min(max(y + dy, 0), height - 1)
                    total += horizontal[ny * width + x]
                }
                mask[y * width + x] = Double(total) >= threshold ? 1 : 0
            }
        }
    }

    /// Máximo en una ventana cuadrada, en dos pasadas.
    ///
    /// Separable —primero filas, luego columnas— porque hacerlo con la ventana
    /// entera cuesta el radio al cuadrado por píxel, y aquí se corre sobre un
    /// mapa de medio millón.
    private static func dilate(
        from source: [UInt8], into destination: inout [UInt8],
        width: Int, height: Int, radius: Int
    ) {
        var horizontal = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var value: UInt8 = 0
                for dx in -radius...radius {
                    let nx = x + dx
                    guard nx >= 0, nx < width else { continue }
                    if source[row + nx] == 1 { value = 1; break }
                }
                horizontal[row + x] = value
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                var value: UInt8 = 0
                for dy in -radius...radius {
                    let ny = y + dy
                    guard ny >= 0, ny < height else { continue }
                    if horizontal[ny * width + x] == 1 { value = 1; break }
                }
                destination[y * width + x] = value
            }
        }
    }

    /// Y el mínimo, que es lo que devuelve la silueta a su tamaño.
    private static func erode(
        from source: [UInt8], into destination: inout [UInt8],
        width: Int, height: Int, radius: Int
    ) {
        var horizontal = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var value: UInt8 = 1
                for dx in -radius...radius {
                    let nx = x + dx
                    // Fuera de la imagen se considera vacío: una prenda que
                    // toca el canto no debe crecer hacia fuera al cerrar.
                    guard nx >= 0, nx < width, source[row + nx] == 1 else { value = 0; break }
                }
                horizontal[row + x] = value
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                var value: UInt8 = 1
                for dy in -radius...radius {
                    let ny = y + dy
                    guard ny >= 0, ny < height, horizontal[ny * width + x] == 1 else {
                        value = 0
                        break
                    }
                }
                destination[y * width + x] = value
            }
        }
    }
}
