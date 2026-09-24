import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Lo que el escaneo encontró y espera a que decidas: la rejilla y el
/// selector, **una sola pieza** para el onboarding y para el armario.
///
/// ## Por qué desde dos sitios
///
/// Porque decidir doscientas prendas de una sentada al final del onboarding no
/// es lo que apetece: se quedan las obvias y el resto espera. Lo que no se
/// importa no se pierde —está guardado como pendiente, ver `PendingGarment`—
/// y el armario tiene una entrada para volver a ello cuando quieras.
struct PendingGarmentsGrid: View {
    /// Lo marcado, por id del pendiente.
    @Binding var selection: Set<UUID>

    @Environment(AppEnvironment.self) private var appEnvironment

    /// Lo reciente primero: es lo que llevas ahora, y lo que más probablemente
    /// quieras en el armario.
    @Query(sort: [
        SortDescriptor(\PendingGarment.photoDate, order: .reverse),
        SortDescriptor(\PendingGarment.foundAt, order: .reverse),
    ])
    private var pending: [PendingGarment]

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: WK.Spacing.m)]

    var body: some View {
        VStack(spacing: WK.Spacing.s) {
            selectionBar
            ScrollView {
                LazyVGrid(columns: columns, spacing: WK.Spacing.m) {
                    // **Por id, no por la clave de la imagen.** Dos recortes
                    // idénticos tienen la misma clave, y con ella de
                    // identidad la rejilla pintaba dos celdas como una sola y
                    // se descolocaba al marcar —la otra mitad del "salen
                    // repetidas"—.
                    ForEach(pending) { item in
                        PendingCell(
                            item: item,
                            store: appEnvironment.imageStore,
                            isSelected: selection.contains(item.id)
                        ) { toggle(item.id) }
                    }
                }
                // Tanto aire como degradado: en reposo la primera y la
                // última fila se ven enteras, y solo se desvanece lo que
                // pasa por el borde al desplazar.
                .padding(.top, WK.Spacing.l)
                .padding(.bottom, WK.Spacing.xl)
                // Aire dentro del scroll para la sombra del cristal: sin él,
                // el borde del scroll la cortaba en seco y se veía una franja.
                .padding(.horizontal, WK.Spacing.m)
            }
            .padding(.horizontal, -WK.Spacing.m)
            .scrollIndicators(.hidden)
            // Las prendas se desvanecen al llegar arriba y abajo en vez de
            // cortarse en seco contra el borde.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: WK.Spacing.l)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: WK.Spacing.xl)
                }
            }
        }
    }

    private var selectionBar: some View {
        HStack {
            Text("\(selection.count) de \(pending.count)")
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
                .monospacedDigit()
                .contentTransition(.numericText())

            Spacer(minLength: 0)

            Button(selection.count == pending.count ? "Ninguna" : "Todas") {
                withAnimation(WKAnimation.selection) {
                    selection = selection.count == pending.count ? [] : Set(pending.map(\.id))
                }
            }
            .font(WK.Font.captionMedium)
            .foregroundStyle(WK.Palette.primaryText)
            .padding(.horizontal, WK.Spacing.m)
            .padding(.vertical, WK.Spacing.s)
            .contentShape(.capsule)
            .buttonStyle(.plain)
            .adaptiveGlassInteractive(in: .capsule)
        }
        .animation(WKAnimation.selection, value: selection.count)
    }

    private func toggle(_ id: UUID) {
        withAnimation(WKAnimation.selection) {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        }
    }
}

/// Importar y descartar lo pendiente.
///
/// Fuera de la vista porque lo usan dos pantallas y las dos tienen que hacer
/// exactamente lo mismo: lo importado entra al armario **y deja de estar
/// pendiente**, en ese orden, para que un fallo a mitad no lo deje en los dos
/// sitios a la vez ni en ninguno.
@MainActor
enum PendingGarments {
    /// Mete en el armario lo elegido y lo quita de pendientes.
    static func importing(
        _ ids: Set<UUID>,
        context: ModelContext,
        wardrobe: WardrobeActor
    ) async {
        let chosen = fetch(ids, context: context)
        let drafts = chosen.compactMap(\.draft)
        // Por lotes, como el escaneo: una transacción por prenda con cien
        // prendas son cien transacciones y varios segundos de pantalla quieta.
        for start in stride(from: 0, to: drafts.count, by: WardrobeActor.batchSize) {
            let slice = Array(drafts[start..<min(start + WardrobeActor.batchSize, drafts.count)])
            try? await wardrobe.insert(slice)
        }
        for item in chosen { context.delete(item) }
        try? context.save()
        DiagnosticsLog.record("ESCANEO", "importadas \(drafts.count) pendientes")
    }

    /// Descarta lo elegido. Los recortes se quedan en disco hasta que el
    /// recolector de arranque vea que ya nadie los usa.
    static func discarding(_ ids: Set<UUID>, context: ModelContext) {
        for item in fetch(ids, context: context) { context.delete(item) }
        try? context.save()
        DiagnosticsLog.record("ESCANEO", "descartadas \(ids.count) pendientes")
    }

