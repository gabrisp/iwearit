import CloudKit
import CoreData
import Foundation
import Observation
import SwiftData
import SwiftUI
import WKCore
import WKPersistence

/// En qué anda la sincronización.
///
/// Lo justo para poder enseñarlo y para poder diagnosticar por qué un iPad no
/// recibió algo. **Sin porcentajes inventados**: CloudKit no dice cuánto queda,
/// así que un "63% sincronizado" sería una animación mintiendo.
enum CloudSyncStatus: Equatable {
    /// Al día, o al menos sin nada en marcha.
    case idle
    /// Subiendo o bajando ahora mismo.
    case syncing
    /// Sin red. Los datos locales siguen estando, que es lo importante.
    case offline
    /// No hay iCloud disponible: sesión cerrada, cuenta restringida, o el
    /// usuario no quiere. **No es un error**: la app funciona igual.
    case unavailable(String)
    case failed(String)

    var isBusy: Bool { self == .syncing }
}

/// Lo que la app sabe de iCloud.
///
/// ## Por qué esto es tan pequeño
///
/// Porque `NSPersistentCloudKitContainer` —que es lo que SwiftData usa por
/// debajo— ya hace el trabajo: sube, baja, mezcla por propiedad, se suscribe a
/// los cambios del otro dispositivo y reintenta cuando vuelve la red. Lo que
/// falta no es un motor de sincronización, es **saber qué está pasando** y
/// avisar a quien lo necesite.
///
/// Así que esto solo escucha:
///
/// - los eventos del contenedor, que dicen cuándo empieza y acaba cada
///   importación o exportación y si falló;
/// - el estado de la cuenta de iCloud, para distinguir "no hay nada que
///   sincronizar" de "no hay sesión";
/// - los cambios remotos ya aplicados, para resolver el conflicto que la
///   mezcla por propiedad no sabe resolver sola: una edición que llega después
///   de un borrado.
/// Lo que de un evento del contenedor hace falta saber, como valor.
///
/// El evento de CloudKit no es `Sendable` y llega en el hilo que sea; esto es
/// lo que cruza a la vista.
private struct CloudEventSummary: Sendable {
    let label: String
    /// Si es una importación: es la única que trae datos nuevos del otro
    /// dispositivo, y por tanto la única que puede haber duplicado algo.
    let isImport: Bool
    let endDate: Date?
    /// El fallo, ya traducido. **Como texto y código y no como `Error`**: un
    /// `Error` no es `Sendable`, y lo único que se necesita de él al otro lado
    /// es qué decirle al usuario y si es culpa de la red.
    let failure: String?
    let code: CKError.Code?

}

@MainActor
@Observable
final class CloudSync {

    private(set) var status: CloudSyncStatus = .idle
    private(set) var lastSyncedAt: Date?
    /// Si la app se abrió con la réplica encendida. Se decide al arrancar y no
    /// cambia en caliente: cambiarla exige reabrir el store.
    let isEnabled: Bool

    private let container: ModelContainer
    private var observers: [NSObjectProtocol] = []

    /// Hay cuenta de iCloud **y la app se abrió sin ella**.
    ///
    /// Es el caso de "no había iCloud cuando arrancaste y ahora sí": el store
    /// se abrió en local, y encender la réplica exige volver a abrirlo. En vez
    /// de hacerlo por la cara —que reconstruye el contenedor debajo de la
    /// pantalla que estés mirando— se pregunta.
    private(set) var canEnableNow = false

    /// Si ya se ha ofrecido encender la réplica en **esta** ejecución.
    ///
    /// Estática porque la pregunta sobrevive al objeto: contestar que sí crea
    /// un `CloudSync` nuevo, y es justo ese el que volvía a preguntar.
    private static var hasOffered = false

    /// **Ha terminado de bajar lo del otro dispositivo.**
    ///
    /// Una sola señal y no un goteo: `NSPersistentStoreRemoteChange` llega
    /// decenas de veces durante una importación —una por tanda de filas— y
    /// mirar el armario entero en cada una es trabajo repetido mientras el
    /// usuario lo tiene delante. CloudKit avisa cuando la importación acaba, y
    /// ese es el momento en que hay algo nuevo que mirar y solo pasa una vez.
    var onImportFinished: (@MainActor () -> Void)?

