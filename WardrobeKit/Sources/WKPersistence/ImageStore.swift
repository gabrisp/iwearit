import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WKCore

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
/// Quién guarda los bytes para que viajen a los demás dispositivos.
///
/// Un protocolo y no una dependencia directa a la base: el `ImageStore` sabe de
/// ficheros y de nada más, y meterle un `ModelContext` dentro lo convertiría en
/// otra cosa. Lo implementa `WardrobeActor`, que es quien tiene el contexto.
public protocol ImageBlobStore: Sendable {
    func storeBlob(key: String, variant: String, data: Data) async throws
    func blobData(key: String, variant: String) async throws -> Data?
}

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
            // 512 y no 256: en la balda una prenda mide unos 100 pt, que en un
            // iPhone son 300 px. Con 256 la miniatura se **ampliaba**, y el
            // borde transparente salía en escalera.
            case .thumb: 512
            case .display, .catalog: 1024
            }
        }

        var compressionQuality: CGFloat {
            switch self {
            // Más altas que antes (0,7 y 0,85): el recorte lleva canal alfa y la
            // compresión con pérdida trabaja justo en el borde. Ver
            // `isLossless`. Pesa algo más y el contorno se ve limpio.
            case .thumb: 0.9
            case .display, .catalog: 0.95
            }
        }

        /// En qué formato se guarda: **PNG, las tres**.
        ///
        /// Antes solo la de catálogo. Las otras dos se guardaban en HEIC con
        /// pérdida porque "son fotos" — y no lo son: son recortes con canal
        /// alfa, y la compresión con pérdida trabaja justo donde más duele, el
        /// borde. Los píxeles medio transparentes del contorno llevan el color
        /// premultiplicado y el compresor los mezcla con los vecinos, así que
        /// el filete de fondo alrededor de la prenda volvía por mucho que el
        /// recorte saliera limpio.
        ///
        /// Pesa más —un recorte de 1024 con alfa son unos cientos de kB en vez
        /// de ochenta— y da igual: un armario son cientos de prendas, no
        /// cientos de miles, y lo que se ve en pantalla es el borde.
        var isLossless: Bool { true }

        var fileExtension: String { isLossless ? "png" : "heic" }

        /// Cómo se llama en disco. La miniatura cambió de nombre al pasar a
        /// 512: así las de 256 que ya había no se reutilizan y se rehacen
        /// desde `display` la primera vez que se piden.
        var fileName: String { self == .thumb ? "thumb512" : rawValue }
    }

    public enum StoreError: Error, Sendable {
        case renderFailed
        case encodeFailed
        case notFound(key: String, variant: Variant)
        case decodeFailed(key: String, variant: Variant)
    }

    private let root: URL
    private let fileManager = FileManager.default

    /// Dónde dejar copia de los bytes para que se sincronicen, si alguien la
    /// quiere. `nil` = solo ficheros, que es el comportamiento de siempre y el
    /// de los tests.
    private var blobs: (any ImageBlobStore)?

    /// Se conecta al arrancar, no en el `init`: el `ImageStore` se construye
    /// antes que la base de datos.
    public func attachBlobStore(_ store: any ImageBlobStore) {
        blobs = store
    }

    /// Las variantes que viajan.
    ///
    /// La miniatura no: se saca de `display` en milisegundos y subir una
    /// tercera copia de cada prenda gasta cuota de iCloud del usuario para no
    /// ahorrar nada.
    static let syncedVariants: [Variant] = [.display, .catalog]

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
    public func store(_ image: CGImage) async throws -> String {
        // **Sin margen transparente.** Ver `trimmed`.
        let tight = Self.trimmed(image) ?? image
        guard let canonical = Self.resize(tight, maxPixelSize: Variant.display.maxPixelSize) else {
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
            let data = try Self.encodePNG(source)
            try writeAtomically(data, to: url)
            // Y copia a la base si hay sincronización: el fichero es la caché
            // rápida de este dispositivo, la fila es lo que llega al otro.
            if Self.syncedVariants.contains(variant) {
                try? await blobs?.storeBlob(key: key, variant: variant.rawValue, data: data)
            }
        }
        return key
    }

    /// Guarda la versión de catálogo **bajo la clave de la prenda**.
    ///
    /// Comparte clave con el recorte a propósito: es la misma prenda vista de
    /// otra manera, así que borrar la prenda se lleva las dos, y no hay una
    /// segunda clave que pueda quedarse huérfana.
    public func storeCatalog(_ image: CGImage, for key: String) async throws {
        let tight = Self.trimmed(image) ?? image
        guard let resized = Self.resize(tight, maxPixelSize: Variant.catalog.maxPixelSize) else {
            throw StoreError.renderFailed
        }
        let data = try Self.encodePNG(resized)
        try writeAtomically(data, to: url(for: key, variant: .catalog))
        try? await blobs?.storeBlob(key: key, variant: Variant.catalog.rawValue, data: data)
    }

    /// Lleva la versión de catálogo de una clave a otra.
    ///
    /// Hace falta cuando el recorte se rehace —"mejorar" vuelve a pasar la
    /// foto por el detector— y la prenda cambia de clave: la reconstrucción
    /// sigue siendo de **esta** prenda, pero vivía colgada de la clave vieja y
    /// se quedaba huérfana. El usuario había pagado por ella y desaparecía sin
    /// decir nada.
    /// - Returns: `true` si había algo que llevar y se llevó.
    @discardableResult
    public func moveCatalog(from key: String, to newKey: String) async -> Bool {
        guard key != newKey else { return true }
        guard let data = try? await data(for: key, variant: .catalog) else { return false }
        do {
            try writeAtomically(data, to: url(for: newKey, variant: .catalog))
            try? await blobs?.storeBlob(key: newKey, variant: Variant.catalog.rawValue, data: data)
            try? deleteCatalog(for: key)
            return true
        } catch {
            return false
        }
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
    public func hasCatalog(for key: String) async -> Bool {
        if fileManager.fileExists(atPath: url(for: key, variant: .catalog).path(percentEncoded: false)) {
            return true
        }
        // En un dispositivo recién sincronizado el fichero todavía no existe,
        // pero los bytes sí: decir que no hay catálogo aquí haría que la balda
        // enseñara el recorte feo y que la ficha ofreciera generar —y pagar—
        // una imagen que ya está.
        guard let blobs else { return false }
        return (try? await blobs.blobData(key: key, variant: Variant.catalog.rawValue)) != nil
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
            .appending(path: "\(key).\(variant.fileName).\(variant.fileExtension)")
    }

    public func exists(key: String, variant: Variant = .thumb) -> Bool {
        fileManager.fileExists(atPath: url(for: key, variant: variant).path(percentEncoded: false))
            || fileManager.fileExists(atPath: legacyURL(for: key, variant: variant).path(percentEncoded: false))
    }

    public func data(for key: String, variant: Variant) async throws -> Data {
        let url = url(for: key, variant: variant)
        if let data = fileManager.contents(atPath: url.path(percentEncoded: false)) {
            return data
        }
        // **Lo que se guardó antes en HEIC sigue valiendo.** Cambiar de
        // formato no puede dejar sin foto a las prendas que ya estaban: si el
        // PNG no está, se lee el HEIC de siempre y se sigue como si nada. Se
        // reescribirá en PNG cuando toque rehacerla.
        if let legacy = fileManager.contents(atPath: legacyURL(for: key, variant: variant).path(percentEncoded: false)) {
            return legacy
        }
        // **No está en disco: puede que haya llegado del otro dispositivo.**
        //
        // Es el caso normal en un iPad recién sincronizado: las prendas están
        // en la base y los bytes también, pero ningún fichero se ha escrito
        // todavía porque aquí nadie ha recortado nada. Se materializa al
        // pedirla —una vez— y a partir de ahí es un fichero local como los
        // demás.
        // La miniatura se saca de la grande que ya está en este iPhone. Es lo
        // que rehace las de 256 de antes. Ver `Variant.fileName`.
        if variant == .thumb, let derived = try? deriveThumb(for: key) {
            return derived
        }
        if let recovered = try? await materialise(key: key, variant: variant) {
            return recovered
        }
        throw StoreError.notFound(key: key, variant: variant)
    }

    private func deriveThumb(for key: String) throws -> Data? {
        let displayURL = url(for: key, variant: .display)
        guard
            // La grande, en PNG o en el HEIC de antes: las dos sirven de
            // origen para la miniatura. Ver `legacyURL`.
            let display = fileManager.contents(atPath: displayURL.path(percentEncoded: false))
                ?? fileManager.contents(
                    atPath: legacyURL(for: key, variant: .display).path(percentEncoded: false)
                ),
            let source = CGImageSourceCreateWithData(display as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let resized = Self.resize(image, maxPixelSize: Variant.thumb.maxPixelSize)
        else { return nil }
        let data = try Self.encodePNG(resized)
        try writeAtomically(data, to: url(for: key, variant: .thumb))
        // La de 256 ya no se usa.
        try? fileManager.removeItem(at: legacyThumbURL(for: key))
        return data
    }

    /// Donde vive la versión en HEIC, la de antes de guardar todo en PNG.
    private nonisolated func legacyURL(for key: String, variant: Variant) -> URL {
        root
            .appending(path: String(key.prefix(2)), directoryHint: .isDirectory)
            .appending(path: "\(key).\(variant.fileName).heic")
    }

    /// Donde estaba la miniatura de 256.
    private nonisolated func legacyThumbURL(for key: String) -> URL {
        root
            .appending(path: String(key.prefix(2)), directoryHint: .isDirectory)
            .appending(path: "\(key).thumb.heic")
    }

    /// Escribe en disco lo que venga de la base, si viene algo.
    ///
    /// La miniatura no viaja, así que se deriva de `display`: es lo que evita
    /// subir una tercera copia de cada prenda a iCloud.
    private func materialise(key: String, variant: Variant) async throws -> Data? {
        guard let blobs else { return nil }

        if let data = try await blobs.blobData(key: key, variant: variant.rawValue) {
            try writeAtomically(data, to: url(for: key, variant: variant))
            DiagnosticsLog.record("IMÁGENES", "recuperada de la nube · \(key.prefix(8)) \(variant.rawValue)")
            return data
        }

        guard
            variant == .thumb,
            let display = try await blobs.blobData(key: key, variant: Variant.display.rawValue),
            let source = CGImageSourceCreateWithData(display as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let resized = Self.resize(image, maxPixelSize: Variant.thumb.maxPixelSize)
        else { return nil }

        let data = try Self.encodePNG(resized)
        try writeAtomically(data, to: url(for: key, variant: .thumb))
        return data
    }

    /// - Parameter cappedAt: lado máximo en píxeles. Con él, la imagen se
    ///   decodifica **ya reducida** en vez de decodificar entera y encoger
    ///   después: la de catálogo es un PNG de 1024 con alfa, y una balda llena
    ///   de esas son decenas de megas de mapa de bits para pintar prendas de
    ///   cien puntos.
    public func image(
        for key: String,
        variant: Variant,
        cappedAt: CGFloat? = nil
    ) async throws -> CGImage {
        let data = try await data(for: key, variant: variant)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw StoreError.decodeFailed(key: key, variant: variant)
        }
        if let cappedAt {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: cappedAt,
            ]
            if let reduced = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return reduced
            }
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
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
        // Y la miniatura de 256, si aún quedaba.
        try? fileManager.removeItem(at: legacyThumbURL(for: key))
    }

    /// Cuánto tiene que llevar un fichero sin dueño antes de poder borrarlo.
    ///
    /// Una semana. Es el margen que convierte "no lo referencia nadie" en "no
    /// lo referencia nadie **y lleva días así**", que son dos afirmaciones muy
    /// distintas en cuanto hay sincronización: un dispositivo que acaba de
    /// arrancar tiene menos filas de las que va a tener dentro de un minuto.
    public static let orphanGracePeriod: TimeInterval = 7 * 24 * 60 * 60

    /// Borra los ficheros que ya no referencia ningún modelo **y llevan tiempo
    /// así**.
    ///
    /// ## Por qué el margen de tiempo
    ///
    /// Esto se ejecuta al arrancar, y sin margen es la operación más peligrosa
    /// de la app. El razonamiento "si ninguna fila lo referencia, sobra" solo
    /// vale si las filas están **todas**. Deja de valer en dos casos reales:
    ///
    /// 1. **Una importación a medias.** Los bytes se escriben antes que la
    ///    fila; si la app muere en medio, el siguiente arranque los borra.
    /// 2. **La sincronización entre dispositivos.** Un iPad que acaba de
    ///    instalar la app tiene la base vacía mientras CloudKit importa. Sin
    ///    margen, ese arranque borra las imágenes de todas las prendas que
    ///    todavía no han llegado — y las borra en el dispositivo que sí las
    ///    tenía.
    ///
    /// El coste de esperar una semana son unos megas de más. El coste de no
    /// esperar es perder fotos que el usuario no puede recuperar.
    ///
    /// - Parameter grace: margen mínimo desde la última modificación del
    ///   fichero. Cero solo en tests.
    @discardableResult
    public func garbageCollect(
        keeping liveKeys: Set<String>,
        grace: TimeInterval = ImageStore.orphanGracePeriod
    ) throws -> Int {
        var removed = 0
        var spared = 0
        let now = Date()
        for key in try allKeys() where !liveKeys.contains(key) {
            if grace > 0, let touched = lastModified(forKey: key), now.timeIntervalSince(touched) < grace {
                spared += 1
                continue
            }
            try delete(key: key)
            removed += 1
        }
        if spared > 0 {
            DiagnosticsLog.record("IMÁGENES", "\(spared) huérfanas recientes, se dejan estar")
        }
        return removed
    }

    /// Cuándo se tocó por última vez cualquiera de las variantes de esa clave.
    ///
    /// La más reciente de las tres: la de catálogo puede haberse generado hoy
    /// sobre un recorte de hace meses.
    private func lastModified(forKey key: String) -> Date? {
        Variant.allCases.compactMap { variant in
            try? fileManager.attributesOfItem(
                atPath: url(for: key, variant: variant).path(percentEncoded: false)
            )[.modificationDate] as? Date
        }
        .max()
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

    /// La imagen **recortada a la prenda**: se quita todo el borde
    /// transparente.
    ///
    /// ## Por qué
    ///
    /// El recorte se normaliza en un lienzo fijo —1024 cuadrado, o 4:5 para lo
    /// que va abajo— con su margen, así que dos prendas del mismo tamaño en
    /// pantalla pueden traer dentro cantidades muy distintas de nada. Guardado
    /// así, el alto y el ancho del fichero no son los de la prenda, y cualquier
    /// sitio que la pinte "a lo que mida" la saca más grande o más pequeña de
    /// lo que es.
    ///
    /// Aquí se busca, por cada lado, el primer píxel que no sea transparente
    /// —la columna más a la izquierda, la más a la derecha, la fila de arriba y
    /// la de abajo— y se corta por ahí. Lo que queda es la prenda y nada más.
    static func trimmed(_ image: CGImage, alphaThreshold: UInt8 = 8) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        guard
            let buffer = PixelBuffer(width: width, height: height),
            let context = buffer.makeContext()
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where buffer[x, y, buffer.alphaThresholdComponent] > alphaThreshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        // Sin un solo píxel opaco no hay nada que recortar; y si ya está
        // ajustada, se devuelve la misma imagen y no se copia por nada.
        guard maxX >= minX, maxY >= minY else { return nil }
        guard minX > 0 || minY > 0 || maxX < width - 1 || maxY < height - 1 else { return image }

        return image.cropping(
            to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        )
    }

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

    /// **Ya no lo usa nadie**: todo se guarda en PNG, que es lo único que
    /// conserva el borde con alfa intacto. Se queda por si alguna vez hay que
    /// guardar una foto de verdad —una foto original, no un recorte—, que es
    /// donde HEIC sí es lo correcto.
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
