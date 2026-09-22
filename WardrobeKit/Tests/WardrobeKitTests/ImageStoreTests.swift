import CoreGraphics
import Foundation
import Testing
@testable import WKPersistence

/// Crea un recorte de prueba: un cuadrado opaco en el centro, transparente
/// alrededor. Es la forma de una prenda recortada, que es lo que el store tiene
/// que saber guardar sin destruir el alfa.
private func makeCutout(size: Int = 512) -> CGImage {
    let context = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)
    let inset = size / 4
    context.fill(CGRect(x: inset, y: inset, width: size / 2, height: size / 2))
    // Un agujero transparente dentro de la prenda: es lo que permite
    // comprobar que el alfa sobrevive **después** de recortar el margen.
    context.clear(CGRect(x: size / 2 - 16, y: size / 2 - 16, width: 32, height: 32))
    return context.makeImage()!
}

/// Lee el alfa de un píxel concreto.
private func alpha(of image: CGImage, atX x: Int, y: Int) -> UInt8 {
    var pixel: [UInt8] = [0, 0, 0, 0]
    let context = CGContext(
        data: &pixel, width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
    return pixel[3]
}

private func temporaryRoot() -> URL {
    URL.temporaryDirectory.appending(path: "iWearIt-tests/\(UUID().uuidString)", directoryHint: .isDirectory)
}

@Suite("ImageStore")
struct ImageStoreTests {

    /// Las variantes **derivadas**: las que salen de reescalar el recorte.
    ///
    /// La de catálogo no está aquí porque no se deriva de nada: es una imagen
    /// distinta, generada fuera y bajo demanda. Que `store` la rellenara sería
    /// meter una copia reescalada del recorte donde debe ir la reconstrucción.
    private static let derived: [ImageStore.Variant] = [.thumb, .display]

    @Test("Guarda, lee y borra las variantes derivadas")
    func roundTrip() async throws {
        let store = try ImageStore(root: temporaryRoot())
        let key = try await store.store(makeCutout())

        #expect(key.count == 64, "la clave es un sha256 en hexadecimal")

        for variant in Self.derived {
            #expect(await store.exists(key: key, variant: variant))
            let image = try await store.image(for: key, variant: variant)
            let longest = max(image.width, image.height)
            #expect(CGFloat(longest) <= variant.maxPixelSize)
        }
        #expect(await !store.hasCatalog(for: key), "la de catálogo no se deriva")

        try await store.delete(key: key)
        for variant in ImageStore.Variant.allCases {
            #expect(await !store.exists(key: key, variant: variant))
        }
    }

    /// El punto que de verdad importa: las prendas son recortes con fondo
    /// transparente. Si el HEIC perdiera el alfa, todas aparecerían sobre un
    /// rectángulo negro en las baldas.
    @Test("El canal alfa sobrevive al round-trip HEIC")
    func preservesAlpha() async throws {
        let store = try ImageStore(root: temporaryRoot())
        let key = try await store.store(makeCutout())
        let restored = try await store.image(for: key, variant: .display)

        // Ya sin margen —ver `trimmed`—, así que lo transparente que queda es
        // el agujero del medio.
        let hole = alpha(of: restored, atX: restored.width / 2, y: restored.height / 2)
        let fabric = alpha(of: restored, atX: 4, y: restored.height / 2)

        #expect(hole < 16, "el hueco tiene que seguir siendo transparente")
        #expect(fabric > 240, "la tela tiene que seguir siendo opaca")
    }

    /// Guardadas con su margen, dos prendas del mismo tamaño real venían en
    /// ficheros de tamaños distintos, y cualquier sitio que las pinte "a lo que
    /// midan" las sacaba descuadradas.
    @Test("Al guardar se recorta el margen transparente")
    func trimsTransparentMargin() async throws {
        let store = try ImageStore(root: temporaryRoot())
        let key = try await store.store(makeCutout(size: 512))
        let restored = try await store.image(for: key, variant: .display)

        // El dibujo ocupa la mitad central: 256 de los 512.
        #expect(restored.width == 256)
        #expect(restored.height == 256)
    }

    /// Direccionado por contenido: el escaneo encuentra la misma camiseta en
    /// treinta fotos y no debe escribir treinta ficheros.
    @Test("Dos imágenes idénticas comparten clave y fichero")
    func deduplicatesByContent() async throws {
        let store = try ImageStore(root: temporaryRoot())
        let first = try await store.store(makeCutout())
        let second = try await store.store(makeCutout())

        #expect(first == second)
        let keys = try await store.allKeys()
        #expect(keys.count == 1)
    }

    @Test("garbageCollect borra solo lo que ya no se referencia")
    func garbageCollection() async throws {
        let store = try ImageStore(root: temporaryRoot())
        let kept = try await store.store(makeCutout(size: 512))
        let orphan = try await store.store(makeCutout(size: 384))

        #expect(kept != orphan)

        // `grace: 0` porque el fichero acaba de escribirse: la limpieza
        // perdona por defecto lo recién tocado, que es justo lo que evita que
        // un arranque con la base a medias borre imágenes que sí tienen dueño.
        let removed = try await store.garbageCollect(keeping: [kept], grace: 0)

        #expect(removed == 1)
        #expect(await store.exists(key: kept))
        #expect(await !store.exists(key: orphan))
        let remaining = try await store.allKeys()
        #expect(remaining == [kept])
    }
}

@Suite("Versión de catálogo")
struct CatalogVariantTests {

    /// La reconstrucción se guarda **bajo la clave del recorte**: es la misma
    /// prenda, así que borrarla se lleva las dos y no queda una huérfana.
    @Test("Se guarda aparte y se borra con la prenda")
    func catalogSharesTheKey() async throws {
        let store = try ImageStore(root: temporaryRoot())
        let key = try await store.store(makeCutout())
        #expect(await !store.hasCatalog(for: key))

        try await store.storeCatalog(makeCutout(), for: key)
        #expect(await store.hasCatalog(for: key))

        try await store.delete(key: key)
        #expect(await !store.hasCatalog(for: key))
    }

    /// PNG y no HEIC, y es una decisión de calidad y no de formato: la de
    /// catálogo es un recorte con alfa, y la compresión con pérdida trabaja
    /// justo en el borde —mezclando los píxeles medio transparentes con sus
    /// vecinos—, que es lo que devolvía el filete de fondo alrededor de la
    /// prenda por muy limpio que saliera el recorte.
    @Test("La de catálogo se guarda sin pérdida")
    func catalogIsLossless() async throws {
        let store = try ImageStore(root: temporaryRoot())
        let key = try await store.store(makeCutout())
        try await store.storeCatalog(makeCutout(), for: key)

        let url = store.url(for: key, variant: .catalog)
        #expect(url.pathExtension == "png")

        // Y las otras dos siguen siendo fotos: ahí la pérdida es justo lo que
        // se quiere, y un PNG de 1024 px por prenda multiplica el disco.
        #expect(store.url(for: key, variant: .display).pathExtension == "heic")
        #expect(store.url(for: key, variant: .thumb).pathExtension == "heic")

        // PNG de verdad: los ocho bytes de firma.
        let data = try await store.data(for: key, variant: .catalog)
        #expect(data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }
}

@Suite("Margen de la recolección")
struct GarbageCollectionGraceTests {

    /// El caso que hace peligrosa la limpieza en cuanto haya sincronización: un
    /// arranque con la base todavía a medias. Las imágenes están, las filas que
    /// las nombran no han llegado, y sin margen se borran justo en el
    /// dispositivo que sí las tenía.
    @Test("Una huérfana recién escrita se deja estar")
    func recentOrphansSurvive() async throws {
        let store = try ImageStore(root: temporaryRoot())
        let key = try await store.store(makeCutout())

        let removed = try await store.garbageCollect(keeping: [])
        #expect(removed == 0)
        #expect(await store.exists(key: key))
    }

    @Test("Lo que referencia alguien no se toca ni sin margen")
    func liveKeysAreNeverTouched() async throws {
        let store = try ImageStore(root: temporaryRoot())
        let key = try await store.store(makeCutout())

        let removed = try await store.garbageCollect(keeping: [key], grace: 0)
        #expect(removed == 0)
        #expect(await store.exists(key: key))
    }
}

@Suite("Bytes que viajan")
struct ImageBlobTests {

    /// Lo que hace que el iPad vea fotos y no cajas grises: los bytes viven
    /// también en la base, y desde ahí se materializan en disco al pedirlos.
    @Test("Una imagen guardada deja copia en la base y se recupera sin fichero")
    func blobsSurviveWithoutFiles() async throws {
        let container = try WardrobeStore.makeContainer(inMemory: true)
        let actor = WardrobeActor(modelContainer: container)

        let origin = try ImageStore(root: temporaryRoot())
        await origin.attachBlobStore(actor)
        let key = try await origin.store(makeCutout())

        // Otro dispositivo: misma base, disco vacío.
        let arriving = try ImageStore(root: temporaryRoot())
        await arriving.attachBlobStore(actor)

        let recovered = try await arriving.image(for: key, variant: .display)
        #expect(recovered.width > 0)

        // Y la miniatura, que no viaja, se deriva de la que sí.
        let thumb = try await arriving.image(for: key, variant: .thumb)
        #expect(thumb.width <= Int(ImageStore.Variant.thumb.maxPixelSize))
    }
}