    /// Por qué no se pudo abrir con réplica, si se intentó y falló.
    ///
    /// No es lo mismo que no haber cuenta: si la había y el almacén no abrió
    /// —un esquema que CloudKit no acepta, un permiso que falta— ofrecer
    /// "encender iCloud" es ofrecer algo que va a fallar igual. Preguntar en
    /// cada arranque por eso era lo que convertía un fallo en un bucle.
    private(set) var openFailure: String?

    init(container: ModelContainer, isEnabled: Bool, openFailure: String? = nil) {
        self.container = container
        self.isEnabled = isEnabled
        self.openFailure = openFailure
        if isEnabled {
            observe()
        } else if let openFailure {
            // Se intentó y no abrió: es un fallo, no una ausencia.
            status = .failed(openFailure)
            observeAccount()
        } else {
            status = .unavailable("sin iCloud")
            // **La cuenta se vigila igual.** Si no hay sesión al arrancar se
            // sigue en local, pero cuando aparece hay que poder ofrecerlo: sin
            // este observador, el usuario tendría que adivinar que ahora sí
            // podría sincronizar.
            observeAccount()
        }
        Task { await refreshAccountStatus() }
    }

    func dismissEnablePrompt() {
        canEnableNow = false
    }

    deinit {
        // Los observadores no se quitan en `deinit` por actor isolation; se
        // van con el objeto, que vive lo que vive la app.
    }

    // MARK: Escuchar

    private func observe() {
        let center = NotificationCenter.default

        // 1. Los eventos del contenedor: setup, import, export.
        observers.append(
            center.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                // El evento se extrae **aquí**, en el hilo que lo entrega, y
                // lo que cruza a la vista es un valor: pasar el `Notification`
                // entero a otro aislamiento es justo lo que Swift 6 marca como
                // carrera.
                guard
                    let event = notification.userInfo?[
                        NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                    ] as? NSPersistentCloudKitContainer.Event
                else { return }

                // Los campos se leen aquí mismo y lo que cruza al hilo
                // principal son tres valores. Sacar el evento entero —o
                // pasárselo a un inicializador— es lo que Swift 6 marca como
                // carrera: su contenido no es `Sendable`.
                let label = switch event.type {
                case .setup: "preparación"
                case .import: "importación"
                case .export: "exportación"
                @unknown default: "trabajo"
                }
                let summary = CloudEventSummary(
                    label: label,
                    isImport: event.type == .import,
                    endDate: event.endDate,
                    failure: event.error.map { ($0 as NSError).localizedDescription },
                    code: (event.error as? CKError)?.code
                )
                MainActor.assumeIsolated { self?.handle(summary) }
            }
        )

