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

    /// Si el armario se replica en iCloud.
    ///
    /// Una preferencia y no una constante porque hay que poder apagarla sin
    /// reinstalar: si algo va mal con CloudKit, apagar esto devuelve la app
    /// exactamente al comportamiento de siempre —mismo fichero, mismos datos—
    /// y nada se pierde por el camino.
    ///
    /// Encendida por defecto. Si no hay sesión de iCloud, si falta el
    /// entitlement o si el contenedor todavía no existe, el arranque cae solo
    /// a local: ver `AppEnvironment.live()`.
    static var syncsWithCloud: Bool {
        get {
            guard UserDefaults.standard.object(forKey: syncKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: syncKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: syncKey) }
    }

    private static let syncKey = "iWearIt.syncsWithCloud"

    /// Clave pública de RevenueCat.
    ///
    /// Las claves públicas de RevenueCat están **pensadas** para ir en el
    /// cliente: solo permiten leer y comprar en nombre del usuario, no
    /// administrar. La que administra —la secreta, la que ajusta saldos— no
    /// está aquí ni puede estarlo.
    ///
    /// Esta empieza por `test_`: es la de la **tienda de pruebas** de
    /// RevenueCat, que simula compras sin App Store Connect y sirve para
    /// montar el paywall entero antes de tener productos de verdad. El día del
    /// lanzamiento se cambia por la `appl_…` y no se toca nada más.
    static let revenueCatAPIKey = "test_pFNpMCuImvcnsGYxAOVYwvSlnlc"

    /// Si esto es una compilación de depuración. Para poner el SDK de la
    /// tienda más hablador sin sembrar `#if DEBUG` por ahí.
    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Identificadores de los modelos en el manifiesto.
    enum ModelID {
        static let clothesSegmenter = "clothes-seg"
        static let garmentEmbedder = "garment-embedder"
        static let promptBank = "prompt-bank"
    }
}
