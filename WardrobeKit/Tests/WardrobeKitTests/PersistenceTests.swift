import Foundation
import SwiftData
import Testing
import WKCore
@testable import WKPersistence

private func makeDraft(index: Int) -> GarmentDraft {
    GarmentDraft(
        kind: GarmentKind.allCases[index % GarmentKind.allCases.count],
        subcategory: "camiseta",
        colors: [NamedColor(nameKey: "granate", red: 0.5, green: 0.1, blue: 0.1, weight: 0.8)],
        normalizedImageKey: String(format: "%064x", index),
        confidence: 0.9
    )
}

@Suite("Persistencia")
struct PersistenceTests {

    @Test("Las categorías semilla se crean una sola vez")
    func seedIsIdempotent() async throws {
        let container = try WardrobeStore.makeContainer(inMemory: true)
        let actor = WardrobeActor(modelContainer: container)

        try await actor.seedCategoriesIfNeeded()
        try await actor.seedCategoriesIfNeeded()

        let context = ModelContext(container)
        let categories = try context.fetch(FetchDescriptor<GarmentCategory>())

        let expectedCount = GarmentCategory.seedDefinitions().count
        let allBuiltIn = categories.allSatisfy(\.isBuiltIn)
        let uniqueSlugs = Set(categories.map(\.slug)).count

        #expect(categories.count == expectedCount)
        #expect(allBuiltIn)
        #expect(uniqueSlugs == categories.count, "los slugs son únicos")
    }

    @Test("Una prenda nueva cae en la balda que le corresponde por su kind")
    func assignsSeedCategoryByKind() async throws {
        let container = try WardrobeStore.makeContainer(inMemory: true)
        let actor = WardrobeActor(modelContainer: container)
        try await actor.seedCategoriesIfNeeded()

        let draft = GarmentDraft(
            kind: .feet,
            normalizedImageKey: String(repeating: "a", count: 64),
            confidence: 0.9
        )
        try await actor.insert([draft])

        let context = ModelContext(container)
        let garment = try #require(try context.fetch(FetchDescriptor<Garment>()).first)

        #expect(garment.kind == .feet)
        #expect(garment.category?.slug == "shoes")
    }