        // 2. Cambios remotos ya aplicados al store. SwiftData los mezcla solo;
        //    lo que hace falta aquí es la política de conflicto que la mezcla
        //    por propiedad no puede decidir. Ver `reconcileDeletions`.
        observers.append(
            center.addObserver(
                forName: .NSPersistentStoreRemoteChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lastSyncedAt = Date()
                    self.reconcileDeletions()
                }
            }
        )

        // 3. Y la cuenta.
        observeAccount()
    }

    /// Cambio de cuenta de iCloud: sesión cerrada, otra cuenta, o
    /// restricciones parentales.
    private func observeAccount() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .CKAccountChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { await self?.refreshAccountStatus() }
            }
        )
    }

    private func handle(_ event: CloudEventSummary) {
        guard let ended = event.endDate else {
            status = .syncing
            return
        }

        if let failure = event.failure {
            status = describe(code: event.code, message: failure)
            DiagnosticsLog.record("ICLOUD", "\(event.label) falló: \(failure)", isProblem: true)
            return
        }

        status = .idle
        lastSyncedAt = ended
        DiagnosticsLog.record("ICLOUD", "\(event.label) terminado")
        // Solo cuando ha bajado algo: ver `onImportFinished`.
        if event.isImport { onImportFinished?() }
    }

    /// Un error de CloudKit, traducido a lo único que hay que decidir: si esto
    /// es un problema del usuario, de la red, o nuestro.
    private func describe(code: CKError.Code?, message: String) -> CloudSyncStatus {
        guard let code else {
            // El fallo de arranque más común no llega como `CKError` sino como
            // error de Core Data: 134400 es "no hay sesión de iCloud". Sin
            // traducirlo, Ajustes enseñaba "Error de Cocoa 134400", que no le
            // dice nada a nadie.
            return message.contains("134400") || message.lowercased().contains("icloud account")
                ? .unavailable("sin sesión de iCloud")
                : .failed(message)
        }
        return switch code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            .offline
        case .notAuthenticated:
            .unavailable("inicia sesión en iCloud para sincronizar")
        case .quotaExceeded:
            .unavailable("no queda espacio en tu iCloud")
        case .managedAccountRestricted, .permissionFailure:
            .unavailable("esta cuenta no permite iCloud")
        default:
            .failed(message)
        }
    }

    // MARK: La cuenta

    func refreshAccountStatus() async {
        do {
            let account = try await CKContainer(
                identifier: WardrobeStore.cloudContainerIdentifier
            ).accountStatus()

            switch account {
            case .available:
                // Hay cuenta pero la app se abrió sin réplica: se ofrece.
                // **Una vez por arranque, y no una vez por intento.**
                //
                // Decir que sí reconstruye el entorno entero, y si esa vez no
                // se pudo abrir con réplica —falta el permiso, CloudKit está
                // caído, el contenedor todavía no existe— la app vuelve a
                // abrirse en local con una cuenta disponible delante: es decir,
                // exactamente la condición que levanta esta pregunta. Sin esta
                // marca, contestar que sí la volvía a hacer, y otra vez, y otra.
                // Y solo si no se intentó ya y falló: ver `openFailure`.
                if !isEnabled, AppConfiguration.syncsWithCloud, !Self.hasOffered, openFailure == nil {
                    Self.hasOffered = true
                    canEnableNow = true
                }
                if isEnabled, case .unavailable = status { status = .idle }
            case .noAccount:
                status = .unavailable("sin sesión de iCloud")
            case .restricted:
                status = .unavailable("iCloud restringido en este dispositivo")
            case .couldNotDetermine, .temporarilyUnavailable:
                status = .offline
            @unknown default:
                break
            }
        } catch {
            status = .offline
        }
        DiagnosticsLog.record("ICLOUD", "estado de la cuenta: \(status)")
    }

    // MARK: La política de conflicto

    /// Devuelve lo que un dispositivo borró y otro siguió editando.
    ///
    /// ## Por qué hace falta hacerlo a mano
    ///
    /// CloudKit mezcla **por propiedad**: si un iPhone marca `deletedAt` y un
    /// iPad cambia el nombre, las dos cosas llegan y conviven. El objeto acaba
    /// con una marca de borrado *y* con una edición posterior, y nadie decide
    /// cuál gana — porque para la base no hay conflicto, son campos distintos.
    ///
    /// La regla de esta app sí decide, y siempre en la misma dirección:
    /// **conservar**. Si alguien lo tocó después de marcarlo, vuelve.
    private func reconcileDeletions() {
        let context = container.mainContext
        var restored = 0

        // Cuatro consultas escritas a mano y no una genérica: `#Predicate`
        // necesita un tipo concreto para traducir el key path a una columna,
        // así que un `revive<T: SoftDeletable>` no llega a compilar.
        let garments = try? context.fetch(
            FetchDescriptor<Garment>(predicate: #Predicate { $0.deletedAt != nil })
        )
        let outfits = try? context.fetch(
            FetchDescriptor<Outfit>(predicate: #Predicate { $0.deletedAt != nil })
        )
        let suitcases = try? context.fetch(
            FetchDescriptor<Suitcase>(predicate: #Predicate { $0.deletedAt != nil })
        )
        let categories = try? context.fetch(
            FetchDescriptor<GarmentCategory>(predicate: #Predicate { $0.deletedAt != nil })
        )

        let marked: [any SoftDeletable] =
            (garments ?? []) + (outfits ?? []) + (suitcases ?? []) + (categories ?? [])
        for object in marked where object.modifiedAt >= (object.deletedAt ?? .distantFuture) {
            object.restore()
            restored += 1
        }

        guard restored > 0 else { return }
        try? context.save()
        DiagnosticsLog.record(
            "ICLOUD",
            "\(restored) objeto(s) devueltos: se editaron después de marcarse para borrar"
        )
    }
}
