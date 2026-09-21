import Foundation

/// Valores de configuración que **sí** pueden vivir en el binario.
///
/// El endpoint y el project id de Appwrite son públicos por diseño: es lo que
/// cualquier cliente envía en cada petición. Lo que no está aquí, y no estará
/// nunca, es la API key — se puede extraer de un binario en cinco minutos y da
/// escritura sobre todo el proyecto. Esa vive solo en `Tools/.env`, en el Mac.
enum AppConfiguration {
    static let appwriteEndpoint = URL(string: "https://appwrite.repzet.app/v1")!
    static let appwriteProjectID = "iwearit"

    /// Clave pública de RevenueCat.
    ///
    /// Las claves públicas de RevenueCat están **pensadas** para ir en el
    /// cliente: solo permiten leer y comprar en nombre del usuario, no
    /// administrar. Aun así sigue vacía hasta que haya productos configurados.
    static let revenueCatAPIKey = ""

    /// Identificadores de los modelos en el manifiesto.
    enum ModelID {
        static let clothesSegmenter = "clothes-seg"
        static let garmentEmbedder = "garment-embedder"
        static let promptBank = "prompt-bank"
    }
}
