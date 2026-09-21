import Foundation
import SwiftData

/// Los bytes de una imagen, **dentro de la base**.
///
/// ## Por qué existe, si ya hay ficheros
///
/// Porque los ficheros no viajan. Las prendas guardan **claves** —el sha256 de
/// su recorte— y los píxeles viven en `Application Support`. Eso está bien y se
/// queda: leer del disco es más rápido que leer de una base, y el
/// direccionamiento por contenido hace que dos recortes iguales compartan
/// fichero sin esfuerzo.
///
/// Pero al sincronizar, el otro dispositivo recibe la prenda y no los píxeles:
/// un armario entero de claves que no resuelven. Y la salida no es subir los
/// ficheros a mano —eso es reimplementar CloudKit—, sino que los bytes formen
/// parte de lo que ya se sincroniza solo.
///
/// `.externalStorage` es lo que hace esto razonable: SwiftData guarda el blob
/// **fuera** de la base de datos y CloudKit lo sube como `CKAsset`, que es el
/// mecanismo pensado para esto. La base no engorda y la sincronización no
/// manda un HEIC dentro de una fila.
///
/// ## Qué se guarda y qué no
///
/// Solo `display` y `catalog`. La miniatura no: se saca de `display` en el
/// propio dispositivo en milisegundos, y subir una tercera copia de cada prenda
/// es gastar cuota de iCloud del usuario para no ahorrar nada.
@Model
public final class GarmentImageBlob {

    /// El sha256 que ya usa el `ImageStore`. Es la identidad de la imagen: dos
    /// dispositivos que recorten lo mismo producen la misma clave, así que la
    /// misma foto no se sube dos veces.
    public var key: String = ""
    /// `display` o `catalog`.
    public var variantRaw: String = ""

    /// Los bytes. Fuera de la base y como `CKAsset` al sincronizar.
    @Attribute(.externalStorage)
    public var data: Data = Data()

    public var createdAt: Date = Date()

    public init(key: String, variantRaw: String, data: Data) {
        self.key = key
        self.variantRaw = variantRaw
        self.data = data
        self.createdAt = Date()
    }
}
