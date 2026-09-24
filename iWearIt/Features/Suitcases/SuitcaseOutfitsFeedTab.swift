import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// Los outfits de la maleta, **como el plan**: un lienzo por pantalla, los días
/// de lado y la tarjeta de crear al final.
///
/// ## Por qué el mismo gesto que en el plan
///
/// Porque es lo mismo: días con ropa asignada. Que la maleta se hojeara de una
/// manera y el plan de otra obligaba a aprender dos veces lo mismo, y encima la
/// de la maleta era la rara —paso de página con curl— justo en la pantalla
/// donde menos falta hace.
///
/// - Note: la pestaña vieja (`SuitcaseOutfitsTab`) **no se ha borrado**: sigue
///   en el repositorio con su revista, su rejilla con fechas y su lista de
///   preparados. Volver es cambiar una línea en `SuitcaseDetailScreen`.
struct SuitcaseOutfitsFeedTab: View {
    let suitcase: Suitcase
    @Binding var dayIndex: Int
    /// Revista o rejilla. La pestaña lo lee **y lo escribe**: el botón de
    /// cambiar vive aquí, en la misma tira que los días, exactamente como en
    /// el plan. En la barra de navegación estaba atado a que el viaje tuviera
    /// fechas —iba dentro del mismo `if` que la tira—, así que en una maleta
    /// sin fechas no había forma de ver la rejilla.
    @Binding var layout: PlannerLayout
    /// Sin uso desde que la maleta respeta el área segura: se pasa a cero.
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    let onEdit: (Outfit, Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var pageSize: CGSize = .zero
    /// Una sola hoja, como en el plan: dos en la misma vista dejan muda a
    /// una. Ver `PlanFeedScreen.Sheet`.
    @State private var sheet: Sheet?
    /// El que espera el sí para irse.
    @State private var deleting: Outfit?

    enum Sheet: Identifiable {
        case move(Outfit)
        case picker
        case tryOn(Outfit)

        var id: String {
            switch self {
            case let .move(outfit): "move-\(outfit.stableID)"
            case .picker: "picker"
            case let .tryOn(outfit): "tryon-\(outfit.stableID)"
            }
        }
    }
    @State private var page: Int?

    @Namespace private var morph

    /// Los días del viaje. Sin fechas, un solo hueco: lo preparado.
    /// Las páginas: los días del viaje **y una más, la de sin día**.
    ///
    /// Lo que se mete sin fecha —desde la inspiración, o moviéndolo a "sin
    /// día"— no salía en ninguna página: no era de ningún día, así que no
    /// estaba. Ahora tiene la suya, la última. Sin fechas, todo es "sin día" y
    /// basta una.
    private var dayCount: Int {
        guard let days = suitcase.tripDayCount else { return 1 }
        return days + 1
    }

    /// **El mismo hueco que en el plan.** La maleta respeta el área segura, así
    /// que el scroll llega ya recortado por sus barras y su alto es lo que se
    /// ve. (Antes la ignoraba y aquí se restaban las barras a mano; esas
    /// cuentas nunca cuadraron con las del plan.)
    private var stride: CGFloat {
        // **Lo mismo que el plan, porque ahora es lo mismo que el plan.** Con
        // el área segura respetada, el scroll ya llega recortado por la tira
        // de arriba y la barra de abajo: su alto es lo que se ve.
        max(320, pageSize.height)
    }

    /// Lo que mide la tira con su aire, igual que en el plan.
    private static let stripHeight: CGFloat = 64

    /// La tira: los días del viaje —si los hay— y el cambio de modo.
    ///
    /// El botón está **siempre**, con fechas y sin ellas: la rejilla sirve
    /// igual para ver de un vistazo lo que llevas preparado.
    private var strip: some View {
        HStack(spacing: WK.Spacing.s) {
            // **Volver, aquí.** La barra de navegación de la maleta se
            // esconde en esta pestaña: dejaba dos franjas arriba —la suya y
            // la tira— en una pantalla cuyo papel llega a los cuatro bordes.
            // El gesto de volver sigue estando; esto es para el dedo que
            // prefiere un botón.
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WK.Palette.primaryText)
                    .frame(width: 56, height: 56)
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())
            .adaptiveGlassInteractive(in: .circle)
            .padding(.leading, WK.Spacing.m)

            if let dayCount = suitcase.tripDayCount {
                // **La misma cápsula que el plan**, con los mismos chips: el
                // día de la semana arriba y el número debajo. La de antes
                // (`TripDayBar`) era otra pieza —"3 OCT" con una raya al
                // lado— y en una fila de tres días se cortaba el tercero.
                TripDayCapsule(suitcase: suitcase, dayCount: dayCount, selected: $dayIndex)
            } else {
                Spacer(minLength: 0)
            }

            Button {
                withAnimation(WKAnimation.content) { layout = layout.next }
            } label: {
                // Los mismos símbolos que el botón del plan: el de la maleta
                // decía "libro" para la revista, que es otro nombre para lo
                // mismo y otro dibujo en el mismo sitio.
                Image(systemName: layout == .book ? "square.grid.2x2" : "rectangle.portrait")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WK.Palette.primaryText)
                    .frame(width: 56, height: 56)
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())
            .adaptiveGlassInteractive(in: .circle)
            .padding(.trailing, WK.Spacing.m)
        }
        .frame(height: Self.stripHeight)
        // Sin uso: los días y el modo van ahora en la barra de navegación de
        // la maleta (`SuitcaseDetailScreen`). Se queda por si vuelve a flotar.
    }

    /// La fecha de una página, **si es un día del viaje**.
    ///
    /// La última página es la de sin día, y no tiene fecha: pedírsela al viaje
    /// devolvía el día siguiente al último —el 7 de un viaje que acaba el 6—
    /// y la tarjeta de crear lo enseñaba en su taco.
    private func tripDate(of index: Int) -> Date? {
        guard let days = suitcase.tripDayCount, index < days else { return nil }
        return suitcase.date(forDayIndex: index)
    }

    private func outfits(ofDay index: Int) -> [Outfit] {
        let all = suitcase.visibleOutfits.filter { !$0.garments.isEmpty }
        guard let days = suitcase.tripDayCount else { return all }
        // La última página es la de sin día: lo que no tiene día, o tiene uno
        // que ya no existe porque el viaje se acortó.
        if index == days {
            return all.filter { outfit in
                guard let day = outfit.suitcaseDayIndex else { return true }
                return day < 0 || day >= days
            }
        }
        return all.filter { $0.suitcaseDayIndex == index }
    }

    var body: some View {
        pager
            .background(WK.Palette.canvas.ignoresSafeArea())
            // **La tira, aquí y como en el plan.** Una barra de área segura
            // que reserva su sitio: así el scroll de debajo sabe lo que tiene
            // encima y las dos pantallas se miran igual.
            // La tira ya no va aquí: los días y el cambio de modo están en la
            // barra de navegación de la maleta, con su botón de volver. Ver
            // `SuitcaseDetailScreen`.
            // .adaptiveSafeAreaBar(edge: .top, spacing: 0) { strip }
            .sheet(item: $sheet) { which in
                switch which {
                case let .move(outfit):
                    SuitcaseDayPicker(suitcase: suitcase) { index in
                        // `nil` lo devuelve a preparados, que es un sitio: el
                        // que tienen los outfits de un viaje sin fecha.
                        outfit.suitcaseDayIndex = index
                        try? modelContext.save()
                        sheet = nil
                    }
                case .picker:
                    OutfitPickerSheet(store: appEnvironment.imageStore) { picked in
                        guard !picked.isEmpty else { return }
                        create(with: picked)
                    }
                case let .tryOn(outfit):
                    TryOnSheet(outfit: outfit)
                        .presentationBackground(WK.Palette.canvas)
                }
            }
            .alert(
                String(localized: "suitcases.suitcaseoutfitsfeedtab.removeThisOutfit", defaultValue: "Remove this outfit?"),
                isPresented: Binding(
                    get: { deleting != nil },
                    set: { if !$0 { deleting = nil } }
                ),
                presenting: deleting
            ) { outfit in
                Button(String(localized: "common.remove", defaultValue: "Remove"), role: .destructive) {
                    withAnimation(WKAnimation.content) { outfit.markDeleted() }
                    deleting = nil
                }
                Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) { deleting = nil }
            } message: { _ in
                Text(String(localized: "suitcases.suitcaseoutfitsfeedtab.theClothesStayInYour", defaultValue: "The clothes stay in your closet."))
            }
            .onChange(of: page) { _, value in
                if let value { dayIndex = value }
            }
            .onChange(of: dayIndex) { _, value in
                if page != value { page = value }
            }
            .task { page = dayIndex }
            .animation(WKAnimation.content, value: layout)
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(0..<dayCount, id: \.self) { index in
                    Group {
                        switch layout {
                        case .book: feed(ofDay: index)
                        case .grid: grid(ofDay: index)
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
    }

    private func feed(ofDay index: Int) -> some View {
        // Con su propio scroll, como en el plan: el sitio por donde va es del
        // día, no de la pestaña. Ver `PlanDayFeed`.
        SuitcaseDayFeed(
            outfits: outfits(ofDay: index),
            day: tripDate(of: index),
            suitcase: suitcase,
            store: appEnvironment.imageStore,
            pageSize: pageSize,
            stride: stride,
            morph: morph,
            createID: "create-\(index)",
            isPicking: sheet != nil,
            onEdit: { onEdit($0, false) },
            onMove: { sheet = .move($0) },
            onTryOn: { sheet = .tryOn($0) },
            onDelete: { deleting = $0 },
            onCreate: { sheet = .picker }
        )
    }

    private func grid(ofDay index: Int) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: WK.Spacing.m)],
                spacing: WK.Spacing.m
            ) {
                ForEach(outfits(ofDay: index), id: \.stableID) { outfit in
                    SuitcaseGridCell(
                        outfit: outfit,
                        suitcase: suitcase,
                        store: appEnvironment.imageStore,
                        canMove: suitcase.tripDayCount != nil,
                        onEdit: { onEdit(outfit, false) },
                        onMove: { sheet = .move(outfit) },
                        onDuplicate: { duplicate(outfit) },
                        onTryOn: { sheet = .tryOn(outfit) },
                        onDelete: { deleting = outfit }
                    )
                    .matchedGeometryEffect(id: outfit.stableID, in: morph)
                    // El mismo menú que en la rejilla del plan: aquí se ven
                    // varios a la vez y es cuando apetece copiar uno o
                    // cambiarlo de día.
                    .contextMenu {
                        Button(String(localized: "common.edit", defaultValue: "Edit"), systemImage: "pencil") { onEdit(outfit, false) }
                        Button(String(localized: "common.tryItOn", defaultValue: "Try it on"), systemImage: "person.crop.rectangle") {
                            sheet = .tryOn(outfit)
                        }
                        Button(String(localized: "common.duplicate", defaultValue: "Duplicate"), systemImage: "plus.square.on.square") {
                            duplicate(outfit)
                        }
                        if suitcase.tripDayCount != nil {
                            Button(String(localized: "common.moveToAnotherDay", defaultValue: "Move to another day"), systemImage: "calendar") {
                                sheet = .move(outfit)
                            }
                        }
                        Button(String(localized: "common.remove", defaultValue: "Remove"), systemImage: "trash", role: .destructive) {
                            deleting = outfit
                        }
                    }
                }

                PlanCreateCard(date: tripDate(of: index))
                    .matchedGeometryEffect(id: "create-\(index)", in: morph)
                    .aspectRatio(CanvasSpace.width / CanvasSpace.height, contentMode: .fit)
                    .onTapGesture { sheet = .picker }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            // El mismo aire que la rejilla del plan: el de la tarjeta grande
            // más seis. Ver `PlanFeedScreen.grid(of:)`.
            .padding(.top, PlanCardSize.inset(stride: stride) + 6)
        }
        .scrollIndicators(.hidden)
    }

    /// Copiar uno para variarlo. Se queda en la misma maleta y en el mismo
    /// día del viaje, que es de donde sale.
    private func duplicate(_ outfit: Outfit) {
        let copy = Outfit(name: outfit.name)
        copy.backdropRaw = outfit.backdropRaw
        modelContext.insert(copy)
        copy.suitcase = suitcase
        copy.suitcaseDayIndex = outfit.suitcaseDayIndex

        for item in outfit.visibleItems {
            let clone = CanvasItem(transform: item.transform, garment: item.garment)
            if let sticker = item.sticker { clone.apply(sticker) }
            clone.isFlipped = item.isFlipped
            clone.outfit = copy
            modelContext.insert(clone)
        }
        try? modelContext.save()
    }

    private func create(with garments: [Garment]) {
        // Sin origen: `inspo` es para lo que propuso el estilista, y esto lo
        // has montado tú eligiendo prendas.
        let outfit = OutfitAssembly.make(
            from: garments,
            name: nil,
            origin: nil,
            isFavorite: false,
            backdropRaw: nil,
            context: modelContext
        )
        outfit.suitcase = suitcase
        // En la página de sin día, sin día.
        if let days = suitcase.tripDayCount {
            let current = page ?? dayIndex
            outfit.suitcaseDayIndex = current < days ? current : nil
        }
        try? modelContext.save()
        onEdit(outfit, true)
    }
}

