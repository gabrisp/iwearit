import CryptoKit
import Foundation
import WKCore

/// Lo que ya se preguntó, para no volver a preguntarlo.
///
/// La clave es el **sha256 del recorte normalizado**, no el id de la prenda:
/// dos fotos distintas de la misma camiseta producen el mismo recorte, y la
/// misma foto importada dos veces produce exactamente los mismos bytes. Con el
/// contenido como clave, las dos cosas se resuelven solas.
///
/// Importa porque cada consulta cuesta dinero y un segundo y medio. Reintentar
/// una importación que falló al guardar no debería volver a pagarlo.
public actor ResolutionCache {

    private let directory: URL
    private let fileManager = FileManager.default
    /// Las últimas, también en memoria: durante un escaneo la misma prenda
    /// puede consultarse dos veces seguidas y leer el disco para eso es tocar
    /// el sistema de ficheros por nada.
    private var recent: [String: RemoteGarmentAnswer] = [:]
    private static let recentLimit = 64

    public init(directory: URL? = nil) throws {
        if let directory {
            self.directory = directory
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            self.directory = support.appending(path: "iWearIt/resolutions", directoryHint: .isDirectory)
        }
        try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// La clave de un recorte.
    public nonisolated static func key(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public func answer(for key: String) -> RemoteGarmentAnswer? {
        if let cached = recent[key] { return cached }
        guard
            let data = try? Data(contentsOf: url(for: key)),
            let answer = try? JSONDecoder().decode(RemoteGarmentAnswer.self, from: data)
        else { return nil }
        remember(key, answer)
        return answer
    }

    public func store(_ answer: RemoteGarmentAnswer, for key: String) {
        remember(key, answer)
        guard let data = try? JSONEncoder().encode(answer) else { return }
        try? data.write(to: url(for: key), options: .atomic)
    }

    public func removeAll() throws {
        recent.removeAll()
        try fileManager.removeItem(at: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func remember(_ key: String, _ answer: RemoteGarmentAnswer) {
        if recent.count >= Self.recentLimit { recent.removeAll() }
        recent[key] = answer
    }

    /// Repartido por los dos primeros caracteres del sha: un directorio con
    /// miles de entradas hace lento el listado en APFS.
    private func url(for key: String) -> URL {
        let shard = directory.appending(path: String(key.prefix(2)), directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: shard, withIntermediateDirectories: true)
        return shard.appending(path: "\(key).json")
    }
}
