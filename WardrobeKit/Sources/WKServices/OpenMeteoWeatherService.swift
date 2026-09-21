import Foundation
import WKCore

/// El tiempo, por REST.
///
/// **Open-Meteo y no WeatherKit**, al menos de momento: WeatherKit exige una
/// capacidad activada en el portal de Apple y un App ID configurado, así que no
/// funciona hasta que alguien entra a la web a habilitarlo. Open-Meteo no pide
/// clave ninguna, su uso no comercial y comercial está permitido con
/// atribución, y así el tiempo funciona desde el primer arranque.
///
/// Cambiar a WeatherKit es escribir otra implementación de `WeatherService`;
/// ninguna vista sabe de dónde sale el dato.
public struct OpenMeteoWeatherService: WeatherService {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func forecast(for place: GeoPlace, days: Int) async throws -> [WeatherSnapshot] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            // Sin esto las fechas vuelven en UTC y el "martes" del servidor no
            // es el martes del usuario.
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: String(max(1, min(days, 16)))),
        ]
        guard let url = components.url else { throw WeatherError.badRequest }

        let (data, response) = try await session.data(from: url)
        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else { throw WeatherError.server }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.snapshots(place: place.name)
    }

    public enum WeatherError: Error, LocalizedError {
        case badRequest
        case server

        public var errorDescription: String? {
            switch self {
            case .badRequest: "No se pudo preguntar por el tiempo"
            case .server: "El servicio del tiempo no responde"
            }
        }
    }

    // MARK: - Respuesta

    private struct Payload: Decodable {
        let daily: Daily

        struct Daily: Decodable {
            let time: [String]
            let weatherCode: [Int]
            let temperatureMax: [Double]
            let temperatureMin: [Double]

            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case temperatureMax = "temperature_2m_max"
                case temperatureMin = "temperature_2m_min"
            }
        }

        /// Fechas locales, sin hora. `timezone=auto` las devuelve ya en la zona
        /// del sitio consultado, así que no hay que reinterpretarlas.
        private static let day: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        func snapshots(place: String?) -> [WeatherSnapshot] {
            // `zip` triple por índice: si el servidor devolviera arrays de
            // distinta longitud —no debería, pero es una API ajena— esto se
            // queda en el más corto en vez de caerse por índice fuera de rango.
            let count = min(
                daily.time.count,
                min(daily.weatherCode.count, min(daily.temperatureMax.count, daily.temperatureMin.count))
            )
            return (0..<count).compactMap { index in
                guard let date = Self.day.date(from: daily.time[index]) else { return nil }
                return WeatherSnapshot(
                    condition: Self.condition(for: daily.weatherCode[index]),
                    highCelsius: daily.temperatureMax[index],
                    lowCelsius: daily.temperatureMin[index],
                    place: place,
                    date: date
                )
            }
        }

        /// Códigos WMO → las ocho categorías que usamos.
        ///
        /// El estándar tiene casi treinta valores y muchos piden la misma ropa:
        /// "llovizna ligera" y "lluvia moderada" son lluvia, y separarlas solo
        /// añadiría iconos que no cambian ninguna decisión.
        static func condition(for code: Int) -> WeatherCondition {
            switch code {
            case 0: .clear
            case 1, 2: .cloudy
            case 3: .overcast
            case 45, 48: .fog
            case 51...67, 80...82: .rain
            case 71...77, 85, 86: .snow
            case 95...99: .storm
            default: .cloudy
            }
        }
    }
}
