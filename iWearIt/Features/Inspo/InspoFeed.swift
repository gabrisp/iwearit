import Foundation
import Observation
import SwiftData
import WKCore
import WKPersistence

/// La inspiración **ya está hecha cuando entras**.
///
/// ## Por qué no se genera al abrir
///
/// Porque entonces abrir la pantalla sería esperar, y porque siempre
/// enseñaría lo mismo hasta que cambiaras de ropa. Esto va por su cuenta: monta
/// conjuntos cada cierto tiempo y los deja puestos, así que cuando entras ya
/// hay algo y **es distinto de la última vez** sin que hayas tenido que pedir
/// nada.
///
/// ## Lo que cuesta
///
/// Nada que se note: montar ocho conjuntos son unos cientos de combinaciones
/// puntuadas con aritmética sobre números que ya están en memoria. No hay red,
/// no hay modelo que cargar y no hay nada que escribir en la base — los
/// conjuntos propuestos **no se guardan**: solo existen los que tú guardas.
@MainActor
@Observable
final class InspoFeed {

    /// Cuántos conjuntos hay puestos.
    static let capacity = 8
    /// Cada cuánto cambian. Veinte minutos: lo bastante para que al volver por
    /// la tarde no sea lo mismo de la mañana, y lo bastante poco para no estar
    /// rehaciendo nada mientras miras.
    static let rotation: TimeInterval = 20 * 60
    /// Cuántos se renuevan en cada vuelta.
    ///
    /// Tres de ocho y no los ocho: si cambiara todo, el que ibas a guardar
    /// desaparecería mientras lo mirabas.
    static let churn = 3

    private(set) var looks: [StylistLook] = []
    private(set) var updatedAt: Date?

    /// Lo que has descartado en esta sesión, para no volver a proponerlo.
    private var dismissed: Set<UUID> = []

    private let container: ModelContainer
    private let weather: WeatherProvider
    private var ticker: Task<Void, Never>?
    private var forecast: WeatherSnapshot?
    /// Para no pedir más conjuntos dos veces a la vez al llegar al final.
    private var isExtending = false
    private let stylist = Stylist()

    init(container: ModelContainer, weather: WeatherProvider) {
        self.container = container
        self.weather = weather
    }

    deinit {
        // El bucle muere con el objeto, que vive lo que vive la app.
    }