    /// Criterio de F1: insertar 500 prendas por el actor **sin bloquear el hilo
    /// principal**. La prueba no mide tiempo, mide que el `MainActor` pudo
    /// seguir ejecutando trabajo mientras el actor escribía.
    @MainActor
    @Test("500 inserciones no bloquean el hilo principal")
    func bulkInsertKeepsMainActorResponsive() async throws {
        let container = try WardrobeStore.makeContainer(inMemory: true)
        let actor = WardrobeActor(modelContainer: container)
        try await actor.seedCategoriesIfNeeded()

        let counter = TickCounter()
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                counter.tick()
                await Task.yield()
            }
        }

        let drafts = (0..<500).map(makeDraft(index:))
        for batch in stride(from: 0, to: drafts.count, by: WardrobeActor.batchSize) {
            let slice = Array(drafts[batch..<min(batch + WardrobeActor.batchSize, drafts.count)])
            try await actor.insert(slice)
        }

        ticker.cancel()

        let inserted = try await actor.garmentCount()
        #expect(inserted == 500)
        #expect(counter.value > 0, "el hilo principal siguió trabajando durante la escritura")
    }

    @Test("liveImageKeys recoge las claves de todos los modelos que las usan")
    func liveKeys() async throws {
        let container = try WardrobeStore.makeContainer(inMemory: true)
        let actor = WardrobeActor(modelContainer: container)
        try await actor.seedCategoriesIfNeeded()
        try await actor.insert((0..<3).map(makeDraft(index:)))

        let keys = try await actor.liveImageKeys()

        #expect(keys.count == 3)
        #expect(!keys.contains(""), "las claves vacías no cuentan como vivas")
    }

    /// El requisito del canvas: 32,56° tienen que seguir siendo 32,56° al
    /// volver. Sin redondeos, sin snap, sin cuantización.
    @Test("La transformada del canvas sobrevive exacta al guardar y recargar")
    func canvasTransformIsExact() async throws {
        let container = try WardrobeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let rotation = 32.56 * .pi / 180
        let original = ItemTransform(
            x: 417.3891, y: 902.7734,
            baseWidth: 311.5, baseHeight: 402.25,
            scale: 1.337, rotation: rotation, zIndex: 7
        )

        let outfit = Outfit(name: "exacto")
        let item = CanvasItem(transform: original, garment: nil)
        item.outfit = outfit
        context.insert(outfit)
        context.insert(item)
        try context.save()

        // Contexto nuevo: fuerza a releer del store en vez de servir el objeto cacheado.
        let fresh = ModelContext(container)
        let reloaded = try #require(try fresh.fetch(FetchDescriptor<CanvasItem>()).first)

        #expect(reloaded.transform == original, "igualdad bit a bit de los siete campos")
        #expect(reloaded.rotation.bitPattern == rotation.bitPattern)

        // Los grados NO vuelven exactos, y no es culpa de la persistencia:
        // grados → radianes → grados pierde precisión en IEEE 754
        // (32,56 vuelve como 32,56000000000001). Por eso el valor canónico son
        // los radianes y `rotationDegrees` es solo para mostrar. Escribir de
        // vuelta un valor derivado del mostrado haría derivar la rotación un
        // poco en cada apertura del outfit.
        #expect(abs(reloaded.transform.rotationDegrees - 32.56) < 1e-9)
    }

    @Test("La imagen de un sticker de foto cuenta como viva")
    func photoStickerKeysAreLive() async throws {
        let container = try WardrobeStore.makeContainer(inMemory: true)
        let actor = WardrobeActor(modelContainer: container)
        let context = ModelContext(container)

        let outfit = Outfit(name: "con foto")
        context.insert(outfit)
        let item = CanvasItem(
            transform: ItemTransform(
                x: 0, y: 0, baseWidth: 100, baseHeight: 100,
                scale: 1, rotation: 0, zIndex: 0
            ),
            garment: nil
        )
        item.apply(.photo(key: "foto-del-sticker"))
        item.outfit = outfit
        context.insert(item)
        try context.save()

        // Sin esto el recolector de basura borraba el fichero al arrancar y el
        // sticker quedaba apuntando a un hueco.
        let live = try await actor.liveImageKeys()
        #expect(live.contains("foto-del-sticker"))
    }

    @Test("Un sticker sobrevive a guardar y recargar, y no se confunde con una prenda")
    func stickersRoundTrip() async throws {
        let container = try WardrobeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let outfit = Outfit(name: "con stickers")
        context.insert(outfit)

        let transform = ItemTransform(
            x: 500, y: 700, baseWidth: 300, baseHeight: 200,
            scale: 1, rotation: 0, zIndex: 1
        )

        let text = CanvasItem(transform: transform, garment: nil)
        text.apply(.text(TextSticker(
            string: "hola qué tal",
            colorHex: "#5AC8F5",
            backgroundHex: "#111111",
            alignment: .leading
        )))
        text.outfit = outfit
        context.insert(text)

        let day = Date(timeIntervalSince1970: 1_758_326_400)
        let dateItem = CanvasItem(transform: transform, garment: nil)
        dateItem.apply(.date(day))
        dateItem.outfit = outfit
        context.insert(dateItem)

        // Una prenda de verdad, para comprobar que NO se lee como sticker.
        let garment = Garment(name: "Camiseta", kind: .upperBody, normalizedImageKey: "abc")
        context.insert(garment)
        let wearable = CanvasItem(transform: transform, garment: garment)
        wearable.outfit = outfit
        context.insert(wearable)

        try context.save()

        let fresh = ModelContext(container)
        let items = try fresh.fetch(FetchDescriptor<CanvasItem>())
        #expect(items.count == 3)

        let reloadedText = try #require(items.first { $0.sticker?.kind == .text })
        guard case let .text(sticker) = try #require(reloadedText.sticker) else {
            Issue.record("debería ser texto")
            return
        }
        #expect(sticker.string == "hola qué tal")
        #expect(sticker.colorHex == "#5AC8F5")
        #expect(sticker.backgroundHex == "#111111")
        #expect(sticker.alignment == .leading)

        let reloadedDate = try #require(items.first { $0.sticker?.kind == .date })
        guard case let .date(value) = try #require(reloadedDate.sticker) else {
            Issue.record("debería ser fecha")
            return
        }
        #expect(value == day)

        // Lo importante del modelo: una prenda no tiene sticker, y el campo
        // nuevo no se ha colado en los items que ya existían.
        let reloadedGarment = try #require(items.first { $0.garment != nil })
        #expect(reloadedGarment.sticker == nil)
        #expect(reloadedGarment.stickerKindRaw == nil)
    }

    @Test("zIndex crece sin reindexar el array")
    func bringToFrontDoesNotReindex() async throws {
        let container = try WardrobeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let outfit = Outfit(name: "capas")
        context.insert(outfit)
        for z in 0..<3 {
            let item = CanvasItem(
                transform: ItemTransform(x: 0, y: 0, baseWidth: 1, baseHeight: 1, zIndex: Double(z)),
                garment: nil
            )
            item.outfit = outfit
            context.insert(item)
        }
        try context.save()

        #expect(outfit.nextZIndex == 3)
        #expect(outfit.lowestZIndex == -1)
    }
}

