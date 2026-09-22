import CoreLocation
import MapKit
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

    /// **Varias opciones, no una.** `CLGeocoder` devuelve casi siempre un
    /// único resultado, y si era el que no era —Valencia de Venezuela— no había
    /// forma de ver las demás. `MKLocalSearch` filtrado a direcciones devuelve
    /// las ciudades que casan, y el geocodificador queda de respaldo.
    public func search(_ query: String) async throws -> [GeoPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = .address
        var places: [GeoPlace] = []
        var seen = Set<String>()
        if let response = try? await MKLocalSearch(request: request).start() {
            for item in response.mapItems {
                guard let place = Self.place(for: item), seen.insert(place.name).inserted else { continue }
                places.append(place)
            }
        }
        if !places.isEmpty { return Array(places.prefix(12)) }

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

    private static func place(for item: MKMapItem) -> GeoPlace? {
        if #available(iOS 26, *) {
            let name = item.addressRepresentations?.cityWithContext(.full) ?? item.name
            guard let name else { return nil }
            let coordinate = item.location.coordinate
            return GeoPlace(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
        } else {
            let placemark = item.placemark
            return GeoPlace(
                name: name(for: placemark),
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude
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
