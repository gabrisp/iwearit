import Foundation

/// Lo que se le pide al estilista.
///
/// Todo opcional: sin nada puesto, propone conjuntos para hoy con lo que
/// tienes. Cada campo es una restricción que el usuario ha dicho en voz alta
/// —"con estas zapatillas", "sin negro", "no el vaquero de ayer"— y por eso
/// viajan juntas en un valor en vez de repartidas por parámetros: la frase del
/// chat se traduce a esto (ver `StylistPhrase`) y el motor solo mira esto.
public struct StylistBrief: Sendable, Equatable {
    /// Para qué día. Decide la estación cuando no hay parte meteorológico.
    public var date: Date
    /// El tiempo de ese día, si se sabe. Manda sobre la estación del calendario.
    public var weather: WeatherSnapshot?
    /// **Lo que sí o sí va puesto.** Lo que ya está en el lienzo: el conjunto
    /// se construye alrededor, no se descarta.
    public var pinned: Set<UUID>
    /// Lo que no quieres ver: el vaquero de ayer, lo que acabas de descartar.
    public var banned: Set<UUID>
    /// Cuándo se llevó cada prenda. Lo de esta semana pesa menos.
    public var recentlyWorn: [UUID: Date]
    /// Etiquetas de uso pedidas: "Deporte", "Formal"…
    public var requiredTags: [String]
    /// Familias de color pedidas y prohibidas ("azul", "negro"…).
    public var preferredColors: [String]
    public var avoidedColors: [String]
    /// Calidez pedida a mano. `nil` = la decide el tiempo.
    public var warmth: GarmentVocabulary.Warmth?
    /// La semilla: es lo que hace que la sección de inspiración **vaya
    /// cambiando** sin que el armario cambie. Misma semilla, mismos conjuntos.
    public var seed: UInt64
    /// Lo que se escribió, tal cual. Solo para responder en el chat.
    public var note: String?

    public init(
        date: Date = Date(),
        weather: WeatherSnapshot? = nil,
        pinned: Set<UUID> = [],
        banned: Set<UUID> = [],
        recentlyWorn: [UUID: Date] = [:],
        requiredTags: [String] = [],
        preferredColors: [String] = [],
        avoidedColors: [String] = [],
        warmth: GarmentVocabulary.Warmth? = nil,
        seed: UInt64 = 0,
        note: String? = nil
    ) {
        self.date = date
        self.weather = weather
        self.pinned = pinned
        self.banned = banned
        self.recentlyWorn = recentlyWorn
        self.requiredTags = requiredTags
        self.preferredColors = preferredColors
        self.avoidedColors = avoidedColors
        self.warmth = warmth
        self.seed = seed
        self.note = note
    }
}

/// Un conjunto propuesto.
public struct StylistLook: Sendable, Identifiable, Hashable {
    public let id: UUID
    /// Las prendas, de arriba abajo. Sin transformadas: dónde se coloca cada
    /// una lo decide el lienzo por su tipo, igual que al montarlo a mano.
    public let garmentIDs: [UUID]
    /// Dos palabras: "Azul y arena".
    public let headline: String
    /// **Por qué este conjunto.** El motor es local y sabe explicarse: si no
    /// dice el motivo, una propuesta es indistinguible de sacar tres prendas
    /// al azar.
    public let reason: String
    public let score: Double

    public init(id: UUID = UUID(), garmentIDs: [UUID], headline: String, reason: String, score: Double) {
        self.id = id
        self.garmentIDs = garmentIDs
        self.headline = headline
        self.reason = reason
        self.score = score
    }
}

/// El estilista: monta conjuntos **en el dispositivo**, con reglas que se
/// pueden leer.
///
/// ## Por qué no hay modelo ni servidor
///
/// Porque lo que decide si un conjunto funciona son cuatro cosas medibles: que
/// abrigue lo que toca, que los colores no peleen, que haya contraste entre
/// arriba y abajo, y que no sea lo mismo que llevaste ayer. Todo eso está en
/// los datos que la app ya tiene de cada prenda. Un modelo en un servidor
/// daría la misma respuesta, más tarde, pagando, y mandando tu armario fuera.
///
/// Y además **se explica**: cada propuesta viene con su motivo, que es lo que
/// permite discutirla ("no, sin negro") en vez de aceptarla a ciegas.
public struct Stylist: Sendable {

