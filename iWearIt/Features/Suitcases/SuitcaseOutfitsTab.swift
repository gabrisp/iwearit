import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// Los outfits de una maleta.
///
/// Con fechas, cada día del viaje es una página con su canvas y se pasa como en
/// el planificador. Sin fechas, los outfits quedan simplemente **preparados**,
/// sin día asignado, que es como se prepara una maleta cuando aún no sabes qué
/// te vas a poner cada día.
struct SuitcaseOutfitsTab: View {
    let suitcase: Suitcase
    @Binding var dayIndex: Int
    /// Para que el editor crezca desde la celda tocada en la rejilla.
    let zoom: Namespace.ID
    /// Pide a la pantalla que **empuje** el editor.
    ///
    /// La página no puede navegar por su cuenta: vive en su propio
    /// `UIHostingController` dentro del pager, fuera de la pila. Por eso lo
    /// pide hacia arriba en vez de presentarlo a pantalla completa.
    let onEdit: (Outfit) -> Void

    var body: some View {
        if let dayCount = suitcase.tripDayCount {
            DatedOutfits(
                suitcase: suitcase,
                dayCount: dayCount,
                dayIndex: $dayIndex,
                onEdit: onEdit
            )
        } else {
            PreparedOutfits(suitcase: suitcase, onEdit: onEdit, zoom: zoom)
        }
    }
}

/// Maleta con fechas: una página por día del viaje.
struct DatedOutfits: View {
    let suitcase: Suitcase
    let dayCount: Int
    @Binding var dayIndex: Int
    let onEdit: (Outfit) -> Void

    var body: some View {
        // El mismo pager del planificador: el paso de página solo arranca
        // desde el borde, así que el canvas conserva el arrastre libre.
        //
        // Sin `VStack` con la tira encima: la tira vive en la barra superior de
        // la pantalla, flotando **sobre** el lienzo, igual que fuera.
        // Acotado al viaje. Sin el tope, pasar página después del último día
        // seguía funcionando y enseñaba **el mismo día otra vez** —el índice se
        // recortaba al pintar, no al pasar—, así que el viaje parecía no
        // acabarse nunca.
        EdgeCurlPager(index: $dayIndex, bounds: 0...(dayCount - 1)) { index in
            TripDayPage(
                suitcase: suitcase,
                dayIndex: max(0, min(index, dayCount - 1)),
                onEdit: onEdit
            )
        }
        .ignoresSafeArea()
    }
}

/// Tira de días del viaje. Acotada al viaje, no infinita como la del
/// planificador: una maleta dura lo que dura, y dejar deslizar más allá del
/// último día ofrece planificar algo que no existe.
struct TripDayBar: View {
    let suitcase: Suitcase
    let dayCount: Int
    @Binding var selected: Int

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.xs) {
                ForEach(0..<dayCount, id: \.self) { index in
                    TripDayChip(
                        index: index,
                        date: suitcase.date(forDayIndex: index),
                        isSelected: index == selected,
                        hasOutfit: suitcase.outfit(forDayIndex: index) != nil
                    )
                    .onTapGesture { selected = index }
                }
            }
            .padding(.horizontal, WK.Spacing.s)
        }
        .scrollIndicators(.hidden)
        .frame(height: 56)
        .clipShape(.capsule)
        .adaptiveGlassInteractive(in: .capsule)
        .padding(.horizontal, WK.Spacing.m)
    }
}

/// Un día del viaje en la tira.
///
/// Día del viaje **y** fecha: "Día 3" solo no sirve para decidir qué llevar, y
/// "26 SEP" solo pierde de vista cuánto dura el viaje.
struct TripDayChip: View {
    let index: Int
    let date: Date?
    let isSelected: Bool
    let hasOutfit: Bool

    private static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()

    private static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    var body: some View {
        // Número pequeño arriba y mes grande debajo. En un viaje de cinco días
        // todos los números son consecutivos y no distinguen nada; lo que sitúa
        // el día es el mes, y más aún cuando el viaje cruza de un mes a otro.
        VStack(spacing: -1) {
            Text(date.map { Self.dayNumber.string(from: $0) } ?? "\(index + 1)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(
                    isSelected ? WK.Palette.onAccent.opacity(0.75) : WK.Palette.secondaryText
                )

            Text(date.map { Self.month.string(from: $0).uppercased() } ?? "DÍA")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isSelected ? WK.Palette.onAccent : WK.Palette.primaryText)

            // Un punto si ese día ya tiene outfit. Es lo que deja ver de un
            // vistazo cuánto queda por preparar sin abrir día por día.
            Circle()
                .fill(isSelected ? WK.Palette.onAccent : WK.Palette.accent)
                .frame(width: 5, height: 5)
                .opacity(hasOutfit ? 1 : 0)
                .padding(.top, 2)
        }
        .padding(.horizontal, WK.Spacing.m)
        .frame(height: 46)
        .background {
            if isSelected { Capsule().fill(WK.Palette.accent) }
        }
        .contentShape(.capsule)
    }
}