/// Contador aislado al `MainActor`, para comprobar que sigue vivo mientras el
/// actor de fondo escribe.
@MainActor
private final class TickCounter {
    private(set) var value = 0
    func tick() { value += 1 }
}

@Suite("Borrado suave")
@MainActor
struct SoftDeletionTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try WardrobeStore.makeContainer(inMemory: true))
    }

    @Test("Marcar no borra: el objeto sigue ahí")
    func markingKeepsTheObject() throws {
        let context = try makeContext()
        let garment = Garment(name: "Camiseta", kind: .upperBody, normalizedImageKey: "k")
        context.insert(garment)

        garment.markDeleted()

        #expect(garment.deletedAt != nil)
        #expect(!garment.isVisible)
        // Y sigue existiendo: es la diferencia entre esconder y perder.
        let all = try context.fetch(FetchDescriptor<Garment>())
        #expect(all.count == 1)
    }

    @Test("Las consultas de pantalla no lo traen")
    func visibleFetchHidesIt() throws {
        let context = try makeContext()
        let kept = Garment(name: "Camisa", kind: .upperBody, normalizedImageKey: "a")
        let gone = Garment(name: "Sudadera", kind: .upperBody, normalizedImageKey: "b")
        context.insert(kept)
        context.insert(gone)
        gone.markDeleted()

        let visible = try context.fetch(FetchDescriptor<Garment>.visibleGarments())
        #expect(visible.count == 1)
        #expect(visible.first?.name == "Camisa")
    }

    @Test("Se puede devolver")
    func restoreBringsItBack() throws {
        let context = try makeContext()
        let garment = Garment(name: "Vaqueros", kind: .lowerBody, normalizedImageKey: "c")
        context.insert(garment)

        garment.markDeleted()
        garment.restore()

        #expect(garment.isVisible)
        #expect(try context.fetch(FetchDescriptor<Garment>.visibleGarments()).count == 1)
    }

    /// El conflicto que decide toda la política: un dispositivo lo borró, otro
    /// lo estaba editando. Gana la edición si es posterior — y en el empate
    /// también, porque un empate es una duda y la duda se resuelve conservando.
    @Test("Una edición posterior gana al borrado")
    func editBeatsDelete() throws {
        let context = try makeContext()
        let garment = Garment(name: "Abrigo", kind: .outerLayer, normalizedImageKey: "d")
        context.insert(garment)

        let deletion = Date()
        garment.markDeleted(at: deletion)
        garment.touch(deletion.addingTimeInterval(1))
        garment.resolveDeletionAgainstEdits()

        #expect(garment.isVisible, "una edición posterior tiene que devolverlo")
    }

    @Test("Sin edición posterior, el borrado se mantiene")
    func deleteStandsWithoutEdits() throws {
        let context = try makeContext()
        let garment = Garment(name: "Gorra", kind: .head, normalizedImageKey: "e")
        context.insert(garment)

        garment.touch(Date().addingTimeInterval(-60))
        garment.markDeleted()
        garment.resolveDeletionAgainstEdits()

        #expect(!garment.isVisible)
    }

    /// Borrar una prenda la quita de los outfits **sin destruir la
    /// colocación**: si vuelve, vuelve a su sitio exacto.
    @Test("La prenda borrada desaparece del lienzo pero su sitio se guarda")
    func canvasHidesDeletedGarments() throws {
        let context = try makeContext()
        let garment = Garment(name: "Botas", kind: .feet, normalizedImageKey: "f")
        let outfit = Outfit(name: "Lunes")
        context.insert(garment)
        context.insert(outfit)
        let item = CanvasItem(
            transform: ItemTransform(x: 100, y: 100, baseWidth: 200, baseHeight: 200),
            garment: garment
        )
        item.outfit = outfit
        context.insert(item)

        #expect(outfit.visibleItems.count == 1)

        garment.markDeleted()
        #expect(outfit.visibleItems.isEmpty)
        #expect(outfit.items.count == 1, "la colocación sigue guardada")

        garment.restore()
        #expect(outfit.visibleItems.count == 1)
    }
}

@Suite("Separar el store en nube y local")
@MainActor
struct StoreSplitTests {