    public init() {}

    /// Varios conjuntos distintos entre sí.
    /// - Parameter count: cuántos como mucho. Pueden salir menos si el armario
    ///   no da para más sin repetirse.
    public func looks(from wardrobe: [StylistGarment], brief: StylistBrief, count: Int = 6) -> [StylistLook] {
        var random = SeededGenerator(seed: brief.seed &+ 0x9E37_79B9)
        let pool = candidates(from: wardrobe, brief: brief, random: &random)

        guard !pool[.top, default: []].isEmpty else { return [] }

        var scored: [(look: StylistLook, ids: Set<UUID>)] = []
        // Solo los mejores de cada hueco: con seis por hueco salen unas
        // doscientas combinaciones, que se puntúan en un parpadeo. Con el
        // armario entero serían decenas de miles y ninguna mejor.
        let tops = Array(pool[.top, default: []].prefix(Self.branching))
        let bottoms = Array(pool[.bottom, default: []].prefix(Self.branching))
        let shoes = Array(pool[.shoes, default: []].prefix(Self.branching))

        for top in tops {
            // Un vestido o un mono **es** arriba y abajo: buscarle pantalón
            // sería vestir dos veces las piernas.
            let bottomOptions: [StylistGarment] =
                top.kind == .wholeBody ? [] : (bottoms.isEmpty ? [] : bottoms)
            let bottomChoices: [StylistGarment?] =
                bottomOptions.isEmpty ? [nil] : bottomOptions.map { $0 }
            for bottom in bottomChoices {
                if top.kind != .wholeBody, bottom == nil { continue }
                let shoeChoices: [StylistGarment?] = shoes.isEmpty ? [nil] : shoes.map { $0 }
                for shoe in shoeChoices {
                    var pieces = [top]
                    if let bottom { pieces.append(bottom) }
                    if let shoe { pieces.append(shoe) }

                    // Chaqueta y complemento se añaden **después**: son
                    // opcionales, así que entran solo si mejoran el conjunto.
                    if let outer = bestAddition(
                        from: pool[.outer, default: []], to: pieces, brief: brief
                    ) {
                        pieces.append(outer)
                    }
                    if let accessory = bestAddition(
                        from: pool[.accessory, default: []], to: pieces, brief: brief
                    ) {
                        pieces.append(accessory)
                    }

                    guard brief.pinned.isSubset(of: Set(pieces.map(\.id))) else { continue }
                    let look = evaluate(pieces, brief: brief, random: &random)
                    scored.append((look, Set(pieces.map(\.id))))
                }
            }
        }

        // Los mejores primero, pero **sin gemelos**: dos conjuntos que solo se
        // diferencian en los zapatos son un conjunto enseñado dos veces.
        scored.sort { $0.look.score > $1.look.score }
        var chosen: [StylistLook] = []
        var used: [Set<UUID>] = []
        for entry in scored {
            guard chosen.count < count else { break }
            let tooSimilar = used.contains { existing in
                let shared = existing.intersection(entry.ids).subtracting(brief.pinned)
                return shared.count >= max(1, entry.ids.subtracting(brief.pinned).count - 1)
            }
            guard !tooSimilar else { continue }
            chosen.append(entry.look)
            used.append(entry.ids)
        }
        return chosen
    }

    /// Un solo conjunto, para cuando se pide un cambio sobre lo que hay.
    public func look(from wardrobe: [StylistGarment], brief: StylistBrief) -> StylistLook? {
        looks(from: wardrobe, brief: brief, count: 1).first
    }

    // MARK: Candidatos

    /// Cuántas opciones por hueco entran en la combinatoria.
    private static let branching = 6

