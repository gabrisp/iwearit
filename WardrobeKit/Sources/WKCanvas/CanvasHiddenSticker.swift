import SwiftUI

/// Qué sticker **no** se dibuja en el lienzo ahora mismo.
///
/// ## Para qué
///
/// El editor de texto se presenta con el fondo transparente, a propósito: se
/// escribe viendo el outfit detrás, que es lo que deja elegir el color y la
/// posición sabiendo cómo va a quedar. El efecto secundario es que el mismo
/// texto se veía **dos veces** — el del lienzo, quieto en su sitio, y el del
/// editor, cambiando mientras escribes.
///
/// Esconder el de abajo mientras dura la edición es lo que convierte eso en lo
/// que parece: el texto sale del lienzo, se edita, y vuelve a su posición.
///
/// Va por el entorno y no como parámetro porque quien lo sabe —la pantalla que
/// presenta el editor— y quien lo necesita —cada elemento del lienzo— están
/// separados por tres vistas que no tienen nada que ver con esto.
public extension EnvironmentValues {
    /// El `PersistentIdentifier` del elemento que no se dibuja.
    ///
    /// El identificador **del elemento**, no el del contenido del texto: el de
    /// un `TextSticker` se deriva de lo que pone, así que cambiaría con cada
    /// tecla y no serviría para reconocer al que se está editando.
    @Entry var canvasHiddenItemID: AnyHashable?
}
