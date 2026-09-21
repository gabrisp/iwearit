import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Guarda las imágenes de las prendas en el **sistema de ficheros**, no en la
/// base de datos.
///
/// Meter `Data` de imágenes en SwiftData infla el store, hace lentísimo
/// cualquier fetch y revienta el escaneo masivo. En SwiftData solo viaja la
/// clave; los bytes viven aquí.
///
/// Direccionado por contenido (sha256 de los píxeles normalizados): dos
/// recortes idénticos comparten fichero automáticamente, lo que importa cuando
/// el escaneo encuentra la misma camiseta en treinta fotos.
///
///     Library/Application Support/iWearIt/img/<sha[0..2]>/<sha>.<variante>.heic
///
/// El sharding por los dos primeros caracteres evita un directorio con 5.000
/// entradas, que en APFS penaliza el listado.
public actor ImageStore {

    public enum Variant: String, CaseIterable, Sendable {
        /// Baldas del armario y celdas de revisión.
        case thumb
        /// Detalle, canvas y maleta.
        case display
        /// La versión de catálogo: la prenda reconstruida plana, como en una
        /// tienda.
        ///
        /// **Variante y no un campo nuevo en `Garment`.** Es otra imagen de la
        /// misma prenda, exactamente igual que la miniatura, así que comparte
        /// su clave y vive junto a las demás. Guardarla como propiedad del
        /// modelo obligaría a migrar el esquema para almacenar algo que el
        /// `ImageStore` ya sabe direccionar — y una migración por una imagen
        /// derivada es un riesgo a cambio de nada.
        ///
        /// Su ausencia es un estado normal: la mayoría de las prendas no la
        /// tienen, porque cuesta dinero generarla.
        case catalog

        var maxPixelSize: CGFloat {
            switch self {
            case .thumb: 256
            case .display, .catalog: 1024
            }
        }

        var compressionQuality: CGFloat {
            switch self {
            case .thumb: 0.7
            case .display, .catalog: 0.85
            }
        }

        /// En qué formato se guarda.
        ///
        /// La de catálogo, **PNG sin pérdida**. Las otras dos son fotos y HEIC
        /// con pérdida es exactamente lo que se quiere para una foto; la de
        /// catálogo no es una foto, es un recorte con canal alfa, y ahí la
        /// compresión con pérdida trabaja justo donde más duele: el borde. Los
        /// píxeles medio transparentes del contorno llevan color premultiplicado
        /// y el compresor los mezcla con los vecinos, que es lo que devolvía el
        /// filete de fondo alrededor de la prenda por mucho que el recorte
        /// saliera limpio.
        var isLossless: Bool { self == .catalog }

        var fileExtension: String { isLossless ? "png" : "heic" }
    }

    public enum StoreError: Error, Sendable {
        case renderFailed
        case encodeFailed
        case notFound(key: String, variant: Variant)
        case decodeFailed(key: String, variant: Variant)
    }

    private let root: URL
    private let fileManager = FileManager.default

    /// - Parameter root: se inyecta en los tests para aislar cada uno en su
    ///   propio directorio temporal.
    public init(root: URL? = nil) throws {
        if let root {
            self.root = root
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.root = appSupport.appending(path: "iWearIt/img", directoryHint: .isDirectory)
        }
        try fileManager.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    // MARK: - Escritura

    /// Escribe todas las variantes y devuelve la clave de contenido.
    ///
    /// La clave sale del hash de los píxeles ya normalizados a tamaño
    /// `display`, no de la imagen original: así dos recortes que produzcan el
    /// mismo resultado visual comparten fichero aunque vinieran de fotos
    /// distintas.
    @discardableResult
    public func store(_ image: CGImage) throws -> String {
        guard let canonical = Self.resize(image, maxPixelSize: Variant.display.maxPixelSize) else {
            throw StoreError.renderFailed
        }
        let key = Self.contentHash(of: canonical)

        // **Sin la de catálogo.** Las demás variantes son la misma imagen a
        // otro tamaño y se derivan aquí; la de catálogo es una imagen
        // *distinta* que hay que generar fuera y cuesta dinero. Meterla en
        // este bucle la habría rellenado con una copia reescalada del recorte,
        // que es exactamente lo que no es.
        for variant in Variant.allCases where variant != .catalog {
            let url = url(for: key, variant: variant)
            // Ya existe con el mismo contenido: por definición es idéntico.
            guard !fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { continue }

            let source = variant == .display
                ? canonical
                : (Self.resize(canonical, maxPixelSize: variant.maxPixelSize) ?? canonical)
            let data = try Self.encodeHEIC(source, quality: variant.compressionQuality)
            try writeAtomically(data, to: url)
        }
        return key
    }

    /// Guarda la versión de catálogo **bajo la clave de la prenda**.
    ///
    /// Comparte clave con el recorte a propósito: es la misma prenda vista de
    /// otra manera, así que borrar la prenda se lleva las dos, y no hay una
    /// segunda clave que pueda quedarse huérfana.
    public func storeCatalog(_ image: CGImage, for key: String) throws {
        guard let resized = Self.resize(image, maxPixelSize: Variant.catalog.maxPixelSize) else {
            throw StoreError.renderFailed
        }
        let data = try Self.encodePNG(resized)
        try writeAtomically(data, to: url(for: key, variant: .catalog))
    }

    /// Tira la versión de catálogo y se queda con el recorte de verdad.
    ///
    /// Hace falta porque la reconstrucción **puede salir mal**: el modelo se
    /// inventa un detalle, cambia un color o devuelve la prenda de otro lado.
    /// Sin poder tirarla, esa prenda se queda enseñando una versión equivocada
    /// para siempre, porque el catálogo es lo que se enseña por defecto.
    public func deleteCatalog(for key: String) throws {
        let url = url(for: key, variant: .catalog)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Si esa prenda ya tiene versión de catálogo.
    ///
    /// Se pregunta antes de generar: volver a pedirla costaría otra vez lo
    /// mismo para obtener algo que ya está en disco.
    public func hasCatalog(for key: String) -> Bool {
        fileManager.fileExists(
            atPath: url(for: key, variant: .catalog).path(percentEncoded: false)
        )
    }

    /// Escritura atómica: a un temporal y luego intercambio.
    ///
    /// Sin esto, morir a mitad del escaneo deja un HEIC truncado que luego
    /// falla al decodificar y es dificilísimo de diagnosticar.
    private func writeAtomically(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporary = url.deletingLastPathComponent()
            .appending(path: ".tmp-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: url)
        }
    }

    // MARK: - Lectura

    public nonisolated func url(for key: String, variant: Variant) -> URL {
        let shard = String(key.prefix(2))
        return root
            .appending(path: shard, directoryHint: .isDirectory)
            .appending(path: "\(key).\(variant.rawValue).\(variant.fileExtension)")
    }

    public func exists(key: String, variant: Variant = .thumb) -> Bool {
        fileManager.fileExists(atPath: url(for: key, variant: variant).path(percentEncoded: false))
    }

    public func data(for key: String, variant: Variant) throws -> Data {
        let url = url(for: key, variant: variant)
        guard let data = fileManager.contents(atPath: url.path(percentEncoded: false)) else {
            throw StoreError.notFound(key: key, variant: variant)
        }
        return data
    }

    public func image(for key: String, variant: Variant) throws -> CGImage {
        let data = try data(for: key, variant: variant)
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw StoreError.decodeFailed(key: key, variant: variant)
        }
        return image
    }

    // MARK: - Borrado

    public func delete(key: String) throws {
        for variant in Variant.allCases {
            let url = url(for: key, variant: variant)
            if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    /// Borra todo fichero cuya clave ya no referencie ningún modelo.
    ///
    /// Se ejecuta en segundo plano al arrancar. Sin esto, descartar prendas en
    /// la revisión de stacks deja basura en disco para siempre — y tras escanear
    /// 4.000 fotos esa basura son cientos de megas.
    @discardableResult
    public func garbageCollect(keeping liveKeys: Set<String>) throws -> Int {
        var removed = 0
        for key in try allKeys() where !liveKeys.contains(key) {
            try delete(key: key)
            removed += 1
        }
        return removed
    }

    public func allKeys() throws -> Set<String> {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var keys = Set<String>()
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            // "<sha>.<variante>.heic"
            guard let key = name.split(separator: ".").first, key.count == 64 else { continue }
            keys.insert(String(key))
        }
        return keys
    }

    // MARK: - Utilidades

    /// Hash de los píxeles en crudo, no del fichero codificado: el HEIC con
    /// pérdida no es determinista entre versiones del SDK, así que hashear el
    /// resultado comprimido daría claves distintas para la misma imagen.
    private static func contentHash(of image: CGImage) -> String {
        guard let data = image.dataProvider?.data as Data? else {
            return SHA256.hash(data: Data("\(image.width)x\(image.height)".utf8))
                .map { String(format: "%02x", $0) }.joined()
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Redibuja preservando el canal alfa.
    ///
    /// `premultipliedLast` es obligatorio: las prendas son recortes con fondo
    /// transparente, y un contexto sin alfa los dejaría sobre negro.
    private static func resize(_ image: CGImage, maxPixelSize: CGFloat) -> CGImage? {
        let longest = CGFloat(max(image.width, image.height))
        let scale = min(1, maxPixelSize / longest)
        let width = Int((CGFloat(image.width) * scale).rounded())
        let height = Int((CGFloat(image.height) * scale).rounded())
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// PNG, para lo que no puede perder el borde. Ver `Variant.isLossless`.
    private static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw StoreError.encodeFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw StoreError.encodeFailed }
        return data as Data
    }

    private static func encodeHEIC(_ image: CGImage, quality: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.heic.identifier as CFString, 1, nil
        ) else {
            throw StoreError.encodeFailed
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality,
            // HEIF sí soporta alfa, y las prendas lo necesitan.
            kCGImagePropertyHasAlpha: true,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw StoreError.encodeFailed }
        return data as Data
    }
}
