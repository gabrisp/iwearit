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