    private static func fetch(_ ids: Set<UUID>, context: ModelContext) -> [PendingGarment] {
        let all = (try? context.fetch(FetchDescriptor<PendingGarment>())) ?? []
        return all.filter { ids.contains($0.id) }
    }
}

/// Una prenda pendiente, para marcarla o no.
///
/// Se pinta desde el `ImageStore` por su clave: el recorte ya está en disco
/// aunque la prenda todavía no exista en el armario.
private struct PendingCell: View {
    let item: PendingGarment
    let store: ImageStore
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // **La prenda con su recorte, sin caja.** Como cuelga en el
            // armario: la silueta y su sombra. Metida en un rectángulo de
            // cristal parecía una foto de carné y no ropa.
            StoredImage(key: item.imageKey, variant: .thumb, store: store)
                .frame(height: 104)
                .shadow(color: .black.opacity(isSelected ? 0.18 : 0.06), radius: 8, y: 5)
                .saturation(isSelected ? 1 : 0.2)
                .padding(WK.Spacing.xs)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.footnote)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            isSelected ? WK.Palette.onAccent : WK.Palette.secondaryText,
                            isSelected ? WK.Palette.accent : WK.Palette.ink(0.10)
                        )
                        .padding(WK.Spacing.xs)
                }
                .contentShape(.rect)
        }
        // .buttonStyle(.plain)
        // .adaptiveGlassInteractive(in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))
        // .overlay {
        //     RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
        //         .strokeBorder(WK.Palette.accent, lineWidth: isSelected ? 2 : 0)
        // }
        // Sin caja ni borde: lo marcado se ve por el color, la sombra y el
        // círculo; lo desmarcado se apaga.
        .buttonStyle(WKPressStyle())
        .opacity(isSelected ? 1 : 0.45)
        .animation(WKAnimation.selection, value: isSelected)
    }
}

/// Lo pendiente, desde el armario: la misma rejilla en una hoja.
struct PendingGarmentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query private var pending: [PendingGarment]
    @State private var selection: Set<UUID> = []
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            PendingGarmentsGrid(selection: $selection)
                .padding(.horizontal, WK.Spacing.screenInset)
                .navigationTitle("Por revisar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .tint(WK.Palette.primaryText)
                    }
                }
                .adaptiveSafeAreaBar(edge: .bottom) {
                    VStack(spacing: WK.Spacing.s) {
                        WKPrimaryButton(
                            isWorking ? "Añadiendo…" : "Añadir \(selection.count)",
                            surface: .glass
                        ) {
                            Task { await importSelected() }
                        }
                        .disabled(selection.isEmpty || isWorking)
                        .opacity(selection.isEmpty ? 0.4 : 1)

                        // Descartar lo que **no** está marcado: la forma de
                        // limpiar la lista cuando ya te has quedado con lo que
                        // querías.
                        if selection.count < pending.count {
                            Button { discardUnselected() } label: {
                                Text("Descartar las no marcadas")
                                    .font(WK.Font.callout)
                                    .foregroundStyle(WK.Palette.secondaryText)
                                    .padding(.horizontal, WK.Spacing.m)
                                    .padding(.vertical, WK.Spacing.s)
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .adaptiveGlassInteractive(in: .capsule)
                        }
                    }
                    .padding(.horizontal, WK.Spacing.screenInset)
                    .padding(.bottom, WK.Spacing.s)
                }
                .task {
                    if selection.isEmpty { selection = Set(pending.map(\.id)) }
                }
                .onChange(of: pending.isEmpty) { _, isEmpty in
                    if isEmpty { dismiss() }
                }
        }
    }

    private func importSelected() async {
        isWorking = true
        defer { isWorking = false }
        await PendingGarments.importing(selection, context: modelContext, wardrobe: appEnvironment.wardrobe)
        selection = []
    }

    private func discardUnselected() {
        let rest = Set(pending.map(\.id)).subtracting(selection)
        withAnimation(WKAnimation.content) {
            PendingGarments.discarding(rest, context: modelContext)
        }
    }
}

/// La entrada a lo pendiente desde el armario: una píldora arriba del todo,
/// **solo mientras quede algo por decidir**.
///
/// Arriba y no al final porque es lo que tienes a medias: al final, debajo de
/// todas las baldas, no la vería nadie y los pendientes se quedarían ahí para
/// siempre.
struct PendingGarmentsPill: View {
    let action: () -> Void

    @Query private var pending: [PendingGarment]

    var body: some View {
        if !pending.isEmpty {
            Button(action: action) {
                Label(
                    "\(pending.count.formatted()) \(pending.count == 1 ? "prenda" : "prendas") por revisar",
                    systemImage: "tray.full"
                )
                .font(WK.Font.captionMedium)
                .foregroundStyle(WK.Palette.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(pending.count)))
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .contentShape(.capsule)
            }
            .buttonStyle(WKPressStyle())
            .adaptiveGlassInteractive(in: .capsule)
            .frame(maxWidth: .infinity)
            .padding(.vertical, WK.Spacing.s)
            .transition(AnyTransition(.blurReplace))
        }
    }
}