    /// Arranca el goteo. Llamarlo dos veces no arranca dos bucles.
    func start() {
        guard ticker == nil else { return }
        loadDislikes()
        refresh(replacingAll: true)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.rotation))
                guard let self, !Task.isCancelled else { return }
                self.refresh(replacingAll: false)
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    /// Rehace la tanda entera **sin cambiar las tarjetas**.
    ///
    /// Los conjuntos nuevos se quedan con los identificadores de los que
    /// había, así que para la lista son las mismas tarjetas con otra ropa
    /// dentro: se cambia lo que hay puesto, no se vacía la pantalla y se
    /// vuelve a llenar. Es la diferencia entre barajar una baraja y tirarla
    /// para sacar otra.
    func shuffle() {
        let fresh = stylist.looks(from: wardrobe(), brief: baseBrief(seed: UInt64(Date().timeIntervalSince1970)), count: max(Self.capacity, looks.count))
        guard !fresh.isEmpty else { return }

        var rebuilt: [StylistLook] = []
        for (index, look) in fresh.enumerated() {
            guard index < looks.count else {
                rebuilt.append(look)
                continue
            }
            let existing = looks[index]
            materialised[existing.id] = nil
            rebuilt.append(
                StylistLook(
                    id: existing.id,
                    garmentIDs: look.garmentIDs,
                    headline: look.headline,
                    reason: look.reason,
                    score: look.score
                )
            )
        }
        looks = rebuilt
        updatedAt = Date()
    }

    /// Fuera este **y anotado**: sus prendas pesan menos a partir de ahora.
    ///
    /// Tirar un conjunto a la izquierda no es solo quitarlo de en medio: es lo
    /// más parecido a enseñarle algo al estilista que hay en esta pantalla, y
    /// si no se guarda en ningún sitio, al rato vuelve lo mismo.
    func dislike(_ look: StylistLook) {
        for id in look.garmentIDs {
            dislikes[id, default: 0] += 0.5
        }
        saveDislikes()
        dismiss(look)
    }

    /// Fuera este, y otro en su sitio.
    func dismiss(_ look: StylistLook) {
        dismissed.insert(look.id)
        looks.removeAll { $0.id == look.id }
        materialised[look.id] = nil
        refill()
    }

    /// Cuántos conjuntos puede llegar a haber en memoria.
    ///
    /// El feed no se acaba mientras queden combinaciones, pero tampoco crece
    /// sin freno: sesenta son muchos más de los que nadie pasa de una sentada,
    /// y a partir de ahí lo que salga va a ser variaciones de lo mismo.
    static let maximum = 60

    /// Más conjuntos al llegar al final.
    ///
    /// ## Por qué se generan al llegar y no de golpe
    ///
    /// Porque montar ocho es instantáneo y montar sesenta no lo es tanto, y
    /// sobre todo porque casi nadie llega al octavo: preparar cincuenta que
    /// nadie va a ver es trabajo tirado en la pantalla que tiene que abrirse
    /// al instante.
    ///
    /// Se piden con una semilla nueva y **sin repetir conjuntos** que ya estén
    /// en la lista. Si el armario ya no da para más combinaciones distintas,
    /// no se añade nada: el feed se acaba, que es lo honesto — inventar
    /// repetidos para que parezca infinito es peor que quedarse corto.
    func extend() {
        guard !isExtending, looks.count < Self.maximum else { return }
        isExtending = true
        defer { isExtending = false }

        var brief = baseBrief(
            seed: UInt64(Date().timeIntervalSince1970) &+ UInt64(looks.count) &* 31
        )
        // Lo de las últimas tarjetas, fuera: así lo que aparece al seguir
        // bajando se nota distinto y no es el mismo pantalón una vez más.
        brief.banned.formUnion(looks.suffix(3).flatMap(\.garmentIDs))

        let existing = Set(looks.map(Self.signature))
        let fresh = stylist.looks(from: wardrobe(), brief: brief, count: Self.capacity)
        let additions = fresh.filter {
            !dismissed.contains($0.id) && !existing.contains(Self.signature($0))
        }
        guard !additions.isEmpty else { return }
        looks.append(contentsOf: additions.prefix(Self.maximum - looks.count))
    }

    /// Qué prendas lleva, sin importar el orden: dos conjuntos con las mismas
    /// prendas son el mismo conjunto aunque se llamen distinto.
    private static func signature(_ look: StylistLook) -> String {
        look.garmentIDs.map(\.uuidString).sorted().joined(separator: "·")
    }

    /// Otro conjunto para ese hueco, sin tocar los demás.
    ///
    /// - Parameter excluding: lo que ya se está viendo, para que el nuevo no
    ///   sea el de al lado con otro nombre.
    func replacement(for look: StylistLook, excluding used: Set<UUID>) -> StylistLook? {
        var brief = baseBrief(seed: UInt64(Date().timeIntervalSince1970) &+ 7)
        brief.banned.formUnion(look.garmentIDs)
        let fresh = stylist.looks(from: wardrobe(), brief: brief, count: Self.capacity)
        return fresh.first { Set($0.garmentIDs).isDisjoint(with: used) } ?? fresh.first
    }

    func replace(_ look: StylistLook, with other: StylistLook) {
        guard let index = looks.firstIndex(where: { $0.id == look.id }) else { return }
        looks[index] = other
        materialised[look.id] = nil
    }

    // MARK: Los que ya son outfits

    /// Los conjuntos que se han convertido en outfit de verdad —al guardarlos,
    /// al ponerles fecha o al abrirlos en el editor—.
    ///
    /// ## Por qué hace falta acordarse
    ///
    /// Porque al editar uno **lo editado tiene que volver a su sitio**: si
    /// mueves la chaqueta y cambias los zapatos, la tarjeta de inspiración de
    /// la que saliste tiene que enseñar eso, no la propuesta de antes. Para
    /// eso la tarjeta deja de pintarse por huecos y se pinta con el outfit,
    /// que ya guarda dónde está cada prenda.
    ///
    /// En memoria y no en la base: la propuesta sigue sin guardarse; lo que se
    /// guarda es el outfit, y esto solo dice cuál es el suyo mientras la
    /// pantalla viva.
    private(set) var materialised: [UUID: PersistentIdentifier] = [:]

    func remember(_ outfit: Outfit, for look: StylistLook) {
        materialised[look.id] = outfit.persistentModelID
    }

    func forget(_ look: StylistLook) {
        materialised[look.id] = nil
    }

    func outfitID(for look: StylistLook) -> PersistentIdentifier? {
        materialised[look.id]
    }

    /// El tiempo de hoy, para que las propuestas sepan si hace frío.
    ///
    /// Se pide una vez y se guarda: el proveedor ya cachea por día, y aquí lo
    /// que importa es no pedirlo dentro del bucle de montar conjuntos.
    func loadWeather() async {
        forecast = await weather.snapshot(for: Date())
    }

    /// El encargo de base: hoy, con el tiempo de hoy y sin lo de estos días.
    ///
    /// Público porque el chat parte de aquí: una pregunta escrita no empieza
    /// de cero, empieza de lo que ya se sabe del día.
    func baseBrief(seed: UInt64 = 0) -> StylistBrief {
        StylistBrief(
            date: Date(),
            weather: forecast,
            discouraged: dislikes,
            recentlyWorn: container.mainContext.recentlyWornGarments(),
            seed: seed == 0 ? Self.seedForNow() : seed
        )
    }

    // MARK: Lo que no te gusta

    /// Cuánto pesa en contra cada prenda, por los conjuntos que has tirado.
    ///
    /// ## Dónde se guarda
    ///
    /// En `UserDefaults`, no en la base. No es parte de tu armario —no es un
    /// dato de la prenda, es una opinión sobre lo que te propuso este
    /// teléfono—, y meterlo en el modelo obligaría a migrar el esquema y a
    /// sincronizar un número que solo sirve para ordenar sugerencias.
    private(set) var dislikes: [UUID: Double] = [:]

    private static let dislikesKey = "inspo.dislikes"

    private func loadDislikes() {
        guard
            let raw = UserDefaults.standard.dictionary(forKey: Self.dislikesKey) as? [String: Double]
        else { return }
        dislikes = raw.reduce(into: [:]) { result, entry in
            guard let id = UUID(uuidString: entry.key) else { return }
            result[id] = entry.value
        }
    }

    private func saveDislikes() {
        let raw = dislikes.reduce(into: [String: Double]()) { result, entry in
            result[entry.key.uuidString] = entry.value
        }
        UserDefaults.standard.set(raw, forKey: Self.dislikesKey)
    }

    func wardrobe() -> [StylistGarment] {
        container.mainContext.stylistWardrobe()
    }

    /// Conjuntos para una petición concreta del chat.
    func looks(for brief: StylistBrief, count: Int) -> [StylistLook] {
        stylist.looks(from: wardrobe(), brief: brief, count: count)
    }

    // MARK: Por dentro

    private func refresh(replacingAll: Bool) {
        let fresh = stylist.looks(
            from: wardrobe(),
            brief: baseBrief(),
            count: Self.capacity
        )
        guard !fresh.isEmpty else { return }

        if replacingAll || looks.isEmpty {
            looks = fresh
        } else {
            // Los que se quedan van delante y los nuevos detrás: así lo que
            // estabas mirando no se mueve de sitio.
            let kept = looks.dropLast(min(Self.churn, looks.count))
            let keptGarments = Set(kept.flatMap(\.garmentIDs))
            let additions = fresh
                .filter { Set($0.garmentIDs).isDisjoint(with: keptGarments) }
                .prefix(Self.churn)
            looks = Array(kept) + additions
        }
        updatedAt = Date()
    }

    private func refill() {
        guard looks.count < Self.capacity else { return }
        let existing = Set(looks.flatMap(\.garmentIDs))
        let fresh = stylist.looks(
            from: wardrobe(),
            brief: baseBrief(seed: UInt64(Date().timeIntervalSince1970)),
            count: Self.capacity
        )
        for look in fresh where looks.count < Self.capacity {
            guard !dismissed.contains(look.id) else { continue }
            guard Set(look.garmentIDs).isDisjoint(with: existing) else { continue }
            looks.append(look)
        }
    }

    /// La semilla del tramo de tiempo en el que estamos.
    ///
    /// Depende de la hora y no del azar para que dos vueltas dentro del mismo
    /// rato den lo mismo: si cambiara en cada llamada, bastaría con que la
    /// vista se reevaluara para que la inspiración se rehiciera debajo del
    /// dedo.
    private static func seedForNow() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 / rotation)
    }
}
