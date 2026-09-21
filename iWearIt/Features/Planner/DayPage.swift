import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// Un día del planificador.
///
/// **Un día son varios lienzos, no uno.** Lo que te pones para comer no es lo
/// que te pones para cenar, y con un solo outfit por día había que elegir cuál
/// de los dos merecía guardarse. Se apilan en vertical y se pasa de uno a otro
/// deslizando; al final siempre hay un lienzo vacío, de modo que crear el
/// siguiente es seguir bajando y no buscar un botón.
///
/// Carga su `PlannedDay` con un `@Query` propio acotado a esa fecha, así que
/// editar el outfit de un día no toca las páginas vecinas que el pager mantiene
/// vivas a los lados.
///
/// - Important: fondo **opaco** obligatorio. `pageCurl` no sabe enrollar una
///   página transparente y deja artefactos al pasar hoja.
struct DayPage: View {
    private let date: Date
    /// Pide a la pantalla que empuje el editor. La página no puede navegar por
    /// su cuenta: vive en su propio `UIHostingController` dentro del pager.
    private let onEdit: (Outfit) -> Void
    /// Avisa de qué lienzo se está viendo, para que la sección de abajo sepa
    /// si hay outfit que editar o uno que crear. La página no lleva botón: uno
    /// por lienzo se repetiría en cada página del scroll vertical.
    ///
    /// **Con su fecha.** El pager mantiene vivas las páginas de los días
    /// vecinos, y esas también reportan: al pasar de día, la de al lado
    /// contestaba después y pisaba el foco del día que se estaba mirando. Con
    /// la fecha delante, quien recibe puede ignorar lo que no es del día
    /// visible.
    private let onFocus: (Date, Outfit?) -> Void
    @Query private var days: [PlannedDay]

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    init(
        date: Date,
        onEdit: @escaping (Outfit) -> Void,
        onFocus: @escaping (Date, Outfit?) -> Void = { _, _ in }
    ) {
        let dayStart = Calendar.current.startOfDay(for: date)
        self.date = dayStart
        self.onEdit = onEdit
        self.onFocus = onFocus
        _days = Query(filter: #Predicate<PlannedDay> { $0.dayStart == dayStart })
    }

    private var outfits: [Outfit] { days.first?.orderedOutfits ?? [] }

    /// Cuál de los lienzos del día.
    ///
    /// **Un tipo propio y no un `PersistentIdentifier?`.** El hueco del final
    /// no tiene outfit, así que se identificaba con `nil` — y `nil` es
    /// exactamente lo que `scrollPosition` usa para decir "no sé dónde estoy".
    /// Las dos cosas eran indistinguibles: bajar al hueco parecía perder la
    /// posición, y el `task` de abajo lo trataba como "aún no hay posición" y
    /// **devolvía el foco al primer outfit**. De ahí que el botón se quedara en
    /// "Editar" por mucho que bajaras.
    private enum Page: Hashable {
        case outfit(PersistentIdentifier)
        /// El lienzo en blanco del final, que sí existe y sí tiene identidad.
        case new
    }

    /// Qué lienzo se está viendo. `nil` **solo** mientras no se ha medido.
    @State private var visiblePage: Page?

    var body: some View {
        // Vertical y paginado: cada lienzo ocupa la página entera, como el día
        // entero la ocupa en horizontal. Media página de un lienzo y media del
        // siguiente no se lee como dos outfits sino como uno cortado.
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(outfits) { outfit in
                    DayCanvas(date: date, outfit: outfit, onEdit: onEdit)
                        .containerRelativeFrame(.vertical)
                        .id(Page.outfit(outfit.persistentModelID))
                }

                // El hueco siguiente, siempre. Es lo que convierte "crear otro
                // outfit" en seguir bajando.
                DayCanvas(date: date, outfit: nil, onEdit: onEdit, makeOutfit: makeOutfit)
                    .containerRelativeFrame(.vertical)
                    .id(Page.new)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        // **Por visibilidad y no solo por posición.**
        //
        // `scrollPosition` avisa cuando el scroll **se asienta**, y con el
        // pager de por medio hay casos en que no llega a asentarse en el
        // sentido que SwiftUI espera: se quedaba sin avisar y el botón no
        // cambiaba. Esto avisa en cuanto una página pasa a ocupar más de la
        // mitad de la ventana, que es exactamente cuando el usuario diría que
        // "está viendo" ese lienzo.
        .onScrollTargetVisibilityChange(idType: Page.self, threshold: 0.55) { visible in
            guard let page = visible.first else { return }
            visiblePage = page
            report(page)
        }
        // **Por posición de scroll y no por `onAppear`.**
        //
        // `onAppear` se dispara también en la página vacía del final mientras
        // sigues mirando la anterior, y en un orden que no se puede predecir:
        // el botón decía "Crear" estando sobre un outfit y al revés. La
        // posición dice exactamente cuál se está viendo.
        .scrollPosition(id: $visiblePage)
        .onChange(of: visiblePage) { _, page in
            report(page)
        }
        // **Al aparecer también.** `scrollPosition` arranca en `nil` y
        // `onChange` no dispara por eso: el botón decía "Crear" estando sobre
        // un outfit hasta que scrolleabas, que es justo el caso más común.
        //
        // Solo cuando de verdad no hay posición todavía. Antes esto se
        // ejecutaba también al bajar al hueco —porque entonces la posición era
        // `nil`— y volvía a empujar el foco al primer outfit.
        .task(id: outfits.count) {
            if visiblePage == nil {
                visiblePage = outfits.first.map { Page.outfit($0.persistentModelID) } ?? .new
            }
            report(visiblePage)
        }
        .scrollIndicators(.hidden)
        // **Y al volver a aparecer.** Al empujar el editor, esta página se
        // queda viva pero deja de estar visible; al volver, ni `task` ni
        // `onChange` se disparan —nada ha cambiado— y el botón se quedaba con
        // lo último que hubiera dicho otra página. Reportar al reaparecer es
        // lo que arregla "voy y vuelvo y pone lo que no es".
        .onAppear { report(visiblePage) }
        .background(WK.Palette.canvas.ignoresSafeArea())
        .ignoresSafeArea()
    }

    /// Qué outfit está a la vista, o ninguno si es el hueco.
    ///
    /// Es lo que decide si el botón de abajo dice "Editar" o "Crear", así que
    /// la diferencia entre "el hueco" y "todavía no sé" tiene que sobrevivir
    /// hasta aquí — por eso `Page` y no un id opcional.
    private func report(_ page: Page?) {
        switch page {
        case let .outfit(id):
            onFocus(date, outfits.first { $0.persistentModelID == id })
        case .new, nil:
            onFocus(date, nil)
        }
    }

    /// Crea el siguiente outfit del día, creando el día si hace falta.
    @discardableResult
    private func makeOutfit() -> Outfit {
        let day = days.first ?? {
            let new = PlannedDay(dayStart: date)
            modelContext.insert(new)
            return new
        }()
        let outfit = Outfit()
        modelContext.insert(outfit)
        outfit.plannedDay = day
        return outfit
    }
}

/// Un lienzo del día.
///
/// Vista propia con su propia selección: dos lienzos del mismo día no pueden
/// compartir qué prenda está cogida, y tener la selección en el padre haría que
/// tocar algo en el de abajo deseleccionara en el de arriba.
private struct DayCanvas: View {
    let date: Date
    let outfit: Outfit?
    let onEdit: (Outfit) -> Void
    /// Crea el outfit cuando este lienzo es el hueco vacío del final.
    var makeOutfit: (() -> Outfit)?

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var isPickingGarments = false
    @State private var selection = CanvasSelection()
    /// El outfit creado por este hueco, para poder abrirlo al momento.
    @State private var created: Outfit?

