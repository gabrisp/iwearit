import Foundation
import SwiftData
import WKCore

/// Todas las escrituras de fondo pasan por aquí.
///
/// Los tipos `@Model` **no son `Sendable`**, así que no pueden cruzar actores.
/// La regla de este proyecto: entran DTOs `Sendable` (`GarmentDraft`), salen
/// `PersistentIdentifier`. Nunca un objeto de modelo.
@ModelActor
public actor WardrobeActor {

    /// Tamaño de lote del escaneo masivo.
    ///
    /// Un insert por foto convertiría 3.000 fotos en 3.000 transacciones. Con
    /// lotes de 25 son 120, que es la diferencia entre una UI fluida y una app
    /// que se atasca cada vez que encuentra una camiseta.
    public static let batchSize = 25

    // MARK: - Categorías semilla

    /// Crea las ocho baldas si no existen. Idempotente: se puede llamar en cada
    /// arranque sin duplicar nada, porque `slug` es único.
    public func seedCategoriesIfNeeded() throws {
        let existing = try modelContext.fetch(FetchDescriptor<GarmentCategory>())
        guard existing.isEmpty else { return }

        for (index, definition) in GarmentCategory.seedDefinitions().enumerated() {
            modelContext.insert(
                GarmentCategory(
                    slug: definition.slug,
                    name: definition.name,
                    isBuiltIn: true,
                    sortOrder: index,
                    symbolName: definition.symbol,
                    defaultKind: definition.kind
                )
            )
        }
        try modelContext.save()
    }

    // MARK: - Alta de prendas

    /// Inserta un lote de borradores y devuelve sus identificadores.
    ///
    /// Una sola transacción por lote. La categoría se resuelve por el `kind`
    /// mientras no haya embeddings; la clasificación contra las categorías
    /// propias del usuario llega en F7.
    @discardableResult
    /// Los embeddings de lo que ya hay, para poder detectar duplicados.
    ///
    /// Solo el id, el nombre y el vector: traerse los `Garment` enteros para
    /// comparar unos cuantos kilobytes de floats sería cargar sus imágenes, sus
    /// relaciones y sus categorías para tirarlo todo acto seguido. Y además
    /// `@Model` no es `Sendable`, así que no podrían cruzar de vuelta.
    ///
    /// Se descartan las prendas sin embedding: no son comparables, y un `nil`
    /// no se parece a nada.
    public func knownEmbeddings() throws -> [DuplicateDetector.Known] {
        var descriptor = FetchDescriptor<Garment>(
            predicate: #Predicate { $0.embedding != nil }
        )
        descriptor.propertiesToFetch = [\.name, \.embedding]
        return try modelContext.fetch(descriptor).compactMap { garment in
            guard let embedding = garment.embedding else { return nil }
            return DuplicateDetector.Known(
                id: PersistentIdentifierBox(garment.persistentModelID),
                name: garment.name,
                embedding: embedding
            )
        }
    }

    public func insert(_ drafts: [GarmentDraft]) throws -> [PersistentIdentifier] {
        guard !drafts.isEmpty else { return [] }

        let categories = try modelContext.fetch(FetchDescriptor<GarmentCategory>())
        let bySlug = Dictionary(uniqueKeysWithValues: categories.map { ($0.slug, $0) })

        var identifiers: [PersistentIdentifier] = []
        identifiers.reserveCapacity(drafts.count)

        // Las baldas propias que quieren clasificar solas, con su vector.
        let custom = categories.compactMap { category -> (GarmentCategory, [Float])? in
            guard category.autoAssignEnabled else { return nil }
            let raw = category.promptEmbedding ?? category.centroidEmbedding
            guard let raw, !raw.isEmpty else { return nil }
            // El centroide se guarda como media sin normalizar; aquí se pasa a
            // dirección, que es lo que el coseno compara.
            guard let direction = EmbeddingMath.direction(of: EmbeddingMath.decode(raw)) else {
                return nil
            }
            return (category, direction)
        }

        for draft in drafts {
            let garment = Garment(
                name: draft.proposedName ?? Self.fallbackName(for: draft),
                kind: draft.kind,
                normalizedImageKey: draft.normalizedImageKey,
                confidence: draft.confidence
            )
            garment.subcategory = draft.subcategory
            garment.material = draft.material
            garment.colors = draft.colors
            garment.seasons = draft.seasons
            garment.tags = draft.tags
            garment.rawCropImageKey = draft.rawCropImageKey
            garment.sourcePhotoLocalIdentifier = draft.sourcePhotoLocalIdentifier
            garment.embedding = draft.embedding
            garment.brand = draft.brand

            let assignment = Self.assign(draft, among: custom)
            garment.category = assignment.category ?? bySlug[draft.kind.seedCategorySlug]
            // Empate entre dos baldas propias: no se decide a ciegas, se
            // pregunta. "Gorras" y "Sombreros" se parecen lo suficiente como
            // para que acertar a medias sea peor que admitir la duda.
            if assignment.isAmbiguous {
                garment.needsReview = true
            }

            modelContext.insert(garment)
            identifiers.append(garment.persistentModelID)
        }

        try modelContext.save()
        return identifiers
    }

    /// Diferencia mínima entre las dos mejores baldas para decidir sin dudar.
    static let ambiguityMargin: Float = 0.03

    /// Elige balda propia para un borrador.
    ///
    /// Compara contra el vector de cada balda —el del prompt bank si la balda
    /// se creó eligiendo un término conocido, o el centroide aprendido de los
    /// ejemplos si el nombre era libre— y se queda con la mejor **si supera su
    /// umbral**. Preferimos no asignar a asignar mal: un error obliga al
    /// usuario a corregir a mano, y corregir cuesta más que colocar.
    private static func assign(
        _ draft: GarmentDraft,
        among custom: [(GarmentCategory, [Float])]
    ) -> (category: GarmentCategory?, isAmbiguous: Bool) {
        guard
            !custom.isEmpty,
            let raw = draft.embedding,
            !raw.isEmpty
        else { return (nil, false) }

        let vector = EmbeddingMath.decode(raw)
        var scored: [(GarmentCategory, Float)] = []
        for (category, reference) in custom where reference.count == vector.count {
            scored.append((category, EmbeddingMath.similarity(vector, reference)))
        }
        scored.sort { $0.1 > $1.1 }

        guard
            let best = scored.first,
            Double(best.1) >= best.0.minSimilarity
        else { return (nil, false) }

        let ambiguous = scored.count > 1 && (best.1 - scored[1].1) < ambiguityMargin
        return (best.0, ambiguous)
    }

    /// Nombre de respaldo cuando no hay Foundation Models (iOS 18) o el
    /// dispositivo no tiene Apple Intelligence.
    ///
    /// Decidido, no pendiente: es la ruta que corre en la mayoría de
    /// dispositivos y tiene que dar un resultado presentable, no un "Prenda 47".
    ///
    /// Se usa "{sustantivo} en {color}" y no "{sustantivo} {color}" porque en
    /// español el adjetivo concuerda en género: "Cazadora negro" está mal, y
    /// "Cazadora negra" exige saber el género del sustantivo y si el color
    /// flexiona (granate y gris no; negro y blanco sí). La preposición evita
    /// la concordancia y lee como catálogo.
    ///
    /// - TODO: en F7, cuando exista el prompt bank, la tabla de colores lleva
    ///   forma masculina + femenina y los sustantivos su género, y esto pasa a
    ///   componer con concordancia real. La misma tabla resuelve el problema
    ///   para el resto de idiomas que se añadan.
    /// El nombre automático vive en `GarmentNaming`, en `WKCore`.
    ///
    /// Hacen falta dos sitios —aquí al guardar y la pantalla de revisión para
    /// enseñarlo antes— y con la regla duplicada dejarían de coincidir el día
    /// que alguien tocara una de las dos copias.
    private static func fallbackName(for draft: GarmentDraft) -> String {
        GarmentNaming.name(for: draft)
    }

    // MARK: - Mantenimiento

    /// Claves de imagen vivas, para que `ImageStore.garbageCollect` sepa qué
    /// puede borrar.
    public func liveImageKeys() throws -> Set<String> {
        var keys = Set<String>()
        for garment in try modelContext.fetch(FetchDescriptor<Garment>()) {
            keys.insert(garment.normalizedImageKey)
            if let raw = garment.rawCropImageKey { keys.insert(raw) }
        }
        for outfit in try modelContext.fetch(FetchDescriptor<Outfit>()) {
            if let thumbnail = outfit.thumbnailKey { keys.insert(thumbnail) }
        }
        // Los stickers de foto. **Sin esto el recolector los borraba**: el
        // fichero no lo referenciaba ninguna prenda, así que al arrancar se
        // consideraba huérfano y desaparecía — el sticker seguía en el outfit
        // pero apuntando a un hueco.
        //
        // Es el riesgo de un recolector que funciona por lista blanca: cada
        // sitio nuevo que guarde una imagen tiene que acordarse de aparecer
        // aquí, y olvidarse no da ningún error, solo pierde datos más tarde.
        for item in try modelContext.fetch(FetchDescriptor<CanvasItem>()) {
            if let key = item.imageKey { keys.insert(key) }
        }
        for profile in try modelContext.fetch(FetchDescriptor<BodyProfile>()) {
            keys.insert(profile.imageKey)
        }
        keys.remove("")
        return keys
    }

    // MARK: - Converger sin destruir

    /// Junta lo que dos dispositivos crearon por separado.
    ///
    /// ## Por qué hace falta
    ///
    /// Las restricciones de unicidad se cayeron al preparar el esquema para
    /// CloudKit —no las soporta— y eran las que impedían dos baldas con el
    /// mismo `slug` o dos "hoy" en el calendario. Con dos dispositivos, eso
    /// pasa el primer día: los dos siembran sus ocho baldas semilla y los dos
    /// crean el día de hoy la primera vez que planifican.
    ///
    /// ## Cómo se junta
    ///
    /// **Moviendo, nunca borrando.** El contenido se lleva al más antiguo —que
    /// es el que más probablemente tiene historia— y el duplicado se queda
    /// vacío. Si queda vacío del todo, se marca como eliminado, que es
    /// reversible; si le quedara algo dentro por lo que sea, se deja en paz.
    ///
    /// Un duplicado de más es una molestia. Una balda fusionada a la brava con
    /// sus prendas dentro es ropa perdida.
    @discardableResult
    public func reconcileDuplicates() throws -> Int {
        var merged = 0

        // --- Baldas con el mismo slug ---
        let categories = try modelContext.fetch(
            FetchDescriptor<GarmentCategory>(sortBy: [SortDescriptor(\.slug)])
        )
        for (_, group) in Dictionary(grouping: categories, by: \.slug) where group.count > 1 {
            // La de más prendas manda; a igualdad, la de menor `sortOrder`.
            let winner = group.max { left, right in
                (left.garments.count, -left.sortOrder) < (right.garments.count, -right.sortOrder)
            }
            guard let winner else { continue }
            for duplicate in group where duplicate !== winner {
                for garment in duplicate.garments { garment.category = winner }
                if duplicate.garments.isEmpty { duplicate.markDeleted() }
                merged += 1
            }
        }

        // --- Días repetidos en el calendario ---
        let days = try modelContext.fetch(
            FetchDescriptor<PlannedDay>(sortBy: [SortDescriptor(\.dayStart)])
        )
        for (_, group) in Dictionary(grouping: days, by: \.dayStart) where group.count > 1 {
            guard let winner = group.first else { continue }
            for duplicate in group.dropFirst() {
                for outfit in duplicate.outfits { outfit.plannedDay = winner }
                merged += 1
            }
        }

        guard merged > 0 else { return 0 }
        try modelContext.save()
        DiagnosticsLog.record("SINCRONIZA", "\(merged) duplicado(s) fusionados sin borrar nada")
        return merged
    }

    // MARK: - Bytes de imagen

    /// Guarda —o sustituye— los bytes de una variante.
    ///
    /// Upsert por `(clave, variante)` y no inserción a secas: la clave es el
    /// hash del contenido, así que volver a guardar la misma imagen tiene que
    /// dejar una fila, no dos. Con CloudKit de por medio eso importa el doble:
    /// dos filas con la misma clave son dos `CKAsset` subidos por lo mismo.
    public func storeBlob(key: String, variant: String, data: Data) throws {
        guard !key.isEmpty, !data.isEmpty else { return }
        var descriptor = FetchDescriptor<GarmentImageBlob>(
            predicate: #Predicate { $0.key == key && $0.variantRaw == variant }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            guard existing.data != data else { return }
            existing.data = data
        } else {
            modelContext.insert(
                GarmentImageBlob(key: key, variantRaw: variant, data: data)
            )
        }
        try modelContext.save()
    }

    public func blobData(key: String, variant: String) throws -> Data? {
        var descriptor = FetchDescriptor<GarmentImageBlob>(
            predicate: #Predicate { $0.key == key && $0.variantRaw == variant }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.data
    }

    /// Las claves que ya tienen bytes guardados.
    ///
    /// Sirve para la puesta al día: subir solo lo que falta en vez de releer
    /// el armario entero del disco en cada arranque.
    public func storedBlobKeys() throws -> Set<String> {
        var descriptor = FetchDescriptor<GarmentImageBlob>()
        descriptor.propertiesToFetch = [\.key]
        return Set(try modelContext.fetch(descriptor).map(\.key))
    }

    public func garmentCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<Garment>())
    }

    #if DEBUG
    /// Pone color de fondo al primer outfit que encuentre, para poder ver en
    /// una captura si el cambio se pinta o no.
    public func probeSetBackdrop(_ raw: String, calendar: Calendar = .current) throws {
        // El outfit **de hoy en el planificador**, no el primero que haya:
        // con maletas sembradas, "el primero por fecha" es un outfit de viaje
        // y la sonda pintaba una pantalla que no estábamos mirando.
        let dayStart = calendar.startOfDay(for: Date())
        let days = try modelContext.fetch(
            FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.dayStart == dayStart })
        )
        guard let outfit = days.first?.outfits.first else {
            NSLog("PROBE: hoy no tiene ningún outfit al que poner color")
            return
        }
        outfit.backdropRaw = raw
        try modelContext.save()
        NSLog("PROBE: color %@ puesto en el outfit %@", raw, outfit.id.uuidString)
    }

    /// Solo para la sonda de invalidación: renombra una prenda concreta para
    /// poder observar qué vistas se reevalúan a raíz de una edición.
    public func renameFirstGarment(inCategorySlug slug: String, to name: String) throws {
        var descriptor = FetchDescriptor<Garment>(
            predicate: #Predicate { $0.category?.slug == slug }
        )
        descriptor.fetchLimit = 1
        guard let garment = try modelContext.fetch(descriptor).first else { return }
        garment.name = name
        try modelContext.save()
    }
    #endif

    #if DEBUG
    /// Solo para la sonda: crea una balda propia, le mueve prendas de un `kind`
    /// concreto y la pone la primera. Reproduce exactamente lo que hacen
    /// `NewCategorySheet` y `ShelfOrderScreen`.
    public func probeCreateCategory(named name: String, movingKind kind: GarmentKind) throws {
        let categories = try modelContext.fetch(
            FetchDescriptor<GarmentCategory>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        guard !categories.contains(where: { $0.name == name }) else { return }

        let category = GarmentCategory(
            slug: UUID().uuidString,
            name: name,
            isBuiltIn: false,
            sortOrder: (categories.map(\.sortOrder).max() ?? 0) + 1,
            symbolName: "square.grid.2x2"
        )
        modelContext.insert(category)

        let raw = kind.rawValue
        var descriptor = FetchDescriptor<Garment>(predicate: #Predicate { $0.kindRaw == raw })
        descriptor.fetchLimit = 4
        let examples = try modelContext.fetch(descriptor)
        for garment in examples {
            garment.category = category
            garment.categoryLockedByUser = true
        }
        category.memberCountAtCentroid = examples.count
        category.autoAssignEnabled = examples.count >= GarmentCategory.minimumExamplesForCentroid

        // Reordenar: la balda nueva pasa a ser la primera.
        var reordered = categories
        reordered.insert(category, at: 0)
        for (index, item) in reordered.enumerated() { item.sortOrder = index }

        try modelContext.save()
    }
    #endif

    #if DEBUG
    /// Solo para la sonda: monta un outfit de hoy con varias prendas colocadas.
    public func probeBuildTodayOutfit(calendar: Calendar = .current) throws {
        let dayStart = calendar.startOfDay(for: Date())
        let existing = try modelContext.fetch(
            FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.dayStart == dayStart })
        )
        guard existing.isEmpty else { return }

        var descriptor = FetchDescriptor<Garment>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        let all = try modelContext.fetch(descriptor)

        // Una de cada tipo, para que el outfit tenga sentido visual.
        let wanted: [GarmentKind] = [.outerLayer, .upperBody, .lowerBody, .feet]
        let chosen = wanted.compactMap { kind in all.first { $0.kind == kind } }
        guard !chosen.isEmpty else { return }

        let day = PlannedDay(dayStart: dayStart)
        let outfit = Outfit(name: "Sonda")
        // Con color: así la captura dice si el fondo se pinta y se persiste,
        // separado de si la hoja que lo elige funciona.
        outfit.backdropRaw = "blush"
        modelContext.insert(day)
        modelContext.insert(outfit)
        outfit.plannedDay = day

        // Colocadas con solape y rotaciones distintas: así la captura muestra
        // apilado, hit testing por alfa y rotación exacta a la vez.
        let layout: [(x: Double, y: Double, w: Double, h: Double, rot: Double, z: Double)] = [
            (360, 480, 420, 520, -0.14, 0),
            (560, 430, 360, 440,  0.09, 1),
            (470, 880, 400, 520,  0.03, 2),
            (620, 1200, 320, 240, -0.22, 3),
        ]

        for (index, garment) in chosen.enumerated() {
            let spec = layout[index % layout.count]
            let item = CanvasItem(
                transform: ItemTransform(
                    x: spec.x, y: spec.y,
                    baseWidth: spec.w, baseHeight: spec.h,
                    scale: 1, rotation: spec.rot, zIndex: spec.z
                ),
                garment: garment
            )
            item.outfit = outfit
            modelContext.insert(item)
        }
        try modelContext.save()
    }
    #endif

    #if DEBUG
    /// Solo para la sonda: mueve **una** prenda del canvas, igual que hace
    /// soltar tras arrastrar, para medir cuántas vistas se reevalúan.
    public func probeNudgeFirstCanvasItem() throws {
        var descriptor = FetchDescriptor<CanvasItem>(sortBy: [SortDescriptor(\.zIndex)])
        descriptor.fetchLimit = 1
        guard let item = try modelContext.fetch(descriptor).first else { return }
        var transform = item.transform
        transform.x += 40
        transform.rotation += 0.1
        item.apply(transform)
        try modelContext.save()
    }
    #endif

    #if DEBUG
    /// Solo para la sonda: una maleta con fechas y outfits por día, y otra sin
    /// fechas con outfits preparados. Cubre las dos ramas de F5.
    public func probeBuildSuitcases(calendar: Calendar = .current) throws {
        guard try modelContext.fetchCount(FetchDescriptor<Suitcase>()) == 0 else { return }

        var descriptor = FetchDescriptor<Garment>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        let all = try modelContext.fetch(descriptor)
        guard !all.isEmpty else { return }

        func pick(_ kind: GarmentKind, skip: Int = 0) -> Garment? {
            all.filter { $0.kind == kind }.dropFirst(skip).first
        }

        // Con fechas: cuatro días, outfit en los dos primeros.
        let start = calendar.date(byAdding: .day, value: 12, to: Date()) ?? Date()
        let trip = Suitcase(
            name: "Lisboa",
            startDate: start,
            endDate: calendar.date(byAdding: .day, value: 3, to: start)
        )
        // Con color e icono: es lo que distingue una maleta de otra en la
        // balda, y una sonda sin ellos no ejercita el caso real.
        trip.colorRaw = SuitcaseTint.teal.rawValue
        trip.symbolName = SuitcaseEmoji.beach.rawValue
        modelContext.insert(trip)

        for day in 0..<2 {
            let outfit = Outfit(name: "Día \(day + 1)")
            outfit.suitcaseDayIndex = day
            modelContext.insert(outfit)
            outfit.suitcase = trip

            let kinds: [GarmentKind] = [.upperBody, .lowerBody, .feet]
            for (slot, kind) in kinds.enumerated() {
                guard let garment = pick(kind, skip: day) else { continue }
                let item = CanvasItem(
                    transform: ItemTransform(
                        x: 420 + Double(slot) * 60,
                        y: 380 + Double(slot) * 320,
                        baseWidth: 340, baseHeight: 420,
                        rotation: Double(slot) * 0.06 - 0.06,
                        zIndex: Double(slot)
                    ),
                    garment: garment
                )
                item.outfit = outfit
                modelContext.insert(item)

                if !trip.packingEntries.contains(where: { $0.garment?.id == garment.id }) {
                    let entry = PackingEntry(garment: garment)
                    modelContext.insert(entry)
                    entry.suitcase = trip
                    // Una marcada, para ver el progreso funcionando.
                    entry.isPacked = day == 0 && slot == 0
                }
            }
        }

        // Sin fechas: outfits simplemente preparados.
        let gym = Suitcase(name: "Gimnasio")
        gym.colorRaw = SuitcaseTint.clay.rawValue
        gym.symbolName = SuitcaseEmoji.gym.rawValue
        modelContext.insert(gym)
        let prepared = Outfit(name: "Outfit 1")
        modelContext.insert(prepared)
        prepared.suitcase = gym
        if let top = pick(.upperBody, skip: 3) {
            let item = CanvasItem(
                transform: ItemTransform(x: 500, y: 600, baseWidth: 340, baseHeight: 420),
                garment: top
            )
            item.outfit = prepared
            modelContext.insert(item)
            let entry = PackingEntry(garment: top)
            modelContext.insert(entry)
            entry.suitcase = gym
        }

        try modelContext.save()
    }
    #endif

    public func deleteGarments(withIDs ids: [PersistentIdentifier]) throws {
        for id in ids {
            if let garment = self[id, as: Garment.self] {
                garment.markDeleted()
            }
        }
        try modelContext.save()
    }
}

/// El actor de la base **es** el almacén de bytes sincronizables.
///
/// No hace falta nada más: guardar un blob es insertar una fila, y quien sabe
/// insertar filas es este. El `ImageStore` le pide los bytes por protocolo y
/// así sigue sin saber que existe una base de datos.
extension WardrobeActor: ImageBlobStore {}
