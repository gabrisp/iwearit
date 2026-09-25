import Foundation
import WKCore

/// **La sesión de Appwrite de este usuario, y solo de este.**
///
/// Antes cada instalación abría una sesión anónima —un usuario nuevo en
/// Appwrite cada vez—, así que no había forma de saber quién gastaba qué ni de
/// regalarle nada. Ahora el usuario es el id estable que decide la app (ver
/// `StableIdentity`): la función `account` lo crea si no existe y devuelve un
/// token de un solo uso, y con él se abre la sesión. Ese mismo id es su
/// cliente de RevenueCat, así que el servidor sabe a quién cobrar.
///
/// Si al arrancar hay una sesión de otro usuario —la anónima de antes—, se
/// cierra y se abre la buena.
public actor AppwriteAccount {

    private let endpoint: URL
    private let projectID: String
    private let session: URLSession
    private let userID: @Sendable () async -> String?

    private var verifiedUserID: String?
    /// Una sola apertura en vuelo: varias peticiones a la vez esperan a la
    /// misma en vez de abrir cada una la suya.
    private var opening: Task<Void, Error>?

    public init(
        endpoint: URL,
        projectID: String,
        session: URLSession = .shared,
        userID: @escaping @Sendable () async -> String?
    ) {
        self.endpoint = endpoint
        self.projectID = projectID
        self.session = session
        self.userID = userID
    }

    /// Deja la sesión abierta con el usuario estable.
    public func ensureSession() async throws {
        guard let id = await userID() else {
            throw ClothingResolverError.transport("sin identidad todavía")
        }
        if verifiedUserID == id { return }
        if let opening { return try await opening.value }
        let task = Task { try await self.open(as: id) }
        opening = task
        defer { opening = nil }
        try await task.value
    }

    private func open(as id: String) async throws {
        if let current = await currentUserID() {
            if current == id {
                verifiedUserID = id
                return
            }
            // La sesión anónima de antes, u otro usuario: fuera.
            _ = try? await send("DELETE", "account/sessions/current")
            DiagnosticsLog.record("CUENTA", "cerrada la sesión de otro usuario")
        }

        let answer = try await execute(["action": "auth", "userId": id])
        guard let secret = answer["secret"] as? String else {
            throw ClothingResolverError.badResponse("auth sin token")
        }
        let (_, status) = try await send(
            "POST", "account/sessions/token", body: ["userId": id, "secret": secret]
        )
        guard status == 201 || status == 200 else {
            throw ClothingResolverError.transport("no se pudo abrir la sesión (\(status))")
        }
        verifiedUserID = id
        DiagnosticsLog.record("CUENTA", "sesión abierta · \(id.prefix(10))…")
    }

    // MARK: Regalos

    /// Un regalo por reclamar.
    public struct Grant: Sendable, Identifiable, Equatable {
        public let id: String
        /// `MEJ` o `PRU`, las monedas de RevenueCat.
        public let currency: String
        public let amount: Int
        public let message: String?
    }

    public func pendingGrants() async throws -> [Grant] {
        try await ensureSession()
        let answer = try await execute(["action": "pending"])
        let items = answer["grants"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard
                let id = item["id"] as? String,
                let currency = item["currency"] as? String,
                let amount = item["amount"] as? Int
            else { return nil }
            return Grant(id: id, currency: currency, amount: amount, message: item["message"] as? String)
        }
    }

    public func claim(_ grantID: String) async throws {
        try await ensureSession()
        let answer = try await execute(["action": "claim", "grantId": grantID])
        guard answer["claimed"] as? Bool == true else {
            throw ClothingResolverError.badResponse(answer["error"] as? String ?? "claim")
        }
    }

    // MARK: Avisos

    /// Apunta este dispositivo para los avisos push del usuario. Un destino por
    /// dispositivo —`targetID` fijo—: si ya existe, se le cambia el token.
    public func registerPush(token: String, targetID: String, providerID: String = "apns") async {
        do {
            try await ensureSession()
            let (_, status) = try await send("POST", "account/targets/push", body: [
                "targetId": targetID, "identifier": token, "providerId": providerID,
            ])
            if status == 409 {
                _ = try await send("PUT", "account/targets/\(targetID)/push", body: ["identifier": token])
            }
            DiagnosticsLog.record("CUENTA", "avisos push apuntados (\(status))")
        } catch {
            DiagnosticsLog.record("CUENTA", "no se pudo apuntar el push: \(error)", isProblem: true)
        }
    }

    // MARK: HTTP

    private func currentUserID() async -> String? {
        guard
            let (data, status) = try? await send("GET", "account"),
            status == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["$id"] as? String
    }

    /// Ejecuta la función `account` y devuelve lo que contestó.
    private func execute(_ body: [String: Any]) async throws -> [String: Any] {
        let inner = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
        let (data, status) = try await send(
            "POST", "functions/account/executions", body: ["body": inner, "async": false]
        )
        guard
            status == 201 || status == 200,
            let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let response = envelope["responseBody"] as? String,
            let answer = try? JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any]
        else {
            throw ClothingResolverError.transport("cuenta: HTTP \(status)")
        }
        if let code = envelope["responseStatusCode"] as? Int, code >= 400 {
            throw ClothingResolverError.badResponse(answer["error"] as? String ?? "HTTP \(code)")
        }
        return answer
    }

    private func send(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> (Data, Int) {
        var request = URLRequest(url: endpoint.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(projectID, forHTTPHeaderField: "X-Appwrite-Project")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