    /// La pregunta que decide la migración: si el fichero que ya tiene el
    /// usuario contiene entidades que la configuración nueva **no** declara,
    /// ¿se abre igual y conserva lo demás, o se queda a oscuras?
    ///
    /// De la respuesta depende poder dejar el store existente como el
    /// sincronizado y llevarse a otro fichero solo lo que es de este
    /// dispositivo. Si fallara, habría que migrar copiando filas — que es
    /// mucho más arriesgado.
    @Test("Abrir el store existente con un esquema más corto conserva los datos")
    func openingWithFewerEntitiesKeepsData() throws {
        let url = URL.temporaryDirectory.appending(path: "split-\(UUID().uuidString).store")

        // Lo que ya tiene el usuario: un store con todo dentro.
        let full = try ModelContainer(
            for: Schema(versionedSchema: WardrobeSchemaV1.self),
            configurations: ModelConfiguration(
                schema: Schema(versionedSchema: WardrobeSchemaV1.self),
                url: url
            )
        )
        let writing = ModelContext(full)
        writing.insert(Garment(name: "Camisa", kind: .upperBody, normalizedImageKey: "x"))
        writing.insert(
            DownloadedModel(
                modelID: "clothes-seg", version: 1, sha256: "abc",
                compiledPath: "models/seg.mlmodelc", sizeBytes: 1
            )
        )
        try writing.save()

        // Y ahora se abre igual pero declarando solo lo que sincroniza.
        let syncedSchema = Schema(WardrobeSchemaV1.synced)
        let partial = try ModelContainer(
            for: syncedSchema,
            configurations: ModelConfiguration(schema: syncedSchema, url: url)
        )
        let reading = ModelContext(partial)
        let garments = try reading.fetch(FetchDescriptor<Garment>())

        #expect(garments.count == 1, "la prenda del usuario tiene que seguir ahí")
        #expect(garments.first?.name == "Camisa")
    }
}

@Suite("Converger entre dispositivos")
struct ConvergenceTests {

    /// El caso del primer día con dos dispositivos: los dos sembraron sus ocho
    /// baldas y ahora hay dieciséis. Juntarlas **no puede costar ni una
    /// prenda**.
    @Test("Dos baldas con el mismo slug se juntan sin perder ropa")
    func mergesDuplicateCategories() async throws {
        let container = try WardrobeStore.makeContainer(inMemory: true)
        let actor = WardrobeActor(modelContainer: container)
        let context = ModelContext(container)

        let first = GarmentCategory(slug: "tops", name: "Tops", sortOrder: 0)
        let second = GarmentCategory(slug: "tops", name: "Tops", sortOrder: 1)
        context.insert(first)
        context.insert(second)

        let mine = Garment(name: "Camisa", kind: .upperBody, normalizedImageKey: "a")
        let theirs = Garment(name: "Jersey", kind: .upperBody, normalizedImageKey: "b")
        context.insert(mine)
        context.insert(theirs)
        mine.category = first
        theirs.category = second
        try context.save()

        _ = try await actor.reconcileDuplicates()

        let reading = ModelContext(container)
        let visible = try reading.fetch(FetchDescriptor<GarmentCategory>.visibleCategories())
        #expect(visible.count == 1, "queda una balda")
        #expect(visible.first?.garments.count == 2, "con las dos prendas dentro")

        // Y la duplicada no se ha borrado: está marcada, que es reversible.
        let all = try reading.fetch(FetchDescriptor<GarmentCategory>())
        #expect(all.count == 2)
    }

    @Test("Dos veces el mismo día se juntan sin perder outfits")
    func mergesDuplicateDays() async throws {
        let container = try WardrobeStore.makeContainer(inMemory: true)
        let actor = WardrobeActor(modelContainer: container)
        let context = ModelContext(container)

        let day = Calendar.current.startOfDay(for: Date())
        let mine = PlannedDay(dayStart: day)
        let theirs = PlannedDay(dayStart: day)
        context.insert(mine)
        context.insert(theirs)

        let a = Outfit(name: "El mío")
        let b = Outfit(name: "El suyo")
        context.insert(a)
        context.insert(b)
        a.plannedDay = mine
        b.plannedDay = theirs
        try context.save()

        _ = try await actor.reconcileDuplicates()

        let reading = ModelContext(container)
        let outfits = try reading.fetch(FetchDescriptor<Outfit>())
        #expect(outfits.count == 2, "ningún outfit se pierde al juntar los días")
        let days = try reading.fetch(FetchDescriptor<PlannedDay>(
            predicate: #Predicate { $0.dayStart == day }
        ))
        let withContent = days.filter { !$0.orderedOutfits.isEmpty }
        #expect(withContent.count == 1, "los dos outfits acaban en el mismo día")
        #expect(withContent.first?.orderedOutfits.count == 2)
    }
}

