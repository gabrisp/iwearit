import Foundation
import Observation
import UIKit
import WKCore
import WKServices

/// **Los avisos grandes**: un regalo que reclamar, o una prueba que ha fallado
/// y cuya moneda ya se ha devuelto. De uno en uno, en el centro de la
/// pantalla. Ver `NoticeOverlay`.
///
/// Los regalos llegan por push —silencioso siempre, que despierta la app
/// aunque no haya permiso de avisos— y además se miran al abrir la app y al
/// volver a ella: si el push se perdió, el regalo sigue esperando.
@MainActor
@Observable
final class NoticeCenter {

    enum Notice: Identifiable, Equatable {
        /// Un regalo desde el panel: se queda hasta que se reclama.
        case grant(AppwriteAccount.Grant)
        /// Falló y no se cobró: se lee y se va.
        case refunded(currency: StoreIDs.Currency)

        var id: String {
            switch self {
            case let .grant(grant): "grant-\(grant.id)"
            case let .refunded(currency): "refund-\(currency.rawValue)"
            }
        }
    }

    private(set) var current: Notice?
    private var queue: [Notice] = []
    /// Reclamando ahora mismo.
    private(set) var isClaiming = false
    /// Recién reclamado: el icono se transforma en el visto antes de irse.
    private(set) var didClaim = false

    private var account: AppwriteAccount?
    private var store: Store?
    private var isChecking = false

    func attach(account: AppwriteAccount?, store: Store) {
        self.account = account
        self.store = store
    }

    /// Mira si hay regalos esperando.
    func checkGrants() async {
        guard let account, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let grants = try await account.pendingGrants()
            for grant in grants where !isQueued(.grant(grant)) {
                enqueue(.grant(grant))
            }
        } catch {
            DiagnosticsLog.record("AVISOS", "no se pudieron mirar los regalos: \(error)")
        }
    }

    func show(_ notice: Notice) { enqueue(notice) }

    func claim() async {
        guard case let .grant(grant) = current, let account, !isClaiming else { return }
        isClaiming = true
        defer { isClaiming = false }
        do {
            try await account.claim(grant.id)
            didClaim = true
            await store?.refreshCredits()
            try? await Task.sleep(for: .seconds(1.3))
            dismiss()
        } catch {
            DiagnosticsLog.record("AVISOS", "no se pudo reclamar: \(error)", isProblem: true)
        }
    }

    func dismiss() {
        didClaim = false
        current = queue.isEmpty ? nil : queue.removeFirst()
    }

    private func isQueued(_ notice: Notice) -> Bool {
        current?.id == notice.id || queue.contains { $0.id == notice.id }
    }

    private func enqueue(_ notice: Notice) {
        guard !isQueued(notice) else { return }
        if current == nil { current = notice } else { queue.append(notice) }
    }
}

extension Notification.Name {
    /// Un push de la app: un regalo, normalmente. Ver `AppDelegate`.
    static let snazzyRemoteNotice = Notification.Name("snazzy.remoteNotice")
    /// El token de avisos de este dispositivo. Ver `AppDelegate`.
    static let snazzyPushToken = Notification.Name("snazzy.pushToken")
}