/// Los outfits de un día del viaje, uno por pantalla.
private struct SuitcaseDayFeed: View {
    let outfits: [Outfit]
    /// Qué día del viaje es, si el viaje tiene fechas. Para el taco de la
    /// tarjeta vacía, como en el plan.
    let day: Date?
    let suitcase: Suitcase
    let store: ImageStore
    let pageSize: CGSize
    /// Lo que mide un hueco de verdad: la pantalla menos lo que tapan las
    /// barras de la maleta. Ver `SuitcaseOutfitsFeedTab.stride`.
    let stride: CGFloat
    let morph: Namespace.ID
    let createID: String
    let isPicking: Bool
    let onEdit: (Outfit) -> Void
    let onMove: (Outfit) -> Void
    let onTryOn: (Outfit) -> Void
    let onDelete: (Outfit) -> Void
    let onCreate: () -> Void

    @State private var anchor: AnyHashable?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(outfits, id: \.stableID) { outfit in
                    SuitcaseFeedCard(
                        outfit: outfit,
                        suitcase: suitcase,
                        store: store,
                        onEdit: { onEdit(outfit) },
                        onMove: { onMove(outfit) },
                        onTryOn: { onTryOn(outfit) },
                        onDelete: { onDelete(outfit) }
                    )
                    .matchedGeometryEffect(id: outfit.stableID, in: morph)
                    .modifier(PlanCardSize(page: pageSize, stride: stride))
                    .id(AnyHashable(outfit.stableID))
                }

