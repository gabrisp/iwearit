import Foundation
import WKCore

/// Pregunta a la Function de Appwrite qué es esta prenda.
///
/// ## El camino, y por qué es ese
///
///     iPhone ──► Function de Appwrite ──► OpenRouter
///
/// Nunca `iPhone ──► OpenRouter`. La clave de OpenRouter vive **solo** como
/// variable de entorno de la función; un `.ipa` es un zip que cualquiera abre,
/// así que una clave embarcada es una clave publicada y de las que se cobran
/// por uso.
///
/// ## Qué se manda
///
/// El recorte ya normalizado y nada más. No hay un camino para mandar la foto
/// original porque `RemoteGarmentQuery` no tiene dónde meterla: la privacidad
/// no es una regla que se aplica más arriba y se puede olvidar, es una forma
/// que no compila de otra manera.
///
/// ## Sesión anónima
///
/// La función se ejecuta con permiso `users`, no `any`. La app abre una sesión
/// anónima —sin login, sin pedir nada al usuario— y a partir de ahí sus
/// peticiones van como usuario y no como invitado. No es autenticación de
/// verdad, pero es la diferencia entre un endpoint cerrado y uno abierto a
/// todo el que sepa el id del proyecto.
///
/// **Por cookie, no por cabecera.** `X-Appwrite-Session` existe, pero necesita
/// que el secreto venga en la respuesta, y el servidor solo lo entrega a
/// plataformas registradas: aquí llega vacío y la petición siguiente vuelve a
/// ser de invitado. Lo que sí funciona —comprobado contra este servidor— es lo
/// que hace cualquier navegador: el servidor manda `Set-Cookie` y `URLSession`
/// la guarda y la reenvía sola. Cero código de sesión, y además persiste entre
/// arranques porque `HTTPCookieStorage` escribe a disco.
public actor RemoteClothingResolver: ClothingResolving {

    private let endpoint: URL
    private let projectID: String
    private let functionID: String
    private let session: URLSession
    /// La sesión del usuario estable. Ver `AppwriteAccount`. Sin ella, la
    /// sesión anónima de antes.
    private let account: AppwriteAccount?

    /// Cuántas preguntas pueden estar en el aire a la vez.
    ///
    /// Dos. En un escaneo con quince prendas dudosas, soltarlas todas de golpe
    /// es quince peticiones facturables simultáneas y un servidor contestando
    /// 429 a la mitad. De dos en dos tarda más y llega entero.
    public static let maximumConcurrent = 2
    private var inFlight = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init(
        endpoint: URL,
        projectID: String,
        functionID: String = "resolve-garment",
        session: URLSession = .shared,
        account: AppwriteAccount? = nil
    ) {
        self.endpoint = endpoint
        self.projectID = projectID
        self.functionID = functionID
        self.session = session
        self.account = account
    }

    public func resolve(_ query: RemoteGarmentQuery) async throws -> RemoteGarmentAnswer {
        await acquireSlot()
        defer { releaseSlot() }

        try await ensureSession()
        let body = Payload(
            imageBase64: query.imageJPEG.base64EncodedString(),
            kind: query.kind,
            subcategory: query.subcategory,
            dominantColor: query.dominantColor,
            brandCandidates: query.brandCandidates
        )

        var request = URLRequest(
            url: endpoint.appending(path: "functions/\(functionID)/executions")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(projectID, forHTTPHeaderField: "X-Appwrite-Project")

        // El cuerpo de la ejecución va como **cadena** dentro del sobre de
        // Appwrite: la función recibe `req.body` y lo parsea. Mandarlo como
        // objeto anidado hace que llegue `[object Object]`.
        let encoder = JSONEncoder()
        let inner = String(decoding: try encoder.encode(body), as: UTF8.self)
        request.httpBody = try encoder.encode(
            Execution(body: inner, async: false, path: "/", method: "POST")
        )

        let start = ContinuousClock.now
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClothingResolverError.transport(String(localized: "wkservices.remoteclothingresolver.noResponse", defaultValue: "no response", bundle: .module))
        }
        guard http.statusCode == 200 || http.statusCode == 201 else {
            if http.statusCode == 429 { throw ClothingResolverError.rateLimited }
            throw ClothingResolverError.transport("HTTP \(http.statusCode)")
        }

        let envelope = try JSONDecoder().decode(ExecutionResult.self, from: data)
        guard envelope.responseStatusCode == 200,
              let payload = envelope.responseBody.data(using: .utf8)
        else {
            DiagnosticsLog.record(
                "REMOTO",
                "la función contestó \(envelope.responseStatusCode): \(envelope.responseBody.prefix(160))",
                isProblem: true
            )
            throw ClothingResolverError.badResponse(envelope.responseBody)
        }

        let answer = try JSONDecoder().decode(RemoteGarmentAnswer.self, from: payload)
        DiagnosticsLog.record(
            "REMOTO",
            "\(answer.kind ?? "?") / \(answer.subcategory ?? "?")"
                + " · marca \(answer.brand ?? "ninguna") · \(start.duration(to: .now))"
        )
        return answer
    }

    // Síncrona, antes: se cortaba a los 30 s.
    // public func restyle(_ imageJPEG: Data) async throws -> Data {
    //     await acquireSlot()
    //     defer { releaseSlot() }
    //     try await ensureSession()

    //     let start = ContinuousClock.now
    //     let body = RestylePayload(action: "restyle", imageBase64: imageJPEG.base64EncodedString())
    //     // Más margen que al describir: describir son 1,5 s y **dibujar** son
    //     // entre cinco y cuarenta, según el modelo y la carga del proveedor.
    //     let answer: RestyleAnswer = try await execute(body: body, timeout: 150)

    //     guard let data = Data(base64Encoded: answer.imageBase64) else {
    //         throw ClothingResolverError.badResponse("la imagen no venía en base64")
    //     }
    //     DiagnosticsLog.record(
    //         "CATÁLOGO",
    //         "generada en \(start.duration(to: .now)) · \(data.count / 1024) KB"
    //             + " · \(answer.tokens.map(String.init) ?? "?") tokens"
    //     )
    //     return data
    // }

    public func restyle(_ imageJPEG: Data) async throws -> Data {
        await acquireSlot()
        defer { releaseSlot() }
        try await ensureSession()

        let start = ContinuousClock.now
        let jobID = Self.newJobID()
        let body = RestylePayload(
            action: "restyle", imageBase64: imageJPEG.base64EncodedString(), jobID: jobID
        )
        // **Por encargo.** Dibujar con fondo transparente tarda 20-25 s, y
        // Appwrite corta las ejecuciones síncronas a los 30: un día lento
        // y se perdía la imagen ya pagada. Ver `runJob`.
        let data = try await runJob(body: body, jobID: jobID, timeout: 150)
        DiagnosticsLog.record(
            "CATÁLOGO", "generada en \(start.duration(to: .now)) · \(data.count / 1024) KB"
        )
        return data
    }

    public func tryOn(
        personJPEG: Data?,
        bodyJPEGs: [Data],
        personDescription: String,
        garmentsPNG: [Data],
        direction: TryOnDirection
    ) async throws -> Data {
        await acquireSlot()
        defer { releaseSlot() }
        try await ensureSession()

        let start = ContinuousClock.now
        let jobID = Self.newJobID()
        let body = TryOnPayload(
            action: "tryon",
            personBase64: personJPEG?.base64EncodedString(),
            bodyPhotosBase64: bodyJPEGs.map { $0.base64EncodedString() },
            personDescription: personDescription,
            garmentsBase64: garmentsPNG.map { $0.base64EncodedString() },
            scene: direction.scene,
            sceneDescription: direction.sceneDescription,
            pose: direction.pose,
            poseDescription: direction.poseDescription,
            jobID: jobID
        )
        // Lo más lento que pide la app: varias imágenes de entrada y una de
        // salida. **Por encargo**: en síncrono Appwrite lo cortaba a los 30 s
        // y el probador se quedaba sin resultado. Ver `runJob`.
        // let answer: RestyleAnswer = try await execute(body: body, timeout: 180)
        let data = try await runJob(body: body, jobID: jobID, timeout: 180)
        DiagnosticsLog.record(
            "PROBADOR",
            "generada en \(start.duration(to: .now)) · \(data.count / 1024) KB"
        )
        return data
    }

    /// El sobre de Appwrite, que es el mismo para las dos acciones.
    private func execute<Body: Encodable, Answer: Decodable>(
        body: Body,
        timeout: TimeInterval
    ) async throws -> Answer {
        var request = URLRequest(
            url: endpoint.appending(path: "functions/\(functionID)/executions")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(projectID, forHTTPHeaderField: "X-Appwrite-Project")

        let encoder = JSONEncoder()
        let inner = String(decoding: try encoder.encode(body), as: UTF8.self)
        request.httpBody = try encoder.encode(
            Execution(body: inner, async: false, path: "/", method: "POST")
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClothingResolverError.transport(String(localized: "wkservices.remoteclothingresolver.noResponse", defaultValue: "no response", bundle: .module))
        }
        guard http.statusCode == 200 || http.statusCode == 201 else {
            if http.statusCode == 429 { throw ClothingResolverError.rateLimited }
            throw ClothingResolverError.transport("HTTP \(http.statusCode)")
        }

        let envelope = try JSONDecoder().decode(ExecutionResult.self, from: data)
        guard envelope.responseStatusCode == 200,
              let payload = envelope.responseBody.data(using: .utf8)
        else {
            DiagnosticsLog.record(
                "REMOTO",
                "la función contestó \(envelope.responseStatusCode): \(envelope.responseBody.prefix(160))",
                isProblem: true
            )
            throw ClothingResolverError.badResponse(envelope.responseBody)
        }
        return try JSONDecoder().decode(Answer.self, from: payload)
    }

    // MARK: - Encargos

    /// El bucket donde la función deja cada resultado, legible solo por quien
    /// lo pidió.
    private static let resultsBucket = "ai-results"

    private static func newJobID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// Pide un trabajo largo **por encargo** y espera a su resultado.
    ///
    /// ## Por qué no síncrono
    ///
    /// Appwrite corta las ejecuciones síncronas a los 30 s, y de las
    /// asíncronas no guarda la respuesta. Así que la ejecución va en
    /// asíncrono con un `jobID`, la función deja la imagen —o un JSON con el
    /// error— en `ai-results/<jobID>` con permiso solo para este usuario, y
    /// aquí se espera a que aparezca.
    ///
    /// - Returns: los bytes de la imagen.
    private func runJob<Body: Encodable>(
        body: Body,
        jobID: String,
        timeout: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(
            url: endpoint.appending(path: "functions/\(functionID)/executions")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(projectID, forHTTPHeaderField: "X-Appwrite-Project")
        let encoder = JSONEncoder()
        let inner = String(decoding: try encoder.encode(body), as: UTF8.self)
        request.httpBody = try encoder.encode(
            Execution(body: inner, async: true, path: "/", method: "POST")
        )

        let (created, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClothingResolverError.transport(String(localized: "wkservices.remoteclothingresolver.noResponse", defaultValue: "no response", bundle: .module))
        }
        guard (200...202).contains(http.statusCode) else {
            if http.statusCode == 429 { throw ClothingResolverError.rateLimited }
            throw ClothingResolverError.transport("HTTP \(http.statusCode)")
        }
        let executionID = (try? JSONDecoder().decode(CreatedExecution.self, from: created))?.id

        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        var polls = 0
        // Lo que tarda como poco: no tiene sentido preguntar antes.
        try await Task.sleep(for: .seconds(3))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let data = try await download(jobID) {
                Task { await self.deleteResult(jobID) }
                return try Self.unwrap(data)
            }
            polls += 1
            // De vez en cuando, si la ejecución se ha caído: esperar el
            // tiempo entero a un fichero que ya no va a llegar sería el
            // "se queda colgado" de siempre.
            if polls.isMultiple(of: 4), let executionID, await executionFailed(executionID) {
                throw ClothingResolverError.transport(String(localized: "wkservices.remoteclothingresolver.theExecutionFailedOnThe", defaultValue: "the execution failed on the server", bundle: .module))
            }
            try await Task.sleep(for: .milliseconds(1500))
        }
        throw ClothingResolverError.transport(String(localized: "wkservices.remoteclothingresolver.itTookTooLong", defaultValue: "it took too long", bundle: .module))
    }

    /// El resultado, si ya está. `nil` mientras no exista.
    private func download(_ jobID: String) async throws -> Data? {
        var request = URLRequest(url: endpoint.appending(
            path: "storage/buckets/\(Self.resultsBucket)/files/\(jobID)/download"
        ))
        request.setValue(projectID, forHTTPHeaderField: "X-Appwrite-Project")
        request.timeoutInterval = 30
        guard
            let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse,
            http.statusCode == 200
        else { return nil }
        return data
    }

    /// Una imagen, o el error que la función dejó en su lugar.
    private static func unwrap(_ data: Data) throws -> Data {
        guard data.first == UInt8(ascii: "{") else { return data }
        let failure = try? JSONDecoder().decode(JobFailure.self, from: data)
        DiagnosticsLog.record(
            "REMOTO",
            "el encargo falló: \(failure?.status ?? 0) \(failure?.error ?? "?") \(failure?.reason ?? "")",
            isProblem: true
        )
        if failure?.status == 429 { throw ClothingResolverError.rateLimited }
        if failure?.status == 402 { throw ClothingResolverError.insufficientCredits }
        if failure?.refunded == true {
            throw ClothingResolverError.refunded(failure?.error ?? "")
        }
        throw ClothingResolverError.badResponse(
            [failure?.error, failure?.reason].compactMap { $0 }.joined(separator: ": ")
        )
    }

    private func executionFailed(_ id: String) async -> Bool {
        var request = URLRequest(url: endpoint.appending(
            path: "functions/\(functionID)/executions/\(id)"
        ))
        request.setValue(projectID, forHTTPHeaderField: "X-Appwrite-Project")
        guard
            let (data, _) = try? await session.data(for: request),
            let execution = try? JSONDecoder().decode(ExecutionStatus.self, from: data)
        else { return false }
        return execution.status == "failed"
    }

    /// Recogido, se borra: es una foto tuya y no tiene por qué quedarse en
    /// el servidor.
    private func deleteResult(_ jobID: String) async {
        var request = URLRequest(url: endpoint.appending(
            path: "storage/buckets/\(Self.resultsBucket)/files/\(jobID)"
        ))
        request.httpMethod = "DELETE"
        request.setValue(projectID, forHTTPHeaderField: "X-Appwrite-Project")
        _ = try? await session.data(for: request)
    }

    // MARK: - Turnos

    private func acquireSlot() async {
        guard inFlight >= Self.maximumConcurrent else {
            inFlight += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
        inFlight += 1
    }

    private func releaseSlot() {
        inFlight -= 1
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume()
    }

    // MARK: - Sesión

    /// Si ya se abrió en esta ejecución. La cookie sobrevive al reinicio, así
    /// que lo normal es que la comprobación no llegue ni a hacerse dos veces.
    private var hasSession = false

    /// Se asegura de que las peticiones van como usuario y no como invitado.
    ///
    /// Primero pregunta: si ya hay sesión de un arranque anterior —la cookie
    /// está en disco— no se abre otra. Abrir una por arranque dejaría una
    /// cuenta anónima nueva cada vez que se abre la app.
    private func ensureSession() async throws {
        // **El usuario de verdad**, no uno anónimo nuevo. Ver `AppwriteAccount`.
        if let account { return try await account.ensureSession() }
        if hasSession { return }

        if await isSignedIn() {
            hasSession = true
            return
        }

        var request = URLRequest(url: endpoint.appending(path: "account/sessions/anonymous"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(projectID, forHTTPHeaderField: "X-Appwrite-Project")
        request.httpBody = Data("{}".utf8)

        let (_, response) = try await session.data(for: request)
        guard
            let http = response as? HTTPURLResponse,
            http.statusCode == 200 || http.statusCode == 201
        else {
            throw ClothingResolverError.transport(String(localized: "wkservices.remoteclothingresolver.couldnTOpenAnAnonymous", defaultValue: "couldn't open an anonymous session", bundle: .module))
        }
        hasSession = true
        DiagnosticsLog.record("REMOTO", "sesión anónima abierta")
    }

    private func isSignedIn() async -> Bool {
        var request = URLRequest(url: endpoint.appending(path: "account"))
        request.setValue(projectID, forHTTPHeaderField: "X-Appwrite-Project")
        guard
            let (_, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse
        else { return false }
        return http.statusCode == 200
    }

    // MARK: - Sobres

    private struct Payload: Encodable {
        let imageBase64: String
        let kind: String?
        let subcategory: String?
        let dominantColor: String?
        let brandCandidates: [String]
    }

    private struct TryOnPayload: Encodable {
        let action: String
        let personBase64: String?
        let bodyPhotosBase64: [String]
        let personDescription: String
        let garmentsBase64: [String]
        let scene: String
        let sceneDescription: String?
        let pose: String
        let poseDescription: String?
        let jobID: String
    }

    private struct RestylePayload: Encodable {
        let action: String
        let imageBase64: String
        let jobID: String
    }

    private struct CreatedExecution: Decodable {
        let id: String
        enum CodingKeys: String, CodingKey { case id = "$id" }
    }

    private struct ExecutionStatus: Decodable {
        let status: String
    }

    private struct JobFailure: Decodable {
        let status: Int?
        let error: String?
        let reason: String?
        /// Si el servidor devolvió la moneda reservada.
        let refunded: Bool?
    }

    private struct RestyleAnswer: Decodable {
        let imageBase64: String
        let tokens: Int?
    }

    private struct Execution: Encodable {
        let body: String
        let async: Bool
        let path: String
        let method: String
    }

    private struct ExecutionResult: Decodable {
        let responseStatusCode: Int
        let responseBody: String
    }

    private struct SessionResponse: Decodable {
        let secret: String
    }
}
