import SwiftUI
import WKCore
import WKDesign
import WKServices

/// Buscar un sitio: tu ciudad, o el destino de un viaje.
///
/// Se busca al **confirmar**, no mientras escribes: Apple limita la frecuencia
/// de geocodificación, y consultar en cada tecla agota la cuota y empieza a
/// devolver errores justo cuando el usuario va rápido.
struct PlaceSearchSheet: View {
    let title: String
    let onPick: (GeoPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var isLocating = false
    @State private var query = ""
    /// Las sugerencias de Mapas mientras escribes. Ver `PlaceCompleter`.
    @State private var completer = PlaceCompleter()
    @State private var results: [GeoPlace] = []
    @State private var isSearching = false
    @State private var message: String?

    private let service = PlaceSearchService()

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.m) {
            Text(title)
                .font(WK.Font.title)
                .foregroundStyle(WK.Palette.primaryText)

            HStack(spacing: WK.Spacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WK.Palette.secondaryText)
                TextField("Ciudad", text: $query)
                    .font(WK.Font.rowTitle)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if isSearching { ProgressView().controlSize(.small) }
            }
            .padding(WK.Spacing.m)
            .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                    .stroke(WK.Palette.ink(0.07), lineWidth: 1)
            )

            // **Y lo primero, dónde estás.** Escribir la ciudad funciona, pero
            // es un paso que casi nadie da: sin él la app viste por el mes del
            // calendario en vez de por los grados que hace. El permiso se pide
            // aquí, con el motivo delante.
            WKSection {
                WKRow(showsSeparator: false, action: { Task { await locate() } }) {
                    HStack {
                        Label("Usar mi ubicación", systemImage: "location.fill")
                            .foregroundStyle(WK.Palette.primaryText)
                        Spacer()
                        if isLocating { ProgressView().controlSize(.small) }
                    }
                }
            }

            if let message {
                Text(message)
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
            }

            // **La lista de Mapas, no un resultado.**
            //
            // `MKLocalSearch` resuelve la búsqueda y devuelve lo que mejor
            // casa: para "Madrid", una fila. Si tu Madrid es otro, no había
            // forma de llegar. El completador devuelve la lista de verdad, con
            // el país o la provincia debajo para distinguir los que se llaman
            // igual. Ver `PlaceCompleter`.
            WKSection {
                ForEach(Array(completer.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    WKRow(
                        showsSeparator: index < completer.suggestions.count - 1,
                        action: { Task { await choose(suggestion) } }
                    ) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .foregroundStyle(WK.Palette.primaryText)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(WK.Font.caption)
                                        .foregroundStyle(WK.Palette.secondaryText)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(WK.Palette.tertiaryText)
                        }
                    }
                }
            }
            .opacity(completer.suggestions.isEmpty ? 0 : 1)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .wkDynamicSheet()
        // Mientras escribes: el completador no geocodifica, solo sugiere, así
        // que no hay cuota que agotar ni pausa que respetar.
        .onChange(of: query) { _, new in
            message = nil
            completer.update(query: new)
        }
    }

    /// Pregunta al sistema dónde estamos y lo usa como sitio.
    private func locate() async {
        isLocating = true
        defer { isLocating = false }
        guard let place = await appEnvironment.location.current() else {
            message = appEnvironment.location.isDenied
                ? "Sin permiso de ubicación. Puedes escribir la ciudad o dárselo en Ajustes."
                : "No se pudo saber dónde estás. Prueba a escribir la ciudad."
            return
        }
        onPick(place)
        dismiss()
    }

    /// Resuelve la sugerencia elegida y la devuelve.
    private func choose(_ suggestion: PlaceSuggestion) async {
        isSearching = true
        defer { isSearching = false }
        guard let place = await completer.resolve(suggestion) else {
            message = "No se pudo situar ese sitio. Prueba con otro."
            return
        }
        onPick(place)
        dismiss()
    }

    private func search() async {
        isSearching = true
        message = nil
        defer { isSearching = false }

        do {
            let found = try await service.search(query)
            results = found
            // Decirlo en vez de dejar la lista vacía sin más: vacío se lee como
            // "todavía no ha buscado", no como "no existe".
            if found.isEmpty { message = "No se encontró ningún sitio con ese nombre." }
        } catch {
            results = []
            message = "No se pudo buscar ahora mismo. Inténtalo en un momento."
        }
    }
}