                // Solo con el día vacío: ver `PlanDayFeed`.
                if outfits.isEmpty {
                    PlanCreateCard(date: day)
                        .matchedGeometryEffect(id: createID, in: morph)
                        .modifier(PlanCardSize(page: pageSize, stride: stride))
                        .onTapGesture { onCreate() }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $anchor, anchor: .center)
        .scrollIndicators(.hidden)
        // Y con outfits, el tirón del final. El mismo que el plan.
        .modifier(
            CreateOnOverscroll(isOn: !outfits.isEmpty && !isPicking, action: onCreate)
        )
    }
}

/// Un outfit de la maleta. Las mismas dos acciones que en el plan: el lápiz y
/// mover. Ni corazón ni calendario — aquí el día es el del viaje, y para eso
/// está mover.
private struct SuitcaseFeedCard: View {
    let outfit: Outfit
    let suitcase: Suitcase
    let store: ImageStore
    /// Sin uso desde que la rejilla tiene su propia celda con menú —ver
    /// `SuitcaseGridCell`—, pero el parámetro se queda: la tarjeta sabe
    /// encogerse y volver a usarla en una rejilla es pasarle `true`.
    var isCompact = false
    let onEdit: () -> Void
    let onMove: () -> Void
    let onTryOn: () -> Void
    let onDelete: () -> Void