    /// Cuántas prendas hay en el armario.
    ///
    /// Solo el número: contar es mucho más barato que traerse los objetos, y
    /// esta vista no necesita ninguno.
    @Query private var garments: [Garment]
    private var garmentCount: Int { garments.count }

    private var current: Outfit? { outfit ?? created }

    /// Un día que ya pasó no se planifica: se recuerda.
    private var isPast: Bool {
        date < Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        ZStack {
            DotGridBackground().allowsHitTesting(false)

            if let current, !current.items.isEmpty {
                FreeformCanvas(outfit: current, store: appEnvironment.imageStore, selection: selection)
                    // Sin tocar las prendas: en revista el lienzo es una
                    // **vista previa**, no el editor. Colocar aquí sería
                    // editar sin haber entrado a editar, y con el scroll
                    // vertical de por medio cualquier arrastre descolocaría
                    // algo por accidente.
                    .allowsHitTesting(false)
                    // Pero entrar a editarlo sí, y desde el propio lienzo.
                    //
                    // Doble toque y mantener pulsado, las dos: un toque simple
                    // no puede ser —compite con el scroll de página y con
                    // deseleccionar—, y cuál de las dos espera cada uno depende
                    // de si viene de una app de fotos o de una de notas.
                    .onTapGesture(count: 2) { onEdit(current) }
                    .onLongPressGesture(minimumDuration: 0.4) { onEdit(current) }
                    // Área de toque en todo el lienzo: sin esto, el gesto solo
                    // existe donde hay una prenda pintada, y el hueco entre
                    // ellas —que es la mayor parte— no responde.
                    .contentShape(.rect)
            } else {
                EmptyDayPrompt(
                    date: date,
                    isPast: isPast,
                    garmentCount: garmentCount
                ) { isPickingGarments = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // El color, como **fondo del contenedor**.
        //
        // Como capa dentro del `ZStack` con `ignoresSafeArea` no funcionaba:
        // ahí dentro de un `ScrollView` paginado pide crecer más allá del
        // contenedor y SwiftUI le da tamaño cero.
        //
        // Y **antes** de la máscara, que es lo que faltaba. Los modificadores
        // se aplican de dentro hacia fuera: con el fondo puesto después, la
        // máscara solo llegaba a la retícula y a las prendas, y el color se
        // pintaba entero por detrás. Por eso entre dos lienzos seguía habiendo
        // un canto duro donde se tocan sus colores por mucho degradado que
        // hubiera: lo que se veía en el corte era justo lo que no se estaba
        // enmascarando.
        .background(backdropColor)
        // **Cada lienzo se desvanece por su cuenta**, arriba y abajo.
        //
        // La máscara va aquí y no en el `ScrollView`: puesta en el scroll, lo
        // que se difumina son los bordes de la ventana —una banda fija que no
        // se mueve con el contenido—. En cada página, el degradado viaja con
        // ella y el paso de un color al siguiente se funde.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .sheet(isPresented: $isPickingGarments) {
            OutfitPickerSheet(store: appEnvironment.imageStore) { picked in
                onEdit(fill(with: picked))
            }
        }
    }

    /// El color del día. Vive en el outfit porque es parte de cómo quedó, no
    /// una preferencia de la pantalla.
    private var backdropColor: Color {
        guard
            let components = OutfitBackdrop(rawValue: current?.backdropRaw ?? "")?.components
        else { return WK.Palette.canvas }
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    @discardableResult
    private func fill(with garments: [Garment]) -> Outfit {
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
        return target
    }

    @discardableResult
    private func ensureOutfit() -> Outfit {
        if let current { return current }
        let new = makeOutfit?() ?? Outfit()
        created = new
        return new
    }
}

/// Lo que se ve en un lienzo sin planear: el sticker de la fecha y una
/// invitación.
///
/// El sticker no es decoración — es la misma pieza que se puede pegar en el
/// canvas, así que la página vacía ya enseña de qué va esto.
struct EmptyDayPrompt: View {
    /// Prendas mínimas para que planificar signifique algo.
    ///
    /// Con dos camisetas no hay nada que decidir: el "outfit" es la única
    /// combinación posible, y la app se queda con la impresión de no servir
    /// para nada. Cinco es el mínimo en que empieza a haber elección.
    static let minimumGarments = 5

    let date: Date
    /// Hacia atrás la app no planifica, registra.
    ///
    /// "Planea tu outfit" para el martes pasado no tiene sentido y además
    /// desanima a usar lo único que ahí sí vale: dejar constancia de lo que
    /// llevaste, que es lo que luego alimenta las estadísticas de uso.
    var isPast = false
    var garmentCount = Self.minimumGarments
    let onPlan: () -> Void

    private var hasEnough: Bool { garmentCount >= Self.minimumGarments }

    var body: some View {
        VStack(spacing: WK.Spacing.xl) {
            Spacer()

            DateStickerView(date: date)
                .frame(width: 128, height: 140)
                .shadow(color: WK.Palette.ink(0.18), radius: 18, y: 10)

            if hasEnough {
                Button(action: onPlan) { prompt }
                    .buttonStyle(WKPressStyle())
            } else {
                // Sin prendas suficientes no se ofrece planificar: llevaría a un
                // selector casi vacío, que es peor que decir cuánto falta.
                GarmentProgressPill(count: garmentCount, total: Self.minimumGarments)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, WK.Spacing.screenInset)
    }

    private var prompt: some View {
        HStack(spacing: WK.Spacing.m) {
            Image(systemName: "plus")
                .font(WK.Font.headline)
                .foregroundStyle(WK.Palette.secondaryText)

            VStack(alignment: .leading, spacing: 2) {
                Text(isPast ? "Registra qué llevaste" : "Planea tu outfit")
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.primaryText)
                Text(isPast
                     ? "Guarda el look de ese día en tu historial"
                     : "Obtén una sugerencia de tu guardarropa")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(WK.Spacing.m)
        .background(
            WK.Palette.shelf,
            in: .rect(cornerRadius: WK.Radius.medium, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                .stroke(WK.Palette.ink(0.07), lineWidth: 1)
        )
        .contentShape(.rect)
    }
}

/// Cuánto falta para poder planificar.
///
/// Un número y una barra, no un texto de error. "Necesitas 5 prendas" regaña;
/// "2 de 5 prendas" enseña el progreso y deja claro que ya vas por la mitad.
private struct GarmentProgressPill: View {
    let count: Int
    let total: Int

    var body: some View {
        VStack(spacing: WK.Spacing.s) {
            Text("\(count) de \(total) prendas")
                .font(WK.Font.rowTitle)
                .foregroundStyle(WK.Palette.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())

            Capsule()
                .fill(WK.Palette.ink(0.08))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(WK.Palette.accent)
                            .frame(
                                width: proxy.size.width
                                    * min(1, Double(count) / Double(max(total, 1)))
                            )
                    }
                }
                .frame(height: 6)

            Text("Añade unas cuantas más y podrás planificar.")
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(WK.Spacing.m)
        .frame(maxWidth: .infinity)
        .background(
            WK.Palette.shelf,
            in: .rect(cornerRadius: WK.Radius.medium, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                .stroke(WK.Palette.ink(0.07), lineWidth: 1)
        )
        .animation(WKAnimation.content, value: count)
    }
}

struct DayActionButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(WK.Font.headline)
                .foregroundStyle(WK.Palette.primaryText)
                .frame(width: 38, height: 38)
                .contentShape(.circle)
        }
        .buttonStyle(WKPressStyle())
        .adaptiveGlass(in: .circle)
    }
}
