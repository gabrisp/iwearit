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

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var isPresentingTray = false

    /// Agrupado por balda: hacer la maleta va por montones, no por orden de alta.
    private var groups: [(name: String, entries: [PackingEntry])] {
        Dictionary(grouping: suitcase.packingEntries) { entry in
            entry.garment?.category?.name ?? "Otros"
        }
        .map { (name: $0.key, entries: $0.value.sorted { ($0.garment?.name ?? "") < ($1.garment?.name ?? "") }) }
        .sorted { $0.name < $1.name }
    }

    var body: some View {
        Group {
            if suitcase.packingEntries.isEmpty {
                ContentUnavailableView {
                    Label("Maleta vacía", systemImage: "suitcase")
                } description: {
                    Text("Las prendas que uses en los outfits aparecen aquí solas. También puedes añadirlas sueltas.")
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
                    .padding(.bottom, WK.Spacing.xxl)
                }
                .scrollIndicators(.hidden)
            }
        }
        .adaptiveSafeAreaBar(edge: .bottom) {
            WKPrimaryButton("Añadir suelta", systemImage: "plus") {
                isPresentingTray = true
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.m)
        }
        .sheet(isPresented: $isPresentingTray) {
            // **El mismo selector que para crear un outfit**, en modo múltiple.
            // Tener dos formas distintas de elegir ropa —una rejilla aquí y las
            // baldas allí— obliga a aprender dos veces lo mismo, y la que
            // sobraba era esta.
            OutfitPickerSheet(
                mode: .many,
                title: "Añadir al equipaje",
                subtitle: "Elige lo que va en la maleta",
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

                Text(entry.garment?.name ?? "Prenda")
                    .foregroundStyle(WK.Palette.primaryText)
                    .strikethrough(entry.isPacked, color: WK.Palette.secondaryText)

            }
        }
        .sensoryFeedback(.selection, trigger: entry.isPacked)
    }
}