    private func candidates(
        from wardrobe: [StylistGarment],
        brief: StylistBrief,
        random: inout SeededGenerator
    ) -> [StylistRole: [StylistGarment]] {
        let target = targetSeasons(brief)
        let avoided = Set(brief.avoidedColors.map(Self.fold))
        let preferred = Set(brief.preferredColors.map(Self.fold))
        let required = Set(brief.requiredTags.map(Self.fold))

        var byRole: [StylistRole: [(StylistGarment, Double)]] = [:]
        for garment in wardrobe {
            let isPinned = brief.pinned.contains(garment.id)
            if !isPinned {
                guard !brief.banned.contains(garment.id) else { continue }
                guard !avoided.contains(Self.fold(garment.tone.familyName)) else { continue }
            }

            var score = 0.0

            // Abrigo. Una prenda de todo el año —sin calidez marcada— vale
            // siempre, y por eso no se la penaliza por no coincidir.
            let isAllYear = garment.seasons == .all || garment.seasons.isEmpty
            if isAllYear {
                score += 0.35
            } else if !garment.seasons.intersection(target).isEmpty {
                score += 0.9
            } else {
                score -= 1.4
            }

            // Uso: si has pedido deporte, lo que no es de deporte estorba.
            if !required.isEmpty {
                let tags = Set(garment.tags.map(Self.fold))
                score += tags.isDisjoint(with: required) ? -0.9 : 1.1
            }

            if preferred.contains(Self.fold(garment.tone.familyName)) { score += 1.0 }

            // Lo de estos días, menos. Lo de ayer, mucho menos: es justo lo
            // que se pide al decir "no quiero repetir".
            if let worn = brief.recentlyWorn[garment.id] ?? garment.lastWornAt {
                let days = brief.date.timeIntervalSince(worn) / 86_400
                switch days {
                case ..<1.5: score -= 1.6
                case ..<4: score -= 0.7
                case ..<8: score -= 0.25
                default: break
                }
            }

            if garment.isFavorite { score += 0.25 }
            // Lo que nunca te pones sube un poco: un armario que solo propone
            // lo de siempre no sirve para nada.
            if garment.wearCount == 0 { score += 0.2 }

            // El zarandeo: lo que hace que mañana no salga exactamente lo
            // mismo. Pequeño, para que no mande sobre las reglas.
            score += Double.random(in: -0.3...0.3, using: &random)

            if isPinned { score += 100 }
            byRole[garment.role, default: []].append((garment, score))
        }

        return byRole.mapValues { entries in
            entries.sorted { $0.1 > $1.1 }.map(\.0)
        }
    }

    /// La estación que toca: la que dice el tiempo, o la del calendario.
    private func targetSeasons(_ brief: StylistBrief) -> SeasonSet {
        if let warmth = brief.warmth { return warmth.seasons }
        if let weather = brief.weather {
            let average = (weather.highCelsius + weather.lowCelsius) / 2
            switch average {
            case ..<10: return [.autumn, .winter]
            case ..<19: return [.spring, .autumn]
            default: return [.spring, .summer]
            }
        }
        let month = Calendar.current.component(.month, from: brief.date)
        switch month {
        case 12, 1, 2: return [.autumn, .winter]
        case 3, 4, 5: return [.spring]
        case 6, 7, 8: return [.spring, .summer]
        default: return [.autumn]
        }
    }

    /// Si una chaqueta o un complemento **mejoran** el conjunto, el mejor.
    ///
    /// Se mide de verdad: se puntúa el conjunto con y sin, y solo entra si
    /// sube. Añadir siempre una chaqueta en julio es lo que hace que estas
    /// propuestas dejen de tomarse en serio.
    private func bestAddition(
        from options: [StylistGarment],
        to pieces: [StylistGarment],
        brief: StylistBrief
    ) -> StylistGarment? {
        guard !options.isEmpty else { return nil }
        let base = harmony(of: pieces) + coverage(of: pieces, brief: brief)
        var best: (StylistGarment, Double)?
        for option in options.prefix(Self.branching) {
            let candidate = pieces + [option]
            let value = harmony(of: candidate) + coverage(of: candidate, brief: brief)
            let forced = brief.pinned.contains(option.id)
            guard forced || value > base + 0.08 else { continue }
            if best == nil || value > best!.1 || forced { best = (option, forced ? .infinity : value) }
        }
        return best?.0
    }

