import AppleArchive
import CoreML
import CryptoKit
import Foundation
import System
import WKCore

/// Trae los modelos al dispositivo, los verifica y los deja compilados.
///
/// El flujo completo:
///
///     manifiesto → ¿ya está esta versión? → sí: usar
///                                         → no: descargar trozos
///                                              → reensamblar
///                                              → verificar sha256
///                                              → descomprimir
///                                              → MLModel.compileModel
///                                              → guardar y borrar lo viejo
///
/// El sha256 se comprueba sobre el paquete **reensamblado**, no sobre cada
/// trozo: lo que importa es que el modelo entero sea el que se subió, y una
/// concatenación en mal orden daría trozos válidos y un modelo roto.
public actor ModelStore {

    public struct InstalledModel: Sendable {
        public let modelID: String
        public let version: Int
        public let compiledURL: URL
        public let labels: [String]
        public let inputWidth: Int
        public let inputHeight: Int
    }

    public enum Progress: Sendable {
        case downloading(fraction: Double)
        case verifying
        case compiling
        case ready
    }

    private let repository: ModelRepository
    private let root: URL
    private let fileManager = FileManager.default

    public init(repository: ModelRepository, root: URL? = nil) throws {
        self.repository = repository
        if let root {
            self.root = root
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            self.root = support.appending(path: "iWearIt/models", directoryHint: .isDirectory)
        }
        try fileManager.createDirectory(at: self.root, withIntermediateDirectories: true)
        try Self.excludeFromBackup(self.root)
    }

    /// Los modelos ya compilados en este dispositivo.
    public func installed() -> [String: InstalledModel] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ) else { return [:] }

        var result: [String: InstalledModel] = [:]
        for directory in contents where directory.hasDirectoryPath {
            guard
                let data = try? Data(contentsOf: directory.appending(path: "meta.json")),
                let meta = try? JSONDecoder().decode(StoredMeta.self, from: data)
            else { continue }
            let compiled = directory.appending(path: meta.compiledName)
            guard fileManager.fileExists(atPath: compiled.path(percentEncoded: false)) else { continue }
            result[meta.modelID] = InstalledModel(
                modelID: meta.modelID,
                version: meta.version,
                compiledURL: compiled,
                labels: meta.labels,
                inputWidth: meta.inputWidth,
                inputHeight: meta.inputHeight
            )
        }
        return result
    }

    /// El manifiesto del servidor.
    public func installedOrFetch() async throws -> [ModelManifestEntry] {
        try await repository.manifest()
    }

    /// Asegura que un modelo del manifiesto está instalado y actualizado.
    @discardableResult
    public func install(
        _ entry: ModelManifestEntry,
        onProgress: @Sendable (Progress) -> Void = { _ in }
    ) async throws -> InstalledModel {
        if let current = installed()[entry.modelID], current.version >= entry.version {
            DiagnosticsLog.record(
                "MODELO",
                "\(entry.modelID) v\(current.version) ya está en disco (\(byteCount(sizeOnDisk(of: entry.modelID))))"
            )
            onProgress(.ready)
            return current
        }

        DiagnosticsLog.record(
            "MODELO",
            "\(entry.modelID): hay que traer la v\(entry.version) — \(byteCount(entry.sizeBytes))"
                + " en \(entry.orderedFileIDs.count) trozo(s)"
        )
        let clock = ContinuousClock.now

        let staging = root.appending(path: "staging-\(entry.modelID)", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        // 1. Trozos, en orden.
        let archive = staging.appending(path: "package.aar")
        fileManager.createFile(atPath: archive.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: archive)

        let fileIDs = entry.orderedFileIDs
        for (index, fileID) in fileIDs.enumerated() {
            let part = try await repository.downloadPart(fileID: fileID) { _ in }
            try handle.write(contentsOf: try Data(contentsOf: part, options: .mappedIfSafe))
            try? fileManager.removeItem(at: part)
            DiagnosticsLog.record(
                "MODELO", "\(entry.modelID): trozo \(index + 1)/\(fileIDs.count) descargado"
            )
            onProgress(.downloading(fraction: Double(index + 1) / Double(fileIDs.count)))
        }
        try handle.close()

        // 2. Verificar antes de tocar nada más. Un modelo corrupto que llegue a
        //    compilarse da errores incomprensibles mucho más adelante.
        onProgress(.verifying)
        let digest = try sha256(of: archive)
        guard digest == entry.sha256 else {
            DiagnosticsLog.record(
                "MODELO",
                "\(entry.modelID): el sha256 no cuadra — descarga corrupta",
                isProblem: true
            )
            throw ModelRepositoryError.checksumMismatch(expected: entry.sha256, actual: digest)
        }
        DiagnosticsLog.record("MODELO", "\(entry.modelID): sha256 correcto, compilando")

        // 3. Descomprimir y compilar.
        onProgress(.compiling)
        let unpacked = try unpackIfNeeded(archive, into: staging, task: entry.task)
        let compiled: URL
        if entry.task == .promptBank {
            // No hay nada que compilar: es una tabla de vectores.
            compiled = unpacked
        } else {
            do {
                compiled = try await MLModel.compileModel(at: unpacked)
            } catch {
                throw ModelRepositoryError.compilationFailed(error.localizedDescription)
            }
        }

        // 4. Instalar, y solo entonces retirar la versión anterior.
        let destination = root.appending(path: entry.modelID, directoryHint: .isDirectory)
        try? fileManager.removeItem(at: destination)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let compiledName = compiled.lastPathComponent
        let finalCompiled = destination.appending(path: compiledName)
        try fileManager.moveItem(at: compiled, to: finalCompiled)

        let meta = StoredMeta(
            modelID: entry.modelID,
            version: entry.version,
            compiledName: compiledName,
            labels: entry.labels,
            inputWidth: entry.inputWidth,
            inputHeight: entry.inputHeight
        )
        try JSONEncoder().encode(meta).write(to: destination.appending(path: "meta.json"))

        DiagnosticsLog.record(
            "MODELO",
            "\(entry.modelID) v\(entry.version) instalado en \(clock.duration(to: .now))"
        )
        onProgress(.ready)
        return InstalledModel(
            modelID: entry.modelID,
            version: entry.version,
            compiledURL: finalCompiled,
            labels: entry.labels,
            inputWidth: entry.inputWidth,
            inputHeight: entry.inputHeight
        )
    }

    /// Cuánto ocupa en disco lo instalado de un modelo.
    ///
    /// Se suma recorriendo: un `.mlmodelc` es un directorio con pesos,
    /// metadatos y el plan compilado, y su "tamaño" no es el de ningún fichero
    /// suelto.
    public func sizeOnDisk(of modelID: String) -> Int {
        let directory = root.appending(path: modelID, directoryHint: .isDirectory)
        guard let enumerator = fileManager.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total = 0
        for case let url as URL in enumerator {
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            total += size ?? 0
        }
        return total
    }

    /// Borra un modelo para que la próxima comprobación lo vuelva a traer.
    ///
    /// Lo que hace que funcione es que `install` compara versiones contra lo
    /// que hay en disco: sin nada en disco, cualquier versión del manifiesto
    /// es más nueva.
    public func remove(_ modelID: String) throws {
        let directory = root.appending(path: modelID, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: directory)
    }

    public func removeAll() throws {
        try fileManager.removeItem(at: root)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.excludeFromBackup(root)
    }

    // MARK: - Utilidades

    /// "34,1 MB". Para el registro, no para la UI.
    private nonisolated func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Los modelos no van a iCloud Backup: son re-descargables, y meter decenas
    /// de megas en la copia de seguridad del usuario a cambio de nada es de
    /// mala educación.
    private nonisolated static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Hash por bloques: un modelo entero en memoria solo para hashearlo sería
    /// un pico de 30 MB evitable.
    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let block = try handle.read(upToCount: 1 << 20), !block.isEmpty {
            hasher.update(data: block)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Extrae el paquete con **Apple Archive**.
    ///
    /// Ni ZIPFoundation ni ninguna otra dependencia: Foundation no sabe
    /// descomprimir zip en iOS —`unzipItem` es de ZIPFoundation, no del
    /// sistema— y añadir un paquete SPM solo para esto no compensa. Apple
    /// Archive es nativo en las dos puntas: `aa` lo crea en el Mac y este
    /// framework lo extrae en el dispositivo.
    /// Descomprime solo si hace falta.
    ///
    /// El banco de prompts es **un JSON de 108 KB**, y meterlo en un Apple
    /// Archive para sacarlo acto seguido solo añadía un paso que podía fallar
    /// —y fallaba: "el paquete no contiene ningún .json"—. Si los bytes ya son
    /// JSON, se usan tal cual.
    ///
    /// Se mira el contenido y no la extensión ni el manifiesto: así funciona
    /// con lo que ya está publicado **y** con lo que se publique en crudo a
    /// partir de ahora, sin coordinar los dos lados.
    private func unpackIfNeeded(_ archive: URL, into directory: URL, task: ModelTask) throws -> URL {
        if task == .promptBank, isJSON(archive) {
            let destination = directory.appending(path: "PromptBank.json")
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: archive, to: destination)
            return destination
        }
        return try unpack(archive, into: directory, task: task)
    }

    /// Los primeros bytes útiles dicen si es JSON.
    ///
    /// Un Apple Archive empieza por `pbze`; un JSON por `{` o `[`, quizá tras
    /// espacios. No hace falta leer el fichero entero para distinguirlos.
    private func isJSON(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 16) else { return false }
        for byte in head {
            if byte == 0x7B || byte == 0x5B { return true }     // { o [
            if byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 { continue }
            return false
        }
        return false
    }

    private func unpack(_ archive: URL, into directory: URL, task: ModelTask) throws -> URL {
        let destination = directory.appending(path: "unpacked", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        guard
            let readStream = ArchiveByteStream.fileStream(
                path: FilePath(archive.path(percentEncoded: false)),
                mode: .readOnly,
                options: [],
                permissions: FilePermissions(rawValue: 0o644)
            )
        else {
            throw ModelRepositoryError.compilationFailed("No se pudo abrir el paquete descargado")
        }
        defer { try? readStream.close() }

        guard let decompressStream = ArchiveByteStream.decompressionStream(readingFrom: readStream) else {
            throw ModelRepositoryError.compilationFailed("El paquete no se pudo descomprimir")
        }
        defer { try? decompressStream.close() }

        guard let decodeStream = ArchiveStream.decodeStream(readingFrom: decompressStream) else {
            throw ModelRepositoryError.compilationFailed("El paquete está dañado")
        }
        defer { try? decodeStream.close() }

        guard
            let extractStream = ArchiveStream.extractStream(
                extractingTo: FilePath(destination.path(percentEncoded: false)),
                flags: [.ignoreOperationNotPermitted]
            )
        else {
            throw ModelRepositoryError.compilationFailed("No se pudo escribir el modelo en disco")
        }
        defer { try? extractStream.close() }

        _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream)

        // El prompt bank es un JSON, no un modelo. Todo lo demás viaja como
        // `.mlpackage` y hay que compilarlo.
        let expected = task == .promptBank ? "json" : "mlpackage"
        let contents = try fileManager.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
        guard let package = contents.first(where: { $0.pathExtension == expected }) else {
            throw ModelRepositoryError.compilationFailed("El paquete no contiene ningún .\(expected)")
        }
        return package
    }

    private struct StoredMeta: Codable {
        let modelID: String
        let version: Int
        let compiledName: String
        let labels: [String]
        let inputWidth: Int
        let inputHeight: Int
    }
}
