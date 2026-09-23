import CoreLocation
import Foundation
import Observation
import WKCore

/// Dónde estás, cuando quieres que lo sepa.
///
/// ## Por qué existe y por qué es tan pequeño
///
/// El tiempo hace falta para vestir: no es lo mismo un martes de ocho grados
/// que uno de treinta. Hasta ahora el sitio se elegía a mano —se escribía la
/// ciudad— y eso funciona, pero es un paso que casi nadie da: la pestaña de
/// inspiración se abría sin parte meteorológico y el estilista vestía por el
/// mes del calendario.
///
/// ## Una lectura y se apaga
///
/// `requestLocation` y no seguimiento continuo: lo que hace falta es la ciudad,
/// no el movimiento. Se pide una posición, se traduce a un nombre y el
/// localizador se para solo. Nada se guarda aquí ni sale del dispositivo: la
/// ciudad la usa el proveedor del tiempo, que es quien pregunta fuera.
///
/// ## Y el permiso se pide cuando sirve
///
/// No al arrancar la app —donde no hay nada que explique para qué—, sino la
/// primera vez que se abre la inspiración o se toca "usar mi ubicación": ahí el
/// motivo está delante y la respuesta es informada.
@MainActor
@Observable
public final class LocationProvider: NSObject {

    public enum State: Equatable {
        case idle
        case asking
        case locating
        case ready(GeoPlace)
        /// Sin permiso, o el sistema no lo permite. **No es un error**: el
        /// sitio se puede seguir escribiendo a mano.
        case denied
        case failed(String)
    }

    public private(set) var state: State = .idle

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<GeoPlace?, Never>?

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Si ya se ha preguntado alguna vez, sea cual sea la respuesta.
    public var hasBeenAsked: Bool {
        manager.authorizationStatus != .notDetermined
    }

    public var isDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    /// Pide la ubicación —y el permiso, si hace falta— y devuelve la ciudad.
    ///
    /// - Returns: `nil` si no hay permiso o no se pudo resolver. Quien llama
    ///   sigue pudiendo ofrecer escribir la ciudad a mano.
    @discardableResult
    public func current() async -> GeoPlace? {
        guard !isDenied else {
            state = .denied
            return nil
        }
        if case let .ready(place) = state { return place }

        if manager.authorizationStatus == .notDetermined {
            state = .asking
            manager.requestWhenInUseAuthorization()
        }
        state = .locating

        let located: GeoPlace? = await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
        if let located { state = .ready(located) }
        return located
    }

    private func finish(_ place: GeoPlace?) {
        continuation?.resume(returning: place)
        continuation = nil
    }

    /// El nombre de la ciudad, no la calle: para el tiempo sobra el portal.
    nonisolated private static func name(for placemark: CLPlacemark) -> String {
        placemark.locality
            ?? placemark.subAdministrativeArea
            ?? placemark.administrativeArea
            ?? placemark.country
            ?? "Aquí"
    }
}

extension LocationProvider: CLLocationManagerDelegate {

    nonisolated public func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            // El nombre, del geocodificador inverso. Si no contesta, se usa
            // la posición igual: el tiempo se pide por coordenadas, y el
            // nombre es solo lo que se lee arriba.
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            let place = GeoPlace(
                name: placemark.map(Self.name(for:)) ?? "Aquí",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            DiagnosticsLog.record("UBICACIÓN", "resuelta: \(place.name)")
            finish(place)
        }
    }

    nonisolated public func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            DiagnosticsLog.record("UBICACIÓN", "falló: \(error.localizedDescription)", isProblem: true)
            state = .failed(error.localizedDescription)
            finish(nil)
        }
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // El estado se lee aquí y lo que cruza al hilo principal es **un
        // valor**: el propio `CLLocationManager` no es `Sendable`, y pasarlo
        // dentro de la tarea es justo lo que Swift 6 marca como carrera.
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .denied, .restricted:
                state = .denied
                finish(nil)
            case .authorizedWhenInUse, .authorizedAlways:
                // Recién concedido: la petición que esperaba sigue viva, así
                // que se le da lo que pidió — y se le pide al de dentro, que
                // es el que vive en este actor.
                if continuation != nil { self.manager.requestLocation() }
            default:
                break
            }
        }
    }
}
