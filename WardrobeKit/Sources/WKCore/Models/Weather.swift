import Foundation

/// El tiempo de un día en un sitio.
///
/// Es una **foto fija**, no una consulta viva. Un outfit guardado para el
/// martes que viene tiene que seguir diciendo lo mismo el jueves siguiente:
/// si el sticker releyera el tiempo, un outfit de hace un mes mostraría el de
/// hoy y contaría una mentira sobre por qué te vestiste así.
public struct WeatherSnapshot: Sendable, Equatable, Codable {
    public let condition: WeatherCondition
    /// Grados Celsius. La conversión a Fahrenheit es de presentación: guardar
    /// en la unidad del sistema ataría el dato a los ajustes del momento.
    public let highCelsius: Double
    public let lowCelsius: Double
    /// Dónde. `nil` cuando es la ubicación actual y no se resolvió el nombre.
    public let place: String?
    public let date: Date

    public init(
        condition: WeatherCondition,
        highCelsius: Double,
        lowCelsius: Double,
        place: String?,
        date: Date
    ) {
        self.condition = condition
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.place = place
        self.date = date
    }
}

/// Lo que hace, en las categorías que cambian cómo te vistes.
///
/// No son las 100 clases de un servicio meteorológico: "llovizna ligera" y
/// "lluvia moderada" piden el mismo abrigo, y separarlas solo añade iconos que
/// no deciden nada.
public enum WeatherCondition: String, Sendable, Codable, CaseIterable {
    case clear, cloudy, overcast, rain, snow, storm, fog, wind

    public var symbolName: String {
        switch self {
        case .clear: "sun.max.fill"
        case .cloudy: "cloud.sun.fill"
        case .overcast: "cloud.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "snowflake"
        case .storm: "cloud.bolt.rain.fill"
        case .fog: "cloud.fog.fill"
        case .wind: "wind"
        }
    }

    public var label: String {
        switch self {
        case .clear: "Despejado"
        case .cloudy: "Nubes y claros"
        case .overcast: "Cubierto"
        case .rain: "Lluvia"
        case .snow: "Nieve"
        case .storm: "Tormenta"
        case .fog: "Niebla"
        case .wind: "Viento"
        }
    }

    /// Qué abrigo pide. Es lo que permite cruzar el tiempo con el armario sin
    /// inventar una segunda escala.
    public var suggestedWarmth: SeasonSet {
        switch self {
        case .snow, .storm: [.autumn, .winter]
        case .rain, .fog, .overcast, .wind: .all
        case .clear, .cloudy: [.spring, .summer]
        }
    }
}

/// Un sitio del mundo, con nombre.
public struct GeoPlace: Sendable, Equatable, Codable, Identifiable {
    public var id: String { "\(latitude),\(longitude)" }
    public let name: String
    public let latitude: Double
    public let longitude: Double

    public init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// De dónde sale el tiempo.
///
/// Tras protocolo como el resto de servicios: cambiar de proveedor —a
/// WeatherKit, por ejemplo, que pide capacidad y configuración en el portal—
/// es escribir otra implementación, no tocar ninguna vista.
public protocol WeatherService: Sendable {
    /// - Parameter days: cuántos días desde hoy, incluido hoy.
    func forecast(for place: GeoPlace, days: Int) async throws -> [WeatherSnapshot]
}