/// Un día del viaje: su lienzo.
///
/// **Exactamente la misma pantalla que un día del planificador.** Preparar la
/// maleta del jueves y planificar el jueves son la misma tarea; que una fuera
/// un compositor por huecos y la otra un lienzo obligaba a aprender dos formas
/// de montar un outfit según por dónde hubieras entrado.
///
/// - Important: fondo opaco, como en el planificador. `pageCurl` no sabe
///   enrollar una página transparente.
struct TripDayPage: View {
    let suitcase: Suitcase
    let dayIndex: Int
    let onEdit: (Outfit) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var isPickingGarments = false
    @State private var selection = CanvasSelection()

    private var outfit: Outfit? { suitcase.outfit(forDayIndex: dayIndex) }

    var body: some View {
        ZStack {
            DotGridBackground().allowsHitTesting(false)

            if let outfit, !outfit.visibleItems.isEmpty {
                FreeformCanvas(outfit: outfit, store: appEnvironment.imageStore, selection: selection)
                    .allowsHitTesting(false)
                    // **Al editor desde el propio lienzo**, igual que en el
                    // plan: doble toque y mantener pulsado. Un toque simple no
                    // puede ser —compite con el paso de página—, y cuál de las
                    // dos espera cada uno depende de si vienes de una app de
                    // fotos o de una de notas.
                    .onTapGesture(count: 2) { onEdit(ensureOutfit()) }
                    .onLongPressGesture(minimumDuration: 0.4) { onEdit(ensureOutfit()) }
                    // En todo el lienzo: sin esto el gesto solo existe donde
                    // hay una prenda pintada, y el hueco entre ellas —que es
                    // casi todo— no respondería.
                    .contentShape(.rect)
            } else if let date = suitcase.date(forDayIndex: dayIndex) {
                EmptyDayPrompt(date: date) { isPickingGarments = true }
            }
        }
        // **El lápiz, también aquí.** Faltaba: dentro de una maleta no había
        // forma de abrir el editor, así que un outfit de viaje se podía montar
        // pero no retocar.
        .overlay(alignment: .bottomTrailing) {
            DayActionButton(symbol: "pencil") { onEdit(ensureOutfit()) }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.xl)
        }
        .sheet(isPresented: $isPickingGarments) {
            OutfitPickerSheet(store: appEnvironment.imageStore) { picked in
                fill(with: picked)
                onEdit(ensureOutfit())
            }
        }
        // Lo que se meta en el outfit del viaje entra solo en el checklist:
        // preparar el look y hacer la maleta son la misma tarea.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backdropColor)
        .onChange(of: outfit?.items.count ?? 0) { syncPacking() }
        .task(id: dayIndex) { await addWeatherIfPossible() }
    }

    /// El color de la maleta, **siempre**.
    ///
    /// Aquí no se elige color por día: la maleta ya tiene el suyo, y es lo que
    /// la distingue de las demás. Dejar además un color por outfit rompería
    /// esa identidad —cinco días, cinco colores— y obligaría a decidir dos
    /// veces lo mismo.
    private var backdropColor: Color {
        SuitcaseTint.backdrop(for: suitcase.colorRaw)
    }

    @discardableResult
    private func ensureOutfit() -> Outfit {
        outfit ?? createOutfit()
    }

    private func fill(with garments: [Garment]) {
        let target = ensureOutfit()
        for garment in garments {
            let slot = OutfitSlot.slot(for: garment.kind)
            if let existing = target.item(in: slot) {
                existing.garment = garment
                continue
            }
            let item = CanvasItem(transform: slot.transform, garment: garment)
            item.outfit = target
            modelContext.insert(item)
        }
    }

    /// Pega el tiempo del día, si se puede saber.
    ///
    /// **Solo con destino puesto y solo si la fecha cae dentro del
    /// pronóstico.** Un viaje en marzo reservado en enero no tiene tiempo que
    /// enseñar, y poner un icono de sol por rellenar el hueco sería inventar el
    /// dato sobre el que se decide qué meter en la maleta.
    ///
    /// Se pone una vez: si el usuario lo borra, no vuelve.
    private func addWeatherIfPossible() async {
        guard
            let destination = suitcase.destination,
            let date = suitcase.date(forDayIndex: dayIndex),
            let outfit,
            !outfit.items.contains(where: { $0.sticker?.kind == .weather }),
            let snapshot = await appEnvironment.weather.snapshot(for: date, at: destination)
        else { return }

        CanvasEditing.insert(
            sticker: .weather(snapshot),
            size: CGSize(width: 220, height: 250),
            in: outfit,
            context: modelContext
        )
    }

    private func createOutfit() -> Outfit {
        let outfit = Outfit(name: "Día \(dayIndex + 1)")
        outfit.suitcaseDayIndex = dayIndex
        modelContext.insert(outfit)
        outfit.suitcase = suitcase
        return outfit
    }

    private func syncPacking() {
        guard let outfit else { return }
        for item in outfit.items {
            guard let garment = item.garment else { continue }
            SuitcasePacking.ensureEntry(for: garment, in: suitcase, context: modelContext)
        }
    }
}