    // MARK: Puntuación

    private func evaluate(
        _ pieces: [StylistGarment],
        brief: StylistBrief,
        random: inout SeededGenerator
    ) -> StylistLook {
        let harmonyScore = harmony(of: pieces)
        let contrastScore = contrast(of: pieces)
        let coverageScore = coverage(of: pieces, brief: brief)
        let freshnessScore = freshness(of: pieces, brief: brief)
        let score =
            harmonyScore * 1.6 + contrastScore * 0.9 + coverageScore * 1.1 + freshnessScore * 1.0
            + Double.random(in: -0.15...0.15, using: &random)

        return StylistLook(
            garmentIDs: pieces.sorted { $0.role.sortOrder < $1.role.sortOrder }.map(\.id),
            headline: headline(for: pieces),
            reason: reason(
                for: pieces,
                brief: brief,
                harmony: harmonyScore,
                contrast: contrastScore,
                freshness: freshnessScore
            ),
            score: score
        )
    }

    /// Que los colores no peleen.
    ///
    /// Los neutros no cuentan: un conjunto con negro, blanco y un azul tiene
    /// **un** color, no tres. Lo que se mide es cuántos colores de verdad hay
    /// y a qué distancia están en el círculo.
    func harmony(of pieces: [StylistGarment]) -> Double {
        let tones = pieces.map(\.tone)
        let colored = tones.filter { !$0.isNeutral }

        switch colored.count {
        case 0:
            // Todo neutro: nunca falla, tampoco emociona.
            return 0.55
        case 1:
            return 1.0
        case 2:
            guard let distance = colored[0].hueDistance(to: colored[1]) else { return 0.6 }
            switch distance {
            // El mismo color en dos tonos: siempre funciona.
            case ..<25: return 0.95
            // Vecinos —azul y verde, rojo y naranja—: funciona.
            case ..<55: return 0.85
            // La zona fea: lo bastante lejos para no ser lo mismo y lo bastante
            // cerca para que parezca un error.
            case ..<105: return 0.35
            case ..<150: return 0.6
            // Opuestos: es el contraste que se busca a propósito.
            default: return 0.9
            }
        case 3:
            // Tres colores se pueden llevar, pero hay que quererlo.
            let distances = [
                colored[0].hueDistance(to: colored[1]),
                colored[1].hueDistance(to: colored[2]),
                colored[0].hueDistance(to: colored[2]),
            ].compactMap { $0 }
            let spread = distances.min() ?? 0
            return spread > 90 ? 0.45 : 0.3
        default:
            return 0.15
        }
    }

    /// Que arriba y abajo no sean la misma mancha.
    ///
    /// Dos prendas del mismo tono medio se funden y el conjunto se ve plano;
    /// separadas en claridad, se lee cada una. No se busca el máximo —blanco
    /// puro sobre negro puro es un disfraz de camarero— sino el término medio.
    func contrast(of pieces: [StylistGarment]) -> Double {
        guard
            let top = pieces.first(where: { $0.role == .top }),
            let bottom = pieces.first(where: { $0.role == .bottom })
        else { return 0.6 }
        let delta = abs(top.tone.lightness - bottom.tone.lightness)
        switch delta {
        case ..<0.08: return 0.25
        case ..<0.18: return 0.55
        case ..<0.62: return 1.0
        default: return 0.75
        }
    }

    /// Que esté vestido y que abrigue lo que el día pide.
    private func coverage(of pieces: [StylistGarment], brief: StylistBrief) -> Double {
        var score = 0.0
        let roles = Set(pieces.map(\.role))
        let hasDress = pieces.contains { $0.kind == .wholeBody }
        if roles.contains(.top) { score += 0.5 }
        if roles.contains(.bottom) || hasDress { score += 0.5 }
        if roles.contains(.shoes) { score += 0.35 }

        let target = targetSeasons(brief)
        let wantsCold = target.contains(.winter)
        let wantsHeat = target == [.spring, .summer]
        if wantsCold { score += roles.contains(.outer) ? 0.6 : -0.5 }
        if wantsHeat, roles.contains(.outer) { score -= 0.35 }
        if let condition = brief.weather?.condition {
            switch condition {
            case .rain, .storm, .snow: score += roles.contains(.outer) ? 0.45 : -0.4
            default: break
            }
        }
        // Un complemento suma, pero poco: es la guinda, no el conjunto.
        if roles.contains(.accessory) { score += 0.12 }
        return score
    }

