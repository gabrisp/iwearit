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
    /// El alto y el ancho son el **hueco**, no la prenda: la imagen se ajusta
    /// dentro conservando su proporción, así que un pantalón estrecho no se
    /// deforma para llenar su caja — solo no se queda pequeño.
    public var transform: ItemTransform {
        switch self {
        // Detrás de todo y a la izquierda: es la pieza más grande del
        // conjunto, y ocupa dos tercios del ancho del papel.
        case .outer:
            ItemTransform(x: 330, y: 600, baseWidth: 660, baseHeight: 740, zIndex: 0)
        // Delante de la chaqueta y a su derecha, como apoyada encima.
        case .top:
            ItemTransform(x: 690, y: 560, baseWidth: 560, baseHeight: 620, zIndex: 1)
        // Las piernas, en su propia banda y rozando el torso.
        case .bottom:
            ItemTransform(x: 450, y: 1230, baseWidth: 600, baseHeight: 780, zIndex: 1)
        case .shoes:
            ItemTransform(x: 620, y: 1560, baseWidth: 520, baseHeight: 340, zIndex: 2)
        // Arriba a la derecha, en el hueco que deja el torso.
        case .accessory:
            ItemTransform(x: 800, y: 220, baseWidth: 340, baseHeight: 320, zIndex: 3)
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
        }
    }
}