/// Maleta sin fechas: outfits preparados, sin día.
/// Maleta sin fechas: los outfits preparados, en rejilla.
///
/// **La misma rejilla que en el plan**, no una parecida. Un outfit es un
/// lienzo, se vea donde se vea: enseñarlo aquí como una tarjeta con una tira de
/// miniaturas solapadas y un contador de prendas —que es lo que había— lo
/// convertía en otra cosa según por dónde hubieras entrado, y obligaba a abrir
/// cada uno para saber cuál era cuál.
///
/// Reutiliza `PlannerGridCell` y `NewOutfitGridCell` tal cual. Lo único que no
/// se hereda es "mover a otro día": aquí no hay días, que es precisamente lo
/// que distingue esta maleta de la que sí los tiene.
private struct PreparedOutfits: View {
    let suitcase: Suitcase
    let onEdit: (Outfit) -> Void
    /// Para que el editor crezca **desde la celda tocada**, igual que en el
    /// plan, y no desde el centro de la pantalla.
    let zoom: Namespace.ID

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        ScrollView {
            LazyVGrid(columns: outfitGridColumns, spacing: WK.Spacing.m) {
                ForEach(suitcase.visibleOutfits) { outfit in
                    Button { onEdit(outfit) } label: {
                        // Con el color de la maleta de fondo, no el de la app.
                        // Un lienzo de maleta es de su color siempre, y la
                        // rejilla enseña lo mismo que la página: sin esto, las
                        // celdas salían claras sobre el tinte y el fondo del
                        // lienzo parecía colarse por todas partes.
                        PlannerGridCell(
                            outfit: outfit,
                            store: appEnvironment.imageStore,
                            fallback: SuitcaseTint.backdrop(for: suitcase.colorRaw)
                        )
                    }
                    .buttonStyle(WKPressStyle())
                    .adaptiveZoomSource(id: outfit.stableID, in: zoom)
                    .contextMenu {
                        Button("Duplicar", systemImage: "plus.square.on.square") {
                            duplicate(outfit)
                        }
                        Button("Eliminar", systemImage: "trash", role: .destructive) {
                            withAnimation(WKAnimation.content) {
                                outfit.markDeleted()
                            }
                        }
                    }
                }

                NewOutfitGridCell { onEdit(createOutfit()) }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .safeAreaPadding(.vertical)
            .padding(.bottom, WK.Spacing.xl)
        }
        .scrollIndicators(.hidden)
    }

    private func createOutfit() -> Outfit {
        let outfit = Outfit(name: "Outfit \(suitcase.outfits.count + 1)")
        modelContext.insert(outfit)
        outfit.suitcase = suitcase
        return outfit
    }

    /// Copia el outfit dentro de la misma maleta, con sus prendas y sus
    /// stickers: duplicar uno para cambiarle los zapatos es el caso real, y una
    /// copia vacía no ahorraría nada.
    private func duplicate(_ outfit: Outfit) {
        let copy = Outfit(name: outfit.name.map { "\($0) (copia)" })
        copy.backdropRaw = outfit.backdropRaw
        modelContext.insert(copy)
        copy.suitcase = suitcase

        for item in outfit.items {
            let clone = CanvasItem(transform: item.transform, garment: item.garment)
            if let sticker = item.sticker { clone.apply(sticker) }
            clone.isFlipped = item.isFlipped
            clone.outfit = copy
            modelContext.insert(clone)
        }
    }
}

/// Canvas del outfit, o la invitación a empezar.
struct OutfitCanvasOrEmpty: View {
    let outfit: Outfit?
    let store: ImageStore
    let emptyHint: String

    /// En `@State` y no construida en `body`: creada ahí, cada reevaluación
    /// daría una selección nueva y tocar una prenda se desharía solo.
    @State private var selection = CanvasSelection()

    var body: some View {
        if let outfit, !outfit.visibleItems.isEmpty {
            FreeformCanvas(outfit: outfit, store: store, selection: selection)
        } else {
            ContentUnavailableView {
                Label("Sin outfit", systemImage: "square.dashed")
            } description: {
                Text(emptyHint)
            }
        }
    }
}
