import Foundation
import SwiftData

/// Un dispositivo que participa en la sincronización.
///
/// ## Para qué sirve saberlo
///
/// Para dos cosas, y ninguna es borrar nada. La primera es **verlos**: cuando
/// un iPad no recibe un cambio, lo primero que hay que poder contestar es si
/// ese iPad ha llegado a sincronizar alguna vez y cuándo fue la última. La
/// segunda es tener la base para una limpieza segura el día que se quiera
/// purgar de verdad: saber quién ha visto qué exige saber quién hay.
///
/// ## La identidad
///
/// Un UUID generado en la primera ejecución, **no un identificador del
/// aparato**. Los del hardware ni se deben usar ni son estables, y lo que hace
/// falta aquí no es saber qué iPhone es: es distinguir una instalación de otra.
///
/// Reinstalar la app genera un identificador nuevo, así que aparece un
/// dispositivo más. Es la equivocación correcta: sobra una fila, y ninguna
/// decisión de borrado depende de que esa fila estuviera o no.
@Model
public final class SyncDevice {

    /// Identificador de **instalación**, estable mientras la app siga puesta.
    public var installationID: String = ""
    /// Cómo se llama en la lista. Del modelo del aparato —"iPhone", "iPad"—,
    /// que no identifica a nadie y basta para reconocerlo.
    public var name: String = ""
    public var firstSeenAt: Date = Date()
    public var lastSeenAt: Date = Date()

    /// Cuándo se quitó de la lista desde Ajustes. `nil` = en uso.
    ///
    /// Quitar un dispositivo **no borra ni un dato suyo**: solo deja de
    /// contarse. Si vuelve a abrirse la app en él, vuelve a la lista.
    public var removedAt: Date?

    public init(installationID: String, name: String) {
        self.installationID = installationID
        self.name = name
        self.firstSeenAt = Date()
        self.lastSeenAt = Date()
    }

    public var isActive: Bool { removedAt == nil }

    /// Cuánto lleva sin dar señales.
    ///
    /// Se enseña, no se usa para decidir borrados. Un iPhone que lleva dos años
    /// apagado no puede bloquear una limpieza futura, pero tampoco puede
    /// provocar que se borre nada por el hecho de estar callado.
    public var isStale: Bool {
        Date().timeIntervalSince(lastSeenAt) > 60 * 60 * 24 * 90
    }
}

public extension SyncDevice {

    /// El identificador de esta instalación.
    ///
    /// En `UserDefaults` y no en el llavero: el llavero sobrevive a desinstalar
    /// la app, que suena mejor hasta que te das cuenta de lo que implica —una
    /// instalación nueva heredando la identidad de otra que ya no existe—.
    /// Aquí es preferible que sobre un dispositivo en la lista a que dos
    /// instalaciones distintas se hagan pasar por la misma.
    static var currentInstallationID: String {
        let key = "iWearIt.installationID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}