    var body: some View {
        LookCanvasView(
            garments: outfit.garments,
            store: store,
            backdrop: backdrop,
            outfit: outfit,
            showsBorder: true,
            // Ver `PlanFeedCard`: encima de la ropa, el gesto es de la prenda.
            onDoubleTap: onEdit
        )
        .overlay(alignment: .topTrailing) {
            // Los mismos tres que en el plan: abrir, cambiar de día y quitar.
            VStack(spacing: WK.Spacing.xs) {
                WKCircleButton("pencil", size: .compact, action: onEdit)
                    .tint(WK.Palette.primaryText)
                if suitcase.tripDayCount != nil {
                    WKCircleButton(
                        "arrow.up.and.down.and.arrow.left.and.right",
                        size: .compact,
                        action: onMove
                    )
                    .tint(WK.Palette.primaryText)
                }
                WKCircleButton("person.crop.rectangle", size: .compact, action: onTryOn)
                    .tint(WK.Palette.primaryText)
                // El color en el símbolo: el estilo del botón pinta la
                // etiqueta con el primario y el `tint` de fuera no llegaba.
                WKCircleButton(size: .compact, action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
            }
            // Con aire en las dos medidas: pegados al canto, en una celda de
            // rejilla el pulgar los roza al arrancar el scroll.
            .padding(isCompact ? WK.Spacing.s : WK.Spacing.m)
        }
        .contentShape(.rect)
        // Doble toque para editar, igual que en el plan y en el resto de
        // lienzos. Un toque simple no: compite con el scroll.
        .onTapGesture(count: 2, perform: onEdit)
        // Mantener pulsado, **solo en la revista**: en la rejilla esa
        // pulsación saca el menú. Ver `PlanFeedCard`.
        .modifier(LongPressToEdit(isOn: !isCompact, action: onEdit))
    }

    /// El papel de la maleta, que es lo que la distingue de las demás.
    private var backdrop: Color {
        guard
            let raw = suitcase.colorRaw,
            let tint = SuitcaseTint(rawValue: raw)
        else { return WK.Palette.canvas }
        return WK.Palette.canvasTint(
            red: tint.components.red,
            green: tint.components.green,
            blue: tint.components.blue
        )
    }
}

/// Mantener pulsado para editar, donde toca.
private struct LongPressToEdit: ViewModifier {
    let isOn: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if isOn {
            content.onLongPressGesture(perform: action)
        } else {
            content
        }
    }
}

