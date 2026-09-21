import CoreText
import Foundation
import os

/// Registra las tipografías empotradas.
///
/// En tiempo de ejecución y no por `UIAppFonts` en el Info.plist: el proyecto
/// genera su Info.plist desde los ajustes de compilación, y Xcode **no**
/// reconoce `INFOPLIST_KEY_UIAppFonts` como clave conocida — los ficheros
/// acaban en el bundle pero la clave nunca llega al plist, así que las fuentes
/// no se registran y todo cae silenciosamente a la del sistema. Comprobado.
///
/// Registrar a mano cuesta unos milisegundos al arrancar y funciona siempre.
public enum WKFonts {
    private static let logger = Logger(subsystem: "com.gabrisp.iWearIt", category: "fonts")

    /// Los pesos que la app usa. Registrarlos todos de una vez evita que una
    /// pantalla se dibuje con Inter y la siguiente con la del sistema porque su
    /// peso no estaba cargado todavía.
    static let fileNames = [
        "PlusJakartaSans-Light", "PlusJakartaSans-Regular", "PlusJakartaSans-Medium",
        "PlusJakartaSans-SemiBold", "PlusJakartaSans-Bold",
    ]

    /// Si el registro fue bien. Si no, `WK.Font` usa la del sistema.
    ///
    /// Aislado al `MainActor` y no `nonisolated`: se escribe una vez al
    /// arrancar y se lee desde cada `body`, que ya corre ahí. Marcarlo
    /// `nonisolated(unsafe)` sería mentir sobre una carrera que no existe pero
    /// que el compilador no puede descartar solo.
    @MainActor public private(set) static var isRegistered = false

    /// Idempotente: llamarlo dos veces no duplica nada.
    @MainActor
    public static func register(in bundle: Bundle = .main) {
        guard !isRegistered else { return }

        let urls = fileNames.compactMap {
            bundle.url(forResource: $0, withExtension: "ttf")
        }
        guard urls.count == fileNames.count else {
            logger.error("Faltan tipografías: \(fileNames.count - urls.count, privacy: .public)")
            return
        }

        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { _, _ in true }
        isRegistered = true
    }
}
