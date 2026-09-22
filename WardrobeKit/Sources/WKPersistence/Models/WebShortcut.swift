import Foundation
import SwiftData

/// Una tienda del navegador de importar: por dónde compras.
///
/// ## Por qué está en la base y no en `UserDefaults`
///
/// Porque es tuyo, no de este iPhone. Las tiendas donde compras son parte de
/// cómo usas la app, y al abrirla en el iPad tienen que estar puestas igual que
/// está el armario. En `UserDefaults` se quedaban en un aparato, y además se
/// perdían al reinstalar.
///
/// ## Lo que se guarda es **el enlace entero**
///
/// No el dominio. Un atajo útil no es "zara.com": es la página exacta en la que
/// estabas —la sección de hombre, la lista de novedades, un producto— y eso es
/// una URL con su ruta y sus parámetros. El dominio se saca de ella solo para
/// escribirlo en la píldora.
///
/// ## CloudKit
///
/// Como todo lo que viaja: sin `#Unique` y con **valor por defecto en cada
/// propiedad**, que es lo que CloudKit exige. Dos dispositivos que fijen la
/// misma tienda crean dos filas; se juntan al leer, por dominio.
@Model
public final class WebShortcut {

    /// El enlace completo, tal cual estaba en la barra.
    public var urlString: String = ""
    /// El dominio, sin "www.": es lo que se lee en la píldora.
    public var host: String = ""
    /// El favicon ya descargado, para que la fila no pida nada al abrirse.
    public var iconData: Data?
    /// Fijada a mano con el "+". Las demás son recientes y se caen solas.
    public var isPinned: Bool = false
    public var lastVisitedAt: Date = Date()
    public var createdAt: Date = Date()

    public init(urlString: String, host: String, iconData: Data? = nil, isPinned: Bool = false) {
        self.urlString = urlString
        self.host = host
        self.iconData = iconData
        self.isPinned = isPinned
        self.lastVisitedAt = Date()
        self.createdAt = Date()
    }

    public var url: URL? { URL(string: urlString) }
}

public extension FetchDescriptor where T == WebShortcut {

    /// Todas, de la más reciente a la más vieja.
    ///
    /// Lo fijado se pone delante **al pintar** y no aquí: un `SortDescriptor`
    /// sobre un `Bool` no compila —no es `Comparable`— y ordenar por una fecha
    /// es lo único que la consulta necesita saber.
    static func webShortcuts() -> FetchDescriptor<WebShortcut> {
        FetchDescriptor<WebShortcut>(sortBy: [SortDescriptor(\.lastVisitedAt, order: .reverse)])
    }
}
