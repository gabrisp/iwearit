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

    /// Rehace la tanda entera. Lo que pide el botón de barajar.
    func shuffle() {
        refresh(replacingAll: true)
    }

    /// Fuera este, y otro en su sitio.
    func dismiss(_ look: StylistLook) {
        dismissed.insert(look.id)
        looks.removeAll { $0.id == look.id }
        materialised[look.id] = nil
        refill()
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
            recentlyWorn: container.mainContext.recentlyWornGarments(),
            seed: seed == 0 ? Self.seedForNow() : seed
        )
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
