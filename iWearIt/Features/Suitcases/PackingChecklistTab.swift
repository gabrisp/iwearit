import SwiftData
import SwiftUI
import WKDesign
import WKPersistence

/// Checklist de lo que ya está metido en la maleta.
///
/// Se rellena solo: al añadir una prenda a cualquier outfit de la maleta,
/// aparece aquí. Preparar outfits y hacer la maleta son la misma tarea, y
/// obligar a apuntar cada prenda dos veces sería trabajo inventado.
struct PackingChecklistTab: View {
    let suitcase: Suitcase
    /// Lo abre el "+" de la barra. Ver `SuitcaseDetailScreen`.
    @Binding var isPresentingTray: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    /// Agrupado por balda: hacer la maleta va por montones, no por orden de alta.
    private var groups: [(name: String, entries: [PackingEntry])] {
        Dictionary(grouping: suitcase.packingEntries) { entry in
            entry.garment?.category?.name ?? String(localized: "common.other", defaultValue: "Other")
        }
        .map { (name: $0.key, entries: $0.value.sorted { ($0.garment?.name ?? "") < ($1.garment?.name ?? "") }) }
        .sorted { $0.name < $1.name }
    }

    var body: some View {
        Group {
            if suitcase.packingEntries.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "suitcases.packingchecklisttab.emptySuitcase", defaultValue: "Empty suitcase"), systemImage: "suitcase")
                } description: {
                    Text(String(localized: "suitcases.packingchecklisttab.theClothesYouUseIn", defaultValue: "The clothes you use in outfits show up here on their own. You can also add them individually."))
                }
            } else {
                ScrollView {
                    VStack(spacing: WK.Spacing.l) {
                        ForEach(groups, id: \.name) { group in
                            WKSection(group.name) {
                                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                    PackingRow(
                                        entry: entry,
                                        store: appEnvironment.imageStore,
                                        showsSeparator: index < group.entries.count - 1
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, WK.Spacing.screenInset)
                    // **Sin huecos a mano.** La maleta ya no ignora el área
                    // segura: las barras de arriba y de abajo reservan su sitio
                    // solas. Con el hueco contado a mano y el área segura
                    // ignorada aquí dentro —cuando la pantalla ya la respeta—,
                    // la lista empezaba en otro sitio que las otras dos
                    // pestañas y al cambiar entre ellas todo saltaba.
                    .padding(.vertical, WK.Spacing.l)
                }
                .scrollIndicators(.hidden)
                // Lo de antes:
                // .padding(.top, suitcaseTopInset + WK.Spacing.l)
                // .padding(.bottom, 120)
                // .ignoresSafeArea(edges: [.top, .bottom])
            }
        }
        // **El papel de siempre, como las otras dos pestañas.** Outfits e
        // Inspo pintan la página con el fondo de la app y llevan el color de la
        // maleta en las tarjetas; esta dejaba ver el color de la maleta de
        // fondo, así que al cambiar de pestaña la pantalla entera cambiaba de
        // color de golpe.
        .background(WK.Palette.canvas.ignoresSafeArea())
        // **"Añadir suelta" ya no es un botón flotante**: es el "+" de la
        // barra, que además no se pelea con la barra de Outfits · Equipaje.
        //
        // .adaptiveSafeAreaBar(edge: .bottom) {
        //     WKPrimaryButton("Añadir suelta", systemImage: "plus") {
        //         isPresentingTray = true
        //     }
        //     .padding(.horizontal, WK.Spacing.screenInset)
        //     .padding(.bottom, WK.Spacing.m)
        // }
        .sheet(isPresented: $isPresentingTray) {
            // **El mismo selector que para crear un outfit**, en modo múltiple.
            // Tener dos formas distintas de elegir ropa —una rejilla aquí y las
            // baldas allí— obliga a aprender dos veces lo mismo, y la que
            // sobraba era esta.
            OutfitPickerSheet(
                mode: .many,
                title: String(localized: "suitcases.packingchecklisttab.addToLuggage", defaultValue: "Add to luggage"),
                subtitle: String(localized: "suitcases.packingchecklisttab.chooseWhatGoesInThe", defaultValue: "Choose what goes in the suitcase"),
                store: appEnvironment.imageStore
            ) { picked in
                for garment in picked {
                    SuitcasePacking.ensureEntry(for: garment, in: suitcase, context: modelContext)
                }
            }
        }
    }
}

/// Una línea del checklist.
///
/// Vista propia con su propio `@Bindable`: marcar una prenda invalida solo su
/// fila, no la lista entera.
private struct PackingRow: View {
    @Bindable var entry: PackingEntry
    let store: ImageStore
    var showsSeparator = true

    var body: some View {
        WKRow(showsSeparator: showsSeparator, action: { entry.isPacked.toggle() }) {
            HStack(spacing: WK.Spacing.m) {
                Image(systemName: entry.isPacked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(entry.isPacked ? WK.Palette.accent : WK.Palette.secondaryText)

                StoredImage(
                    key: entry.garment?.normalizedImageKey ?? "",
                    variant: .thumb,
                    store: store
                )
                .frame(width: 40, height: 46)
                .opacity(entry.isPacked ? 0.45 : 1)

                Text(entry.garment?.name ?? String(localized: "suitcases.packingchecklisttab.item", defaultValue: "Item"))
                    .foregroundStyle(WK.Palette.primaryText)
                    .strikethrough(entry.isPacked, color: WK.Palette.secondaryText)

            }
        }
        .sensoryFeedback(.selection, trigger: entry.isPacked)
    }
}
