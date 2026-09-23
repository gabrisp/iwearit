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
        if suitcase.tripDayCount != nil, layout == .grid {
            DatedGrid(suitcase: suitcase, dayIndex: dayIndex, onEdit: onEdit)
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

/// Lo que hay que dejar libre arriba: el área segura de la ventana más la
/// barra de navegación.
///
/// De la ventana y no medido con `onGeometryChange`: la pantalla entera ignora
/// el área segura —el papel de puntos llega a los bordes—, así que dentro ya no
/// queda ninguna vista que la conozca y medirla ahí daba cero.
@MainActor
var suitcaseTopInset: CGFloat {
    let window = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first { $0.isKeyWindow }
    return (window?.safeAreaInsets.top ?? 59) + 52
}

/// Y lo que hay que dejar libre abajo: el área segura, la barra de Outfits ·
/// Equipaje y un respiro. Ver `suitcaseTopInset`.
@MainActor
private var suitcaseBottomInset: CGFloat {
    let window = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first { $0.isKeyWindow }
    return (window?.safeAreaInsets.bottom ?? 34) + WKLocktyTabBarMetrics.height + WK.Spacing.xl
}

/// El día del viaje **en rejilla**: sus outfits, todos.
///
/// Un día de maleta es un día del calendario: puede llevar varios outfits —el
/// de la cena y el del avión— y la revista solo enseña uno. Es la misma
/// rejilla que en el plan, con la celda de crear al final.
private struct DatedGrid: View {
    let suitcase: Suitcase
    let dayIndex: Int
    let onEdit: (Outfit, Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var isPickingForNew = false

    /// Los de **ese** día.
    private var outfits: [Outfit] {
        suitcase.visibleOutfits.filter { $0.suitcaseDayIndex == dayIndex }
    }

    var body: some View {
        ZStack {
        ScrollView {
            LazyVGrid(columns: outfitGridColumns, spacing: WK.Spacing.m) {
                ForEach(outfits) { outfit in
                    Button { onEdit(outfit, false) } label: {
                        PlannerGridCell(
                            outfit: outfit,
                            store: appEnvironment.imageStore,
                            fallback: SuitcaseTint.backdrop(for: suitcase.colorRaw)
                        )
                    }
                    .buttonStyle(WKPressStyle())
                    .contextMenu {
                        Button("Duplicar", systemImage: "plus.square.on.square") {
                            duplicate(outfit)
                        }
                        Button("Eliminar", systemImage: "trash", role: .destructive) {
                            withAnimation(WKAnimation.content) { outfit.markDeleted() }
                        }
                    }
                }

                NewOutfitGridCell { isPickingForNew = true }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            // Como la rejilla del plan: el scroll **ignora el área segura** y
            // el hueco lo pone el contenido por dentro.
            .padding(.top, suitcaseTopInset + WK.Spacing.l)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.always, axes: .vertical)
        .ignoresSafeArea(edges: [.top, .bottom])
        }
        .sheet(isPresented: $isPickingForNew) {
            OutfitPickerSheet(store: appEnvironment.imageStore) { picked in
                guard !picked.isEmpty else { return }
                onEdit(createOutfit(with: picked), true)
            }
        }
    }

    /// Un outfit más para ese día, con las prendas elegidas ya colocadas.
    private func createOutfit(with garments: [Garment]) -> Outfit {
        let outfit = Outfit(name: "Día \(dayIndex + 1)")
        outfit.suitcaseDayIndex = dayIndex
        modelContext.insert(outfit)
        outfit.suitcase = suitcase
        for garment in garments {
            let slot = OutfitSlot.slot(for: garment.kind)
            let item = CanvasItem(transform: slot.transform, garment: garment)
            item.outfit = outfit
            modelContext.insert(item)
        }
        return outfit
    }

    private func duplicate(_ outfit: Outfit) {
        let copy = Outfit(name: outfit.name.map { "\($0) (copia)" })
        copy.backdropRaw = outfit.backdropRaw
        copy.suitcaseDayIndex = outfit.suitcaseDayIndex
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
                        isCompact: isCompact
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
    /// Dentro de la barra: una sola línea y del alto de un botón.
    var isCompact = false

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
        // En la barra, **en una línea**: dos pisos de texto hacen la tira más
        // alta que un botón y la barra crece con ella.
        AnyLayout(isCompact ? AnyLayout(HStackLayout(spacing: 4)) : AnyLayout(VStackLayout(spacing: -1))) {
            Text(date.map { Self.dayNumber.string(from: $0) } ?? "\(index + 1)")
                .font(.system(size: isCompact ? 13 : 11, weight: isCompact ? .semibold : .medium))
                .foregroundStyle(
                    isSelected ? WK.Palette.onAccent.opacity(0.75) : WK.Palette.secondaryText
                )

            Text(date.map { Self.month.string(from: $0).uppercased() } ?? "DÍA")
                .font(.system(size: isCompact ? 12 : 15, weight: .bold))
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
                    .frame(width: 4, height: isCompact ? 12 : 18)
            }
        }
        .padding(.horizontal, isCompact ? WK.Spacing.s : WK.Spacing.m)
        // **El alto sale del relleno, no de un número.** En la barra,
        // `maxHeight: .infinity` no estira nada —cada pieza recibe su alto
        // ideal—, así que lo que iguala la tira con los botones es darle a
        // cada día el mismo aire que lleva la etiqueta de un botón.
        .padding(.vertical, isCompact ? 12 : 0)
        .modifier(TripDayBarHeight(height: isCompact ? nil : 46))
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
    /// El selector abierto por el tirón del final.
    @State private var isPickingForNew = false

    /// **Todos los del día**, no uno. Ver `DatedGrid`: un día de maleta es un
    /// día del calendario y admite varios looks.
    private var outfits: [Outfit] {
        suitcase.visibleOutfits.filter { $0.suitcaseDayIndex == dayIndex }
    }

    var body: some View {
        // **Lo mismo que un día del plan**: los lienzos del día, en vertical y
        // paginados, y seguir tirando al final crea otro. Ver `DayPage`.
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(outfits) { outfit in
                    TripDayCanvas(suitcase: suitcase, outfit: outfit, onEdit: onEdit)
                        .containerRelativeFrame(.vertical)
                        .id(outfit.persistentModelID)
                }

                // El hueco **solo con el día vacío**: teniendo ya algo, el
                // siguiente se crea tirando.
                if outfits.isEmpty {
                    TripDayCanvas(suitcase: suitcase, outfit: nil, onEdit: onEdit) {
                        isPickingGarments = true
                    }
                    .containerRelativeFrame(.vertical)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        // Rebota aunque no haya nada que desplazar: si no, el gesto no existe
        // justo el día que aún no tiene nada.
        .scrollBounceBehavior(.always, axes: .vertical)
        .overscrollAction(
            threshold: 84,
            symbol: "plus",
            label: "Crear nuevo outfit",
            // **Más alto que en el plan.** Aquí debajo hay dos cosas: la barra
            // de Outfits · Equipaje y el lápiz del lienzo, y pegado al borde
            // el botón caía justo encima de los dos.
            bottomInset: suitcaseBottomInset
        ) {
            isPickingForNew = true
        }
        .sheet(isPresented: $isPickingForNew) {
            OutfitPickerSheet(store: appEnvironment.imageStore) { picked in
                guard !picked.isEmpty else { return }
                onEdit(createOutfit(with: picked), true)
            }
        }
        .sheet(isPresented: $isPickingGarments) {
            OutfitPickerSheet(store: appEnvironment.imageStore) { picked in
                guard !picked.isEmpty else { return }
                onEdit(createOutfit(with: picked), true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backdropColor)
        // Lo que se meta en un outfit del viaje entra solo en el checklist:
        // preparar el look y hacer la maleta son la misma tarea.
        .onChange(of: outfits.reduce(0) { $0 + $1.items.count }) { syncPacking() }
        // **El sticker del tiempo lo pone el usuario.** Se ponía solo al abrir
        // el día del viaje, y aparecía en el lienzo sin que nadie lo hubiera
        // pedido: un elemento que hay que mover o borrar y que además se
        // colaba en el historial del editor como si lo hubieras puesto tú.
        // Está a un toque en la bandeja de stickers, que es donde se ponen las
        // cosas en un lienzo.
        //
        // .task(id: dayIndex) { await addWeatherIfPossible() }
    }

    /// Un outfit más para este día, con las prendas elegidas colocadas.
    private func createOutfit(with garments: [Garment]) -> Outfit {
        let outfit = createOutfit()
        for garment in garments {
            let slot = OutfitSlot.slot(for: garment.kind)
            if let existing = outfit.item(in: slot) {
                existing.garment = garment
                continue
            }
            let item = CanvasItem(transform: slot.transform, garment: garment)
            item.outfit = outfit
            modelContext.insert(item)
        }
        return outfit
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

    // Lo que había cuando un día tenía **un** outfit: asegurarlo y
    // rellenarlo. Ahora cada lienzo es un outfit y se crean con
    // `createOutfit(with:)`.
    //
    // @discardableResult
    // private func ensureOutfit() -> Outfit {
    //     outfit ?? createOutfit()
    // }

    // private func fill(with garments: [Garment]) {
    //     let target = ensureOutfit()
    //     for garment in garments {
    //         let slot = OutfitSlot.slot(for: garment.kind)
    //         if let existing = target.item(in: slot) {
    //             existing.garment = garment
    //             continue
    //         }
    //         let item = CanvasItem(transform: slot.transform, garment: garment)
    //         item.outfit = target
    //         modelContext.insert(item)
    //     }
    // }

    /// Pega el tiempo del día, si se puede saber. **Sin usar**: se conserva
    /// porque el cálculo —destino, fecha dentro del pronóstico— es el mismo
    /// que hará falta el día que el sticker se ofrezca desde la bandeja del
    /// viaje. Ver arriba por qué ya no se llama sola.
    ///
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
            let outfit = outfits.first,
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
        for item in outfits.flatMap(\.items) {
            guard let garment = item.garment else { continue }
            SuitcasePacking.ensureEntry(for: garment, in: suitcase, context: modelContext)
        }
    }
}

/// Un lienzo del día: el outfit, o la invitación a empezar.
///
/// Los gestos, **los mismos que en el plan**: doble toque y mantener pulsado
/// abren el editor. Un toque simple no puede ser, porque compite con el paso
/// de página.
private struct TripDayCanvas: View {
    let suitcase: Suitcase
    let outfit: Outfit?
    let onEdit: (Outfit, Bool) -> Void
    var onEmptyTap: (() -> Void)?

    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var selection = CanvasSelection()

    var body: some View {
        ZStack {
            DotGridBackground().allowsHitTesting(false)

            if let outfit, !outfit.visibleItems.isEmpty {
                FreeformCanvas(outfit: outfit, store: appEnvironment.imageStore, selection: selection)
                    .allowsHitTesting(false)
                    // **Sin doble toque ni pulsación larga para editar.**
                    //
                    // Cada lienzo tiene ya su lápiz, que es un botón que se ve.
                    // Los dos gestos estaban para quien los conociera, y a
                    // cambio hacían que tocar dos veces sin querer —o apoyar el
                    // dedo mientras pasas— te sacara de donde estabas. Se
                    // quedan comentados: revivirlos es quitar dos barras.
                    // .onTapGesture(count: 2) { onEdit(outfit, false) }
                    // .onLongPressGesture(minimumDuration: 0.4) { onEdit(outfit, false) }
                    // En todo el lienzo: sin esto el gesto solo existe donde
                    // hay una prenda pintada, y el hueco entre ellas —que es
                    // casi todo— no respondería.
                    .contentShape(.rect)
            } else if let date = suitcase.date(forDayIndex: outfit?.suitcaseDayIndex ?? 0) {
                EmptyDayPrompt(date: date) { onEmptyTap?() }
            }
        }
        // **Sin botón suelto sobre el lienzo.** Estorbaba al lado de la barra
        // de Outfits · Equipaje y decía lo que ya dicen el doble toque y el
        // mantener pulsado. Añadir un outfit está en el "+" de la barra.
        //
        // .overlay(alignment: .bottomTrailing) {
        //     if let outfit {
        //         DayActionButton(symbol: "pencil") { onEdit(outfit, false) }
        //             .padding(.horizontal, WK.Spacing.screenInset)
        //             .padding(.bottom, WK.Spacing.xl + WKLocktyTabBarMetrics.height + WK.Spacing.l)
        //     }
        // }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .padding(.top, suitcaseTopInset + WK.Spacing.l)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.always, axes: .vertical)
        .ignoresSafeArea(edges: [.top, .bottom])
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
