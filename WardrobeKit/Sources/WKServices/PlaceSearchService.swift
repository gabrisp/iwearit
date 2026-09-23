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
        // Veinticinco y no doce: escribir "Santiago" o "San Juan" devuelve
        // una lista larga de sitios reales, y cortarla por la mitad deja fuera
        // justo el que buscas cuando no vives en la capital.
        if !places.isEmpty { return Array(places.prefix(25)) }

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

/// Una sugerencia mientras escribes: lo que enseña el buscador de Mapas.
public struct PlaceSuggestion: Identifiable, Sendable, Hashable {
    public let id: String
    /// "Madrid", "Santiago de Compostela".
    public let title: String
    /// "España", "A Coruña, España": lo que distingue dos sitios que se
    /// llaman igual, que es justo el caso en el que una sola fila no sirve.
    public let subtitle: String
}

/// El buscador de sitios **como el de Mapas**.
///
/// ## Por qué hace falta además de `PlaceSearchService`
///
/// Porque `MKLocalSearch` resuelve una búsqueda y devuelve lo que mejor casa:
/// para "Madrid" eso es una fila, y si tu Madrid es el de Cundinamarca no hay
/// forma de llegar a él. `MKLocalSearchCompleter` es el otro extremo de la
/// misma API —lo que alimenta la lista de sugerencias de Mapas mientras
/// tecleas— y devuelve una lista de verdad, ya ordenada y con el país o la
/// provincia debajo para distinguirlas.
///
/// Se resuelve **solo lo que se elige**: las coordenadas de una sugerencia
/// cuestan una búsqueda, y pedirlas para quince filas que nadie va a tocar es
/// gastar la cuota de geocodificación en nada.
@MainActor
@Observable
public final class PlaceCompleter: NSObject {

    public private(set) var suggestions: [PlaceSuggestion] = []

    private let completer = MKLocalSearchCompleter()
    private var raw: [String: MKLocalSearchCompletion] = [:]

    public override init() {
        super.init()
        completer.delegate = self
        // Ciudades y direcciones, no cafeterías: aquí se busca dónde estás o
        // a dónde vas.
        completer.resultTypes = .address
    }

    public func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            return
        }
        completer.queryFragment = trimmed
    }

    /// Las coordenadas de la elegida.
    public func resolve(_ suggestion: PlaceSuggestion) async -> GeoPlace? {
        guard let completion = raw[suggestion.id] else { return nil }
        let request = MKLocalSearch.Request(completion: completion)
        guard
            let response = try? await MKLocalSearch(request: request).start(),
            let item = response.mapItems.first
        else { return nil }

        let name = suggestion.subtitle.isEmpty
            ? suggestion.title
            : "\(suggestion.title), \(suggestion.subtitle)"
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26, *) {
            coordinate = item.location.coordinate
        } else {
            coordinate = item.placemark.coordinate
        }
        return GeoPlace(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

// El delegado de MapKit llega en el hilo principal, pero su protocolo no lo
// promete: se marca `@preconcurrency` para poder seguir estando aislado al
// `MainActor` —que es donde vive lo que se publica— sin saltar de actor en
// cada aviso.
extension PlaceCompleter: @preconcurrency MKLocalSearchCompleterDelegate {

    public func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        var table: [String: MKLocalSearchCompletion] = [:]
        suggestions = completer.results.map { completion in
            let id = "\(completion.title)|\(completion.subtitle)"
            table[id] = completion
            return PlaceSuggestion(
                id: id,
                title: completion.title,
                subtitle: completion.subtitle
            )
        }
        raw = table
    }

    public func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DiagnosticsLog.record("SITIO", "sugerencias: \(error.localizedDescription)", isProblem: true)
    }
}
