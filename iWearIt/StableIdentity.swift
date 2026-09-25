import CloudKit
import CryptoKit
import Foundation
import Security
import WKCore
import WKPersistence

/// **Quién es este usuario, para siempre.**
///
/// Un id que no cambia al reinstalar ni de un iPhone a otro con la misma
/// cuenta, y que es a la vez su usuario de Appwrite y su cliente de
/// RevenueCat: con él el servidor sabe quién gasta qué, y se le puede regalar
/// algo desde el panel.
///
/// De dónde sale, por orden:
///
/// 1. **El llavero**, si ya se guardó uno. Manda siempre: si luego entra en
///    iCloud, sigue siendo el mismo usuario y no dos.
/// 2. **Su cuenta de iCloud** (`ck` + resumen del id de CloudKit): el mismo en
///    todos sus dispositivos.
/// 3. **Uno nuevo** (`kc` + aleatorio), si no hay iCloud.
///
/// Y se guarda en el llavero **sincronizable**: sobrevive a reinstalar y, con
/// el llavero de iCloud, llega a sus otros dispositivos.
///
/// El id no se adivina —128 bits— y no se enseña a nadie: es lo que abre su
/// sesión. Ver `AppwriteAccount`.
actor StableIdentity {

    private static let service = "com.gabrisp.iWearIt.identity"
    private static let account = "userId"

    private var cached: String?
    private var resolving: Task<String, Never>?

    /// El id, resolviéndolo la primera vez. Espera a iCloud unos segundos
    /// como mucho: sin cuenta, o sin red, pasa al aleatorio.
    func id() async -> String {
        if let cached { return cached }
        if let resolving { return await resolving.value }
        let task = Task { await Self.resolve() }
        resolving = task
        let value = await task.value
        cached = value
        resolving = nil
        return value
    }

    /// Lo que ya hay guardado, sin esperar a nada. Para configurar RevenueCat
    /// al arrancar.
    nonisolated static func storedID() -> String? { read() }

    private static func resolve() async -> String {
        if let stored = read() { return stored }
        let id: String
        if let recordName = await cloudRecordName() {
            id = "ck" + digest(recordName)
        } else {
            id = "kc" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        write(id)
        DiagnosticsLog.record("CUENTA", "identidad nueva · \(id.prefix(2))")
        return id
    }

    private static func cloudRecordName() async -> String? {
        let container = CKContainer(identifier: WardrobeStore.cloudContainerIdentifier)
        guard (try? await container.accountStatus()) == .available else { return nil }
        return try? await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask { try await container.userRecordID().recordName }
            // Si iCloud no contesta, no se espera para siempre.
            group.addTask { try await Task.sleep(for: .seconds(6)); return nil }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Llavero

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ id: String) {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(id.utf8),
        ]
        SecItemDelete(item as CFDictionary)
        SecItemAdd(item as CFDictionary, nil)
    }
}
