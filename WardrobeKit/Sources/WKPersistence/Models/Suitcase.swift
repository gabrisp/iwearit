import Foundation
import SwiftData
import WKCore

/// Una maleta. Vive **dentro del Armario**, como balda "altillo" al final —
/// no es una pestaña.
@Model
public final class Suitcase {
    public var id: UUID = UUID()
    public var name: String = ""
    /// Opcionales: una maleta sin fechas tiene outfits "preparados" en vez de
    /// asignados a días concretos.
    public var startDate: Date?
    public var endDate: Date?
    public var coverKey: String?

    // MARK: Destino
    //
    // Campos sueltos y no un `GeoPlace` codificado: el nombre se enseña en
    // listas y cabeceras, y tenerlo dentro de un `Data` obligaría a decodificar
    // para pintar una celda.

    /// Icono y color de la maleta.
    ///
    /// Con varias maletas a la vez —un viaje de trabajo, una escapada, la bolsa
    /// del gimnasio— el nombre en pequeño no distingue nada a la velocidad a la
    /// que se mira una balda. La forma y el color sí.
    public var symbolName: String = "suitcase.fill"
    public var colorRaw: String?

    public var destinationName: String?
    public var destinationLatitude: Double?
    public var destinationLongitude: Double?
    public var createdAt: Date = Date()
    public var modifiedAt: Date = Date()
    public var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Outfit.suitcase)
    public var outfits: [Outfit] = []

    @Relationship(deleteRule: .cascade, inverse: \PackingEntry.suitcase)
    public var packingEntries: [PackingEntry] = []

    public init(id: UUID = UUID(), name: String, startDate: Date? = nil, endDate: Date? = nil) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = Date()
    }

    public var hasDates: Bool { startDate != nil && endDate != nil }

    /// El destino, si está puesto.
    public var destination: GeoPlace? {
        get {
            guard
                let destinationName,
                let destinationLatitude,
                let destinationLongitude
            else { return nil }
            return GeoPlace(
                name: destinationName,
                latitude: destinationLatitude,
                longitude: destinationLongitude
            )
        }
        set {
            destinationName = newValue?.name
            destinationLatitude = newValue?.latitude
            destinationLongitude = newValue?.longitude
        }
    }

    public var packedCount: Int { packingEntries.count { $0.isPacked } }

    /// Días que dura el viaje, ambos incluidos. `nil` si la maleta no tiene
    /// fechas — entonces los outfits van sin día, simplemente preparados.
    public var tripDayCount: Int? {
        guard let startDate, let endDate else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: startDate),
            to: calendar.startOfDay(for: endDate)
        ).day ?? 0
        return max(1, days + 1)
    }

    public func date(forDayIndex index: Int) -> Date? {
        guard let startDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: index, to: startDate)
    }

    public func outfit(forDayIndex index: Int) -> Outfit? {
        outfits.first { $0.suitcaseDayIndex == index }
    }
}

/// Una línea del checklist de equipaje.
@Model
public final class PackingEntry {
    public var id: UUID = UUID()
    public var isPacked: Bool = false
    public var addedAt: Date = Date()

    public var garment: Garment?
    public var suitcase: Suitcase?

    public init(garment: Garment?) {
        self.id = UUID()
        self.garment = garment
        self.addedAt = Date()
    }
}
