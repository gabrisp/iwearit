import CoreGraphics
import Foundation
import WKCore

/// Un hueco del compositor.
///
/// ## Por qué existen los huecos
///
/// El canvas libre sirve para colocar al milímetro, pero montar un outfit no
/// suele ser eso: es "esta camiseta con estos pantalones", y pedirle al usuario
/// que además decida dónde va cada prenda es trabajo que no quería hacer.
///
/// ## Lo que los hace baratos
///
/// Un hueco **no es un tipo nuevo**: es una transformada preestablecida. El
/// compositor escribe los mismos `CanvasItem` que el canvas, así que "editar
/// libremente" abre el mismo outfit y lo sigue editando. Dos formas de trabajar,
/// un solo modelo.
public enum OutfitSlot: String, CaseIterable, Sendable, Identifiable {
    case top
    case outer
    case bottom
    case shoes
    case accessory

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .top: "Parte superior"
        case .outer: "Chaquetas"
        case .bottom: "Parte inferior"
        case .shoes: "Zapatos"
        case .accessory: "Complementos"
        }
    }

    /// Qué prendas caben aquí.
    ///
    /// Un vestido entra tanto en "superior" como en "inferior": ocupa las dos
    /// zonas del cuerpo, y obligarle a elegir una sería una taxonomía nuestra
    /// que al usuario no le dice nada.
    public var kinds: Set<GarmentKind> {
        switch self {
        case .top: [.upperBody, .wholeBody]
        case .outer: [.outerLayer]
        case .bottom: [.lowerBody, .wholeBody]
        case .shoes: [.feet]
        case .accessory: [.head, .bag, .other]
        }
    }

    /// Dónde cae en el lienzo y **cuánto ocupa**, en coordenadas de
    /// `CanvasSpace` (1000 × 1400).
    ///
    /// ## Quién decide el tamaño
    ///
    /// Esto. Al soltar una prenda en un outfit nadie elige nada: se le da el
    /// hueco que le toca por su tipo, con su sitio y su medida. Las de antes
    /// se quedaban cortas —ninguna pasaba de 420 puntos de ancho sobre un
    /// papel de 1000— así que un conjunto entero ocupaba media hoja y parecía
    /// un muestrario en vez de un look.
    ///
    /// ## El papel se reparte, no se llena de miniaturas
    ///
    /// Cada prenda tiene **su banda** y la ocupa: la chaqueta se lleva dos
    /// tercios del ancho, el pantalón una banda entera para él solo y el
    /// calzado la de abajo. Repartir el papel entre cuatro o cinco piezas y
    /// darle a cada una lo suyo es lo que hace que se vean como ropa; dejarlas
    /// pequeñas en el centro las convierte en iconos de un inventario.
    ///
    /// ## Cómo están repartidos
    ///
    /// Como se mira un conjunto tendido en la cama: el torso arriba, las
    /// piernas debajo, el calzado al fondo y los complementos a un lado. Se
    /// **solapan un poco** a propósito: una chaqueta detrás de la camiseta es
    /// como se ve un conjunto de verdad, y separarlo todo con aire igual lo
    /// convierte en una ficha de inventario.
    ///
    /// ## Por qué los huecos son cuadrados
    ///
    /// Porque la imagen lo es. El recorte normalizado sale de la tubería en un
    /// lienzo cuadrado, y la imagen se ajusta al hueco **conservando su
    /// proporción**: en una caja de 520×340, un cuadrado entra a 340×340 y
    /// sobran 180 puntos de ancho que nadie ve pero que empequeñecen la prenda.
    /// Con la caja cuadrada, la imagen la llena entera y la prenda sale tan
    /// grande como el recorte permite.
    ///
    /// Lo que sigue quedando por dentro es el aire del propio recorte —la
    /// prenda no toca los bordes de su PNG—, y eso no se arregla aquí sino
    /// recortando los márgenes transparentes al colocar. Queda pendiente.
    public var transform: ItemTransform {
        switch self {
        // Detrás de todo y a la izquierda: es la pieza más grande del
        // conjunto.
        case .outer:
            ItemTransform(x: 430, y: 660, baseWidth: 820, baseHeight: 820, zIndex: 0)
        // Delante de la chaqueta y a su derecha, como apoyada encima.
        case .top:
            ItemTransform(x: 620, y: 600, baseWidth: 720, baseHeight: 720, zIndex: 1)
        // Las piernas, en su propia banda y rozando el torso.
        case .bottom:
            ItemTransform(x: 500, y: 1250, baseWidth: 800, baseHeight: 800, zIndex: 1)
        case .shoes:
            ItemTransform(x: 600, y: 1460, baseWidth: 560, baseHeight: 560, zIndex: 2)
        // Arriba a la derecha, en el hueco que deja el torso.
        case .accessory:
            ItemTransform(x: 780, y: 260, baseWidth: 420, baseHeight: 420, zIndex: 3)
        }
    }

    /// El hueco al que va una prenda por su tipo.
    ///
    /// Una capa exterior va a "chaquetas" y no a "superior" aunque ambas cubran
    /// el torso: es la distinción que TinyCLIP decide en el pipeline, y aquí se
    /// respeta.
    public static func slot(for kind: GarmentKind) -> OutfitSlot {
        switch kind {
        case .outerLayer: .outer
        case .upperBody, .wholeBody: .top
        case .lowerBody: .bottom
        case .feet: .shoes
        case .head, .bag, .other: .accessory
        }
    }
}