    /// Que no sea lo de ayer.
    private func freshness(of pieces: [StylistGarment], brief: StylistBrief) -> Double {
        var score = 0.0
        for piece in pieces where !brief.pinned.contains(piece.id) {
            guard let worn = brief.recentlyWorn[piece.id] ?? piece.lastWornAt else {
                score += 0.2
                continue
            }
            let days = brief.date.timeIntervalSince(worn) / 86_400
            switch days {
            case ..<1.5: score -= 0.9
            case ..<4: score -= 0.35
            case ..<8: score -= 0.1
            default: score += 0.15
            }
        }
        return score
    }

    // MARK: Cómo se cuenta

    private func headline(for pieces: [StylistGarment]) -> String {
        let colored = pieces.filter { !$0.tone.isNeutral }
        let families = Self.uniqued(colored.map(\.tone.familyName))
        switch families.count {
        case 0:
            let light = pieces.map(\.tone.lightness).reduce(0, +) / Double(max(1, pieces.count))
            return light > 0.6 ? "Neutros claros" : "Neutros"
        case 1:
            return families[0].capitalizedFirst + " y neutros"
        default:
            return "\(families[0].capitalizedFirst) y \(families[1])"
        }
    }

    private func reason(
        for pieces: [StylistGarment],
        brief: StylistBrief,
        harmony: Double,
        contrast: Double,
        freshness: Double
    ) -> String {
        var parts: [String] = []

        let colored = pieces.filter { !$0.tone.isNeutral }
        if colored.count >= 2,
           let distance = colored[0].tone.hueDistance(to: colored[1].tone) {
            if distance >= 150 {
                parts.append("colores opuestos, que es donde se nota")
            } else if distance < 55 {
                parts.append("colores vecinos, sin ruido")
            }
        } else if colored.count == 1 {
            parts.append("un solo color sobre neutros")
        } else if harmony > 0.5 {
            parts.append("todo en neutros")
        }

        if contrast >= 0.9 {
            parts.append("contraste entre arriba y abajo")
        } else if contrast <= 0.3 {
            parts.append("mismo tono arriba y abajo")
        }

        if let weather = brief.weather {
            let degrees = Int(((weather.highCelsius + weather.lowCelsius) / 2).rounded())
            parts.append("para \(degrees)° y \(weather.condition.label.lowercased())")
        }

        if freshness > 0.4 {
            parts.append("nada de esta semana")
        }

        if !brief.pinned.isEmpty {
            let names = pieces.filter { brief.pinned.contains($0.id) }.map(\.name)
            if let first = names.first {
                parts.append("montado alrededor de \(first.lowercasedFirst)")
            }
        }

        return parts.isEmpty ? "Combina bien con lo que tienes" : parts.joined(separator: " · ")
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    private static func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

public extension StylistRole {
    /// De arriba abajo, que es como se lee un conjunto.
    var sortOrder: Int {
        switch self {
        case .accessory: 0
        case .outer: 1
        case .top: 2
        case .bottom: 3
        case .shoes: 4
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

/// Aleatoriedad **repetible**.
///
/// Con semilla y no con `SystemRandomNumberGenerator`: la inspiración tiene
/// que poder rehacerse igual —al volver a la pantalla, al reabrir la app— y a
/// la vez ir cambiando cuando pasa el tiempo. Eso es una semilla que depende
/// de la hora, no un dado distinto en cada llamada.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Cero es un estado absorbente en SplitMix64: se queda dando el mismo
        // número para siempre.
        state = seed == 0 ? 0x4D59_5DF4_D0F3_3173 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
