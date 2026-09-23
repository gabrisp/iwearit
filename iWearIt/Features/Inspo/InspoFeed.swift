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
        refill()
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