/// Fondos pastel de la tarjeta de outfit.
///
/// El color lo pone el usuario por outfit. Apagados, pero **no lavados**: la
/// ropa tiene que seguir siendo lo que manda, y a la vez elegir un color tiene
/// que notarse — si no, el selector parece roto.
public enum OutfitBackdrop: String, CaseIterable, Sendable, Identifiable {
    case sand, clay, blush, coral, lilac, sky, teal, sage, olive, slate
    // **Diez más.** Con diez colores y un armario de cien outfits, el papel
    // se repetía cada dos tarjetas y dejaba de decir nada. Estos siguen la
    // misma regla que los otros: tono medio, nada de saturaciones que griten
    // por encima de la ropa —el papel es papel— y ninguno tan claro que se
    // confunda con el fondo de la app.
    case cream, butter, apricot, rose, plum, denim, ice, moss, cocoa, storm

    public var id: String { rawValue }

    /// Componentes sRGB. Se guardan como cadena en el modelo, no como color,
    /// para que el esquema no dependa de la paleta.
    ///
    /// **La misma paleta que las maletas y con el tono que tienen allí.** Los
    /// pasteles de antes estaban tan lavados que `blush` era RGB(239,219,218)
    /// sobre un fondo por defecto de (242,242,247): elegirlo no cambiaba nada
    /// que se pudiera ver, y parecía que el selector estaba roto cuando lo que
    /// fallaba era el color.
    public var components: (red: Double, green: Double, blue: Double) {
        switch self {
        case .sand:  (0.878, 0.816, 0.686)
        case .clay:  (0.816, 0.647, 0.553)
        case .blush: (0.906, 0.729, 0.722)
        case .coral: (0.886, 0.580, 0.518)
        case .lilac: (0.769, 0.733, 0.859)
        case .sky:   (0.639, 0.757, 0.867)
        case .teal:  (0.576, 0.769, 0.757)
        case .sage:  (0.686, 0.765, 0.667)
        case .olive: (0.635, 0.663, 0.486)
        case .slate: (0.667, 0.686, 0.722)
        case .cream:   (0.937, 0.914, 0.855)
        case .butter:  (0.925, 0.867, 0.671)
        case .apricot: (0.941, 0.788, 0.639)
        case .rose:    (0.871, 0.663, 0.686)
        case .plum:    (0.706, 0.624, 0.702)
        case .denim:   (0.549, 0.639, 0.745)
        case .ice:     (0.769, 0.843, 0.855)
        case .moss:    (0.596, 0.686, 0.588)
        case .cocoa:   (0.729, 0.635, 0.569)
        case .storm:   (0.573, 0.600, 0.643)
        }
    }

    /// Claridad percibida, 0-1. La de siempre: el ojo pesa el verde mucho más
    /// que el azul, y una media aritmética diría que un azul marino y un
    /// verde oliva son igual de oscuros.
    public var luminance: Double {
        let c = components
        return 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
    }

    /// Tono, 0-1, dando la vuelta al círculo. Sirve para saber si dos colores
    /// son **el mismo color** aunque uno sea más claro.
    public var hue: Double {
        let c = components
        let maximum = max(c.red, c.green, c.blue)
        let minimum = min(c.red, c.green, c.blue)
        let delta = maximum - minimum
        guard delta > 0.0001 else { return 0 }
        let hue: Double
        switch maximum {
        case c.red: hue = (c.green - c.blue) / delta
        case c.green: hue = 2 + (c.blue - c.red) / delta
        default: hue = 4 + (c.red - c.green) / delta
        }
        return (hue / 6).truncatingRemainder(dividingBy: 1) + (hue < 0 ? 1 : 0)
    }

    /// Cuánto color tiene. Un gris no compite con nada, así que pega con todo.
    public var saturation: Double {
        let c = components
        let maximum = max(c.red, c.green, c.blue)
        guard maximum > 0.0001 else { return 0 }
        return (maximum - min(c.red, c.green, c.blue)) / maximum
    }
}
