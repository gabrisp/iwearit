import Foundation
import Observation
import SwiftUI
import WKCore
import WKServices

/// De dónde sale el tiempo que se pega en un outfit.
///
/// Guarda **un sitio** —tu ciudad, o el destino del viaje que estés
/// preparando— y consulta el pronóstico a demanda. No usa la ubicación del
/// dispositivo: pedir permiso de localización para poner un sticker es
/// desproporcionado, y para un viaje la ubicación actual es justamente la
/// equivocada.
@MainActor
@Observable
public final class WeatherProvider {
    private let service: any WeatherService

    /// El sitio por defecto, elegido a mano y recordado.
    public private(set) var place: GeoPlace?

    /// Pronósticos ya pedidos, por sitio.
    ///
    /// Una consulta trae 16 días de golpe, así que pegar el sticker en seis
    /// días distintos del mismo viaje es **una** petición, no seis.
    private var cache: [String: [WeatherSnapshot]] = [:]

    private static let storageKey = "weatherPlace"

    public init(service: any WeatherService = OpenMeteoWeatherService()) {
        self.service = service
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            place = try? JSONDecoder().decode(GeoPlace.self, from: data)
        }
    }

    public func use(_ place: GeoPlace) {
        self.place = place
        UserDefaults.standard.set(try? JSONEncoder().encode(place), forKey: Self.storageKey)
    }

    /// El tiempo de un día. `nil` si no hay sitio elegido, si no hay red o si
    /// la fecha cae fuera del pronóstico.
    ///
    /// Devolver `nil` en vez de inventar un valor es deliberado: un sticker
    /// que dice 20° porque no pudo preguntar es peor que no poder pegarlo.
    public func snapshot(for date: Date, at override: GeoPlace? = nil) async -> WeatherSnapshot? {
        guard let target = override ?? place else { return nil }
        let day = Calendar.current.startOfDay(for: date)

        if let cached = cache[target.id]?.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: day)
        }) {
            return cached
        }

        // 16 días es el tope del servicio. Pedir menos obligaría a volver a
        // preguntar en cuanto el usuario planifica un poco más adelante.
        guard let forecast = try? await service.forecast(for: target, days: 16) else { return nil }
        cache[target.id] = forecast
        return forecast.first { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }
}