/// Una celda de la rejilla de la maleta: el lienzo y una elipsis.
///
/// La misma pieza que en el plan —ver `PlanGridCell`—, con el papel de la
/// maleta en vez del del outfit: aquí lo que distingue un viaje de otro es su
/// color.
private struct SuitcaseGridCell: View {
    let outfit: Outfit
    let suitcase: Suitcase
    let store: ImageStore
    let canMove: Bool
    let onEdit: () -> Void
    let onMove: () -> Void
    let onDuplicate: () -> Void
    let onTryOn: () -> Void
    let onDelete: () -> Void

    var body: some View {
        LookCanvasView(
            garments: outfit.garments,
            store: store,
            backdrop: SuitcaseTint.backdrop(for: suitcase.colorRaw),
            outfit: outfit,
            showsBorder: true,
            onDoubleTap: onEdit
        )
        .overlay(alignment: .topTrailing) {
            Menu {
                Button(String(localized: "common.edit", defaultValue: "Edit"), systemImage: "pencil", action: onEdit)
                Button(String(localized: "common.tryItOn", defaultValue: "Try it on"), systemImage: "person.crop.rectangle", action: onTryOn)
                Button(String(localized: "common.duplicate", defaultValue: "Duplicate"), systemImage: "plus.square.on.square", action: onDuplicate)
                if canMove {
                    Button(String(localized: "common.moveToAnotherDay", defaultValue: "Move to another day"), systemImage: "calendar", action: onMove)
                }
                Button(String(localized: "common.remove", defaultValue: "Remove"), systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WK.Palette.primaryText)
                    .frame(width: 34, height: 34)
                    .contentShape(.circle)
                    .adaptiveGlassInteractive(in: .circle)
            }
            .padding(WK.Spacing.s)
        }
    }
}

