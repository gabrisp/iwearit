import Foundation
import WKCore

/// Ajustes pequeños que **son tuyos, no de este teléfono**.
///
/// ## Qué va aquí y qué no
///
/// El armario, los outfits y las baldas viajan por CloudKit con SwiftData: son
/// datos, tienen relaciones y hay que mezclarlos. Aquí van las cuatro cosas
/// que no son datos pero tampoco son de un aparato: la ciudad para el tiempo,
/// lo que has ido descartando en la inspiración. En `UserDefaults` se quedaban
/// en el iPhone, y al abrir el iPad la app volvía a no saber dónde vives.
///
/// ## Por qué el almacén clave-valor de iCloud
///
/// Porque es exactamente esto: un megabyte de pares clave-valor que Apple
/// sincroniza sola, sin esquema, sin migraciones y sin conflictos que resolver
/// —gana la última escritura, que para una preferencia es lo correcto—. Meter
/// esto en el modelo de datos obligaría a migrar el esquema y a mezclar filas
/// duplicadas para guardar un diccionario de números.
///
/// ## Y siempre con copia local
///
/// Se escribe en los dos sitios y se lee de iCloud con `UserDefaults` de
/// respaldo: sin sesión de iCloud —o sin red la primera vez— la app sigue
/// recordando lo tuyo en este dispositivo, que es como funcionaba antes.
public enum SyncedStore {

    private static var cloud: NSUbiquitousKeyValueStore { .default }

    /// Pide a iCloud lo que haya nuevo. Barato y no bloquea.
    public static func start() {
        cloud.synchronize()
    }

    public static func data(forKey key: String) -> Data? {
        cloud.data(forKey: key) ?? UserDefaults.standard.data(forKey: key)
    }

    public static func set(_ data: Data?, forKey key: String) {
        if let data {
            cloud.set(data, forKey: key)
            UserDefaults.standard.set(data, forKey: key)
        } else {
            cloud.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
        cloud.synchronize()
    }

    /// Un valor codificable, ida y vuelta.
    public static func value<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public static func setValue<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value else {
            set(nil, forKey: key)
            return
        }
        set(try? JSONEncoder().encode(value), forKey: key)
    }

    /// Avisa cuando **otro dispositivo** cambia algo.
    ///
    /// - Returns: el observador, que hay que conservar mientras interese.
    public static func observeExternalChanges(
        _ handler: @escaping @Sendable @MainActor () -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                DiagnosticsLog.record("ICLOUD", "ajustes cambiados en otro dispositivo")
                handler()
            }
        }
    }
}
