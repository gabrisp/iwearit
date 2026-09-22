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
    /// Con fechas: revista (un día por página) o rejilla (todos los días).
    var layout: PlannerLayout = .book
    @Binding var dayIndex: Int
    /// Para que el editor crezca desde la celda tocada en la rejilla.
    let zoom: Namespace.ID
    /// Pide a la pantalla que **empuje** el editor.
    ///
    /// La página no puede navegar por su cuenta: vive en su propio
    /// `UIHostingController` dentro del pager, fuera de la pila. Por eso lo
    /// pide hacia arriba en vez de presentarlo a pantalla completa.
    /// Desde la rejilla: ir a ese día en modo revista.
    var onOpenDay: (Int) -> Void = { _ in }
    let onEdit: (Outfit, Bool) -> Void

    var body: some View {
        if let dayCount = suitcase.tripDayCount, layout == .grid {
            DatedGrid(suitcase: suitcase, dayCount: dayCount, onOpenDay: onOpenDay, onEdit: onEdit)
        } else if let dayCount = suitcase.tripDayCount {
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
    let onEdit: (Outfit, Bool) -> Void

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

/// Maleta con fechas, en rejilla: todos los días del viaje de un vistazo.
///
/// La misma celda que la rejilla del plan. Un día sin outfit es la celda de
/// crear, y lleva a ese día en modo revista.
private struct DatedGrid: View {
    let suitcase: Suitcase
    let dayCount: Int
    let onOpenDay: (Int) -> Void
    let onEdit: (Outfit, Bool) -> Void

    @Environment(AppEnvironment.self) private var appEnvironment

    /// Lo que mide la barra de arriba. Ver `body`.
    @State private var safeTop: CGFloat = 0

    private static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()

    var body: some View {
        ZStack {
        ScrollView {
            LazyVGrid(columns: outfitGridColumns, spacing: WK.Spacing.m) {
                ForEach(0..<dayCount, id: \.self) { index in
                    VStack(alignment: .leading, spacing: WK.Spacing.xs) {
                        Text(label(for: index))
                            .font(WK.Font.captionMedium)
                            .foregroundStyle(WK.Palette.secondaryText)
                        if let outfit = suitcase.outfit(forDayIndex: index) {
                            Button { onEdit(outfit, false) } label: {
                                PlannerGridCell(
                                    outfit: outfit,
                                    store: appEnvironment.imageStore,
                                    fallback: SuitcaseTint.backdrop(for: suitcase.colorRaw)
                                )
                            }
                            .buttonStyle(WKPressStyle())
                        } else {
                            NewOutfitGridCell { onOpenDay(index) }
                        }
                    }
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            // Como la rejilla del plan: el scroll **ignora el área segura** y
            // el hueco lo pone el contenido por dentro, más un respiro arriba
            // y el sitio de la barra de abajo.
            // `safeAreaPadding` no se entera con el scroll ignorando el área
            // segura: la barra se mide fuera, como en el plan.
            .padding(.top, safeTop + WK.Spacing.l)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.always, axes: .vertical)
        .ignoresSafeArea(edges: [.top, .bottom])
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { measured in
            guard measured > 0, abs(measured - safeTop) > 0.5 else { return }
            safeTop = measured
        }
    }

    private func label(for index: Int) -> String {
        guard let date = suitcase.date(forDayIndex: index) else { return "Día \(index + 1)" }
        return "Día \(index + 1) · \(Self.date.string(from: date))"
    }
}

/// Tira de días del viaje. Acotada al viaje, no infinita como la del
/// planificador: una maleta dura lo que dura, y dejar deslizar más allá del
/// último día ofrece planificar algo que no existe.
struct TripDayBar: View {
    let suitcase: Suitcase
    let dayCount: Int
    @Binding var selected: Int
    /// Dentro de la barra de navegación: más baja y sin su propio cristal,
    /// que ya lo pone la barra.
    var isCompact = false

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.xs) {
                ForEach(0..<dayCount, id: \.self) { index in
                    TripDayChip(
                        index: index,
                        date: suitcase.date(forDayIndex: index),
                        isSelected: index == selected,
                        hasOutfit: suitcase.outfit(forDayIndex: index) != nil,
                        // Dentro de la barra, **sin alto puesto a mano**: lo
                        // da la barra. Fuera, el de siempre.
                        height: isCompact ? nil : 46
                    )
                    .onTapGesture { selected = index }
                }
            }
            .padding(.horizontal, WK.Spacing.s)
        }
        .scrollIndicators(.hidden)
        .modifier(TripDayBarHeight(height: isCompact ? nil : 56))
        .clipShape(.capsule)
        .modifier(TripDayBarChrome(isCompact: isCompact))
    }
}

/// El alto de la tira, **solo fuera** de la barra: dentro lo pone la barra.
private struct TripDayBarHeight: ViewModifier {
    let height: CGFloat?

    func body(content: Content) -> some View {
        if let height {
            content.frame(height: height)
        } else {
            content
        }
    }
}

/// El cristal de la tira, y el margen solo fuera de la barra de navegación.
private struct TripDayBarChrome: ViewModifier {
    let isCompact: Bool

    func body(content: Content) -> some View {
        if isCompact {
            // En el centro de la barra el sistema **no** pone cristal a una
            // vista propia: sin el suyo, los días flotaban sobre los puntos.
            content.adaptiveGlassInteractive(in: .capsule)
        } else {
            content
                .adaptiveGlassInteractive(in: .capsule)
                .padding(.horizontal, WK.Spacing.m)
        }
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
    /// `nil` = el que salga. Ver `TripDayBarHeight`.
    var height: CGFloat? = 46

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
        HStack(spacing: 6) {
        VStack(spacing: -1) {
            Text(date.map { Self.dayNumber.string(from: $0) } ?? "\(index + 1)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(
                    isSelected ? WK.Palette.onAccent.opacity(0.75) : WK.Palette.secondaryText
                )

            Text(date.map { Self.month.string(from: $0).uppercased() } ?? "DÍA")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isSelected ? WK.Palette.onAccent : WK.Palette.primaryText)

            // Un punto si ese día ya tiene outfit. Ahora es una píldora a la
            // derecha: ver abajo.
            // Circle()
            //     .fill(isSelected ? WK.Palette.onAccent : WK.Palette.accent)
            //     .frame(width: 5, height: 5)
            //     .opacity(hasOutfit ? 1 : 0)
            //     .padding(.top, 2)
        }
            // **Una píldora a la derecha**, no un punto debajo: se ve de un
            // vistazo qué días ya tienen outfit sin abrirlos.
            if hasOutfit {
                Capsule()
                    .fill(isSelected ? WK.Palette.onAccent : WK.Palette.accent)
                    .frame(width: 4, height: 18)
            }
        }
        .padding(.horizontal, WK.Spacing.m)
        .padding(.vertical, height == nil ? 4 : 0)
        .modifier(TripDayBarHeight(height: height))
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
    let onEdit: (Outfit, Bool) -> Void

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
                    .onTapGesture(count: 2) { onEdit(ensureOutfit(), outfit == nil) }
                    .onLongPressGesture(minimumDuration: 0.4) { onEdit(ensureOutfit(), outfit == nil) }
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
            DayActionButton(symbol: "pencil") { onEdit(ensureOutfit(), outfit == nil) }
            .padding(.horizontal, WK.Spacing.screenInset)
            // Por encima de la barra de Outfits · Equipaje: el pager ignora el
            // área segura, así que aquí se cuenta a mano.
            // .padding(.bottom, WK.Spacing.xl)
            .padding(.bottom, WK.Spacing.xl + WKLocktyTabBarMetrics.height + WK.Spacing.l)
        }
        .sheet(isPresented: $isPickingGarments) {
            OutfitPickerSheet(store: appEnvironment.imageStore) { picked in
                fill(with: picked)
                onEdit(ensureOutfit(), outfit == nil)
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
    let onEdit: (Outfit, Bool) -> Void
    /// Para que el editor crezca **desde la celda tocada**, igual que en el
    /// plan, y no desde el centro de la pantalla.
    let zoom: Namespace.ID

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    /// El selector, abierto por el "+".
    @State private var isPickingForNew = false
    /// Lo que mide la barra de arriba. Ver `DatedGrid`.
    @State private var safeTop: CGFloat = 0

    var body: some View {
        ZStack {
        ScrollView {
            LazyVGrid(columns: outfitGridColumns, spacing: WK.Spacing.m) {
                ForEach(suitcase.visibleOutfits) { outfit in
                    Button { onEdit(outfit, false) } label: {
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

                // **Elige prendas primero.** Abría el editor con un lienzo
                // vacío, así que tocar la celda sin querer dejaba un outfit en
                // blanco en la maleta. Igual que en el plan.
                NewOutfitGridCell { isPickingForNew = true }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            // Igual que la rejilla del plan: ver `DatedGrid`.
            // `safeAreaPadding` no se entera con el scroll ignorando el área
            // segura: la barra se mide fuera, como en el plan.
            .padding(.top, safeTop + WK.Spacing.l)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.always, axes: .vertical)
        .ignoresSafeArea(edges: [.top, .bottom])
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { measured in
            guard measured > 0, abs(measured - safeTop) > 0.5 else { return }
            safeTop = measured
        }
        // Sin sobre-scroll: es una rejilla, y la celda de crear ya se ve. Ver
        // `PlannerGrid`.
        .sheet(isPresented: $isPickingForNew) {
            OutfitPickerSheet(store: appEnvironment.imageStore) { picked in
                guard !picked.isEmpty else { return }
                onEdit(createOutfit(with: picked), true)
            }
        }
    }

    /// Un outfit nuevo de la maleta, con las prendas elegidas ya colocadas.
    private func createOutfit(with garments: [Garment]) -> Outfit {
        let outfit = createOutfit()
        for garment in garments {
            let slot = OutfitSlot.slot(for: garment.kind)
            let item = CanvasItem(transform: slot.transform, garment: garment)
            item.outfit = outfit
            modelContext.insert(item)
        }
        return outfit
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
