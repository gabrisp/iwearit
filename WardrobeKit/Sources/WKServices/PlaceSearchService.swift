import CoreLocation
import Foundation
import WKCore

/// Buscar un sitio por nombre.
///
/// `CLGeocoder` y no un servicio web: es nativo, no pide clave, respeta los
/// ajustes de idioma del sistema y no manda el texto que el usuario teclea a
/// ningún tercero nuestro.
///
/// - Important: Apple limita la frecuencia de geocodificación. Por eso se
///   busca al **confirmar**, no en cada tecla: un buscador que consulta mientras
///   escribes agota la cuota y empieza a devolver errores.
public struct PlaceSearchService: Sendable {
    public init() {}

    public func search(_ query: String) async throws -> [GeoPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let placemarks = try await CLGeocoder().geocodeAddressString(trimmed)
        return placemarks.compactMap { placemark in
            guard let location = placemark.location else { return nil }
            return GeoPlace(
                name: Self.name(for: placemark),
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }
    }

    /// Ciudad y país. "Calle Mayor 3, Madrid" no es un destino de viaje, y el
    /// nombre acaba impreso en un sticker.
    private static func name(for placemark: CLPlacemark) -> String {
        let city = placemark.locality ?? placemark.name ?? "Sin nombre"
        guard let country = placemark.country, country != city else { return city }
        return "\(city), \(country)"
    }
}
