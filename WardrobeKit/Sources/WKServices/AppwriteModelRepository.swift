import Foundation
import WKCore

/// Modelos desde Appwrite, por REST.
///
/// Sin el SDK de Appwrite a propósito: son unas pocas peticiones y añadir un
/// paquete para eso significa mantenerlo, actualizarlo y cargar con su
/// superficie entera para usar el 2%.
///
/// - Important: aquí **no hay API key**. Solo el project id, que es público, y
///   lectura anónima sobre el bucket y la colección. Una API key dentro de la
///   app se puede extraer del binario en cinco minutos y da acceso de escritura
///   a todo el proyecto.
public struct AppwriteModelRepository: ModelRepository {
    private let endpoint: URL
    private let projectID: String
    private let databaseID: String
    private let collectionID: String
    private let bucketID: String
    private let session: URLSession

    public init(
        endpoint: URL,
        projectID: String,
        databaseID: String = "wardrobe",
        collectionID: String = "model_manifest",
        bucketID: String = "ml-models",
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.projectID = projectID
        self.databaseID = databaseID
        self.collectionID = collectionID
        self.bucketID = bucketID
        self.session = session
    }

    public func manifest() async throws -> [ModelManifestEntry] {
        var components = URLComponents(
            url: endpoint.appending(path: "databases/\(databaseID)/collections/\(collectionID)/documents"),
            resolvingAgainstBaseURL: false
        )
        // Solo lo activo. Filtrar en el servidor evita traerse el histórico de
        // versiones entero cada vez que arranca la app.
        //
        // Sintaxis JSON y no la antigua `equal("isActive",[true])`: Appwrite
        // 1.8 rechaza esa con "Invalid query: Syntax error". Comprobado contra
        // el servidor, no supuesto.
        let query = #"{"method":"equal","attribute":"isActive","values":[true]}"#
        components?.queryItems = [URLQueryItem(name: "queries[]", value: query)]
        guard let url = components?.url else { throw ModelRepositoryError.notConfigured }

        let (data, response) = try await session.data(
            for: request(for: url, timeout: Self.manifestTimeout)
        )
        try check(response, data: data)

        let payload = try JSONDecoder().decode(DocumentList.self, from: data)
        return payload.documents.map(\.entry)
    }

    public func downloadPart(
        fileID: String,
        progress: @Sendable (Double) -> Void
    ) async throws -> URL {
        let url = endpoint
            .appending(path: "storage/buckets/\(bucketID)/files/\(fileID)/download")
            .appending(queryItems: [URLQueryItem(name: "project", value: projectID)])

        let (temporary, response) = try await session.download(for: request(for: url))
        try check(response, data: Data())
        progress(1)

        // `download(for:)` borra el temporal al volver del scope, así que se
        // mueve a un sitio nuestro antes de devolverlo.
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "iwearit-part-\(fileID)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    // MARK: - Utilidades

    /// - Parameter timeout: 120 para bajar 30 MB; mucho menos para preguntar
    ///   qué hay. Con el mismo tope para las dos cosas, una consulta al
    ///   manifiesto con el servidor atascado dejaba la app dos minutos en
    ///   "consultando el manifiesto" — y lo que se estaba esperando era un
    ///   JSON de tres líneas.
    private func request(for url: URL, timeout: TimeInterval = 120) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(projectID, forHTTPHeaderField: "X-Appwrite-Project")
        // Delante de Appwrite puede haber un proxy que filtre por User-Agent.
        request.setValue("iWearIt/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout
        return request
    }

    /// Lo que se espera por una consulta al manifiesto.
    ///
    /// Doce segundos. Si en doce no ha contestado, no va a contestar en dos
    /// minutos: la app se queda con lo que ya tiene en disco, que es lo que
    /// hace que un segundo arranque sea instantáneo.
    static let manifestTimeout: TimeInterval = 12

    private func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw ModelRepositoryError.network("HTTP \(http.statusCode) \(detail)")
        }
    }

    // MARK: - Decodificación

    private struct DocumentList: Decodable {
        let documents: [Document]
    }

    private struct Document: Decodable {
        let modelId: String
        let task: String
        let version: Int
        let fileId: String
        let sha256: String
        let sizeBytes: Int?
        let minIOSVersion: String?
        let inputWidth: Int?
        let inputHeight: Int?
        let labelsJSON: String?
        let partsJSON: String?

        var entry: ModelManifestEntry {
            ModelManifestEntry(
                modelID: modelId,
                task: ModelTask(rawValue: task) ?? .segmentation,
                version: version,
                fileID: fileId,
                sha256: sha256,
                sizeBytes: sizeBytes ?? 0,
                minIOSVersion: minIOSVersion ?? "18.0",
                inputWidth: inputWidth ?? 512,
                inputHeight: inputHeight ?? 512,
                labels: Self.decodeStrings(labelsJSON),
                partFileIDs: Self.decodeStrings(partsJSON)
            )
        }

        /// Listas guardadas como JSON en un campo de texto.
        ///
        /// Appwrite tiene atributos de array, pero un campo de texto sobrevive
        /// a cambios de esquema sin migrar documentos, y estas listas no se
        /// consultan nunca — solo se leen enteras.
        private static func decodeStrings(_ raw: String?) -> [String] {
            guard
                let raw, !raw.isEmpty,
                let data = raw.data(using: .utf8),
                let decoded = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return decoded
        }
    }
}