/// Los días del viaje, en la cápsula del plan — **y "sin día" al final**.
///
/// Es `DayStripCapsule` sin el calendario ni el taco de hoy —un viaje tiene sus
/// días contados—, con los mismos chips. Dentro de la barra de navegación va
/// compacta y sin cristal propio: el cristal lo pone la barra, y dos uno
/// encima del otro se ven como un parche más oscuro.
struct TripDayCapsule: View {
    let suitcase: Suitcase
    let dayCount: Int
    @Binding var selected: Int
    /// Dentro de una barra: chips más bajos y sin cristal propio.
    var isInBar = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: WK.Spacing.xs) {
                    ForEach(0..<dayCount, id: \.self) { index in
                        let date = suitcase.date(forDayIndex: index) ?? Date()
                        DayChip(
                            date: date,
                            isSelected: index == selected,
                            isToday: Calendar.current.isDateInToday(date),
                            isCompact: isInBar
                        )
                        .id(index)
                        .onTapGesture {
                            withAnimation(WKAnimation.content) { selected = index }
                        }
                    }

                    // El último "día": lo que va en la maleta sin fecha.
                    NoDayChip(isSelected: selected == dayCount, isCompact: isInBar)
                        .id(dayCount)
                        .onTapGesture {
                            withAnimation(WKAnimation.content) { selected = dayCount }
                        }
                }
                .padding(.horizontal, WK.Spacing.xs)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selected) {
                withAnimation(.snappy) { proxy.scrollTo(selected, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
        }
        .frame(height: isInBar ? 44 : 56)
        .clipShape(.capsule)
        // **Con cristal también en la barra.** Los botones de los lados lo
        // reciben del sistema; lo del centro no, y sin él los días flotaban
        // sueltos sobre el contenido, sin forma.
        .modifier(CapsuleGlass(isOn: true))
    }
}

/// El cristal de la cápsula, o nada.
private struct CapsuleGlass: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.adaptiveGlassInteractive(in: .capsule)
        } else {
            content
        }
    }
}

/// "Sin día", con la forma de un chip de día.
private struct NoDayChip: View {
    let isSelected: Bool
    var isCompact = false

    var body: some View {
        VStack(spacing: 2) {
            Text(String(localized: "suitcases.suitcaseoutfitsfeedtab.no", defaultValue: "NO"))
                .font(.caption2)
                .foregroundStyle(isSelected ? WK.Palette.onAccent.opacity(0.75) : WK.Palette.secondaryText)
            Image(systemName: "tray")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? WK.Palette.onAccent : WK.Palette.primaryText)
        }
        .frame(width: isCompact ? 36 : 42, height: isCompact ? 38 : 46)
        .background {
            if isSelected {
                Capsule().fill(WK.Palette.accent)
            }
        }
        .contentShape(.capsule)
    }
}
