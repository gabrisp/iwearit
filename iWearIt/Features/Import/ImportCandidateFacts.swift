import SwiftUI
import WKCore
import WKDesign
import WKVision

/// Los nombres de los tipos de prenda, en un solo sitio.
///
/// Los usan la lista de revisión y la ficha de una prenda. Con la tabla
/// encerrada dentro de una de las dos vistas, la otra tenía que repetirla — y
/// el día que cambiara un nombre, cambiaría en una pantalla y no en la otra.
enum ImportCandidateLabels {
    static func label(for kind: GarmentKind) -> String {
        // En cristiano y no en jerga de base de datos: "Parte superior", no
        // "Top". Es lo que se lee en la tarjeta de la prenda.
        switch kind {
        case .upperBody: String(localized: "import.importcandidatefacts.top", defaultValue: "Top")
        case .outerLayer: String(localized: "common.jackets", defaultValue: "Jackets")
        case .lowerBody: String(localized: "import.importcandidatefacts.bottom", defaultValue: "Bottom")
        case .wholeBody: String(localized: "import.importcandidatefacts.fullBody", defaultValue: "Full body")
        case .feet: String(localized: "common.shoes", defaultValue: "Shoes")
        case .head: String(localized: "import.importcandidatefacts.accessories", defaultValue: "Accessories")
        case .bag: String(localized: "common.bags", defaultValue: "Bags")
        case .other: String(localized: "common.other", defaultValue: "Other")
        }
    }
}

/// Lo que se ha deducido de la prenda, en una línea de píldoras.
///
/// Vista propia y no un `@ViewBuilder` dentro de la fila: son cuatro datos con
/// la misma forma y distinto contenido, que es exactamente el caso en que
/// repetir el cuerpo cuesta un diff por dato en cada retoque.
///
/// Solo aparece lo que se sabe. Una píldora "Marca: —" ocupa el mismo sitio que
/// una con la marca y no dice nada; el hueco vacío ya comunica que no se
/// encontró, y sin ruido.
struct CandidateFactsRow: View {
    let candidate: ImportCandidate

    var body: some View {
        // Fluye a la siguiente línea en vez de recortarse: "Verde oliva" y
        // "Primavera/Verano" no caben en una sola línea de una fila estrecha, y
        // truncarlas deja "Prima…" que no informa de nada.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WK.Spacing.xs) { pills }
            VStack(alignment: .leading, spacing: WK.Spacing.xs) {
                HStack(spacing: WK.Spacing.xs) { pills }
            }
        }
    }

    @ViewBuilder
    private var pills: some View {
        if let brand = candidate.detected.brand {
            FactPill(label: String(localized: "import.importcandidatefacts.brand", defaultValue: "Brand"), value: brand)
        }
        if let color = candidate.detected.colors.first {
            FactPill(label: String(localized: "common.color", defaultValue: "Color"), value: color.nameKey)
        }
        if let subcategory = candidate.detected.subcategory {
            FactPill(label: String(localized: "common.type", defaultValue: "Type"), value: subcategory)
        }
        if let material = candidate.detected.material {
            FactPill(label: String(localized: "common.material", defaultValue: "Material"), value: material)
        }
        if let season = Self.seasonLabel(candidate.detected.seasons) {
            FactPill(label: String(localized: "import.importcandidatefacts.season", defaultValue: "Season"), value: season)
        }
    }

    /// `.all` no se enseña: "sirve todo el año" es lo que pasa cuando el
    /// modelo no ha sabido decidir, y enseñarlo como un dato le da un peso que
    /// no tiene.
    static func seasonLabel(_ seasons: SeasonSet) -> String? {
        switch seasons {
        case .all: nil
        case [.spring, .summer]: "P/V"
        case [.autumn, .winter]: "O/I"
        default: nil
        }
    }
}

/// Una píldora: etiqueta pequeña arriba, valor debajo. Igual que en la ficha
/// de la prenda, para que el dato se reconozca en los dos sitios.
struct FactPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(WK.Palette.secondaryText)
            Text(value)
                .font(.caption2.weight(.medium))
                .foregroundStyle(WK.Palette.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, WK.Spacing.s)
        .padding(.vertical, 3)
        .background(WK.Palette.ink(0.05), in: .rect(cornerRadius: 7, style: .continuous))
    }
}
