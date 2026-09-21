import SwiftData
import SwiftUI
import WKCore
import WKCanvas
import WKDesign
import WKPersistence

/// Planificación: un canvas por día, con paso de página estilo libro.
///
/// **Sin estado propio salvo el día elegido**, que es lo mínimo que alguien
/// tiene que saber aquí. El contenido de cada día lo resuelve su propia página.
struct PlannerScreen: View {
    /// Qué pestaña está activa. La barra se dibuja **aquí dentro**, en la raíz
    /// de esta pila de navegación, para que el editor la tape al abrirse.
    @Binding var tab: RootTab

    /// Día de referencia: hoy. Las páginas se indexan por desplazamiento en
    /// días respecto a él, que es lo que `UIPageViewController` necesita —
    /// entero, ordenable e infinito en ambos sentidos.
    @State private var anchorDay = Calendar.current.startOfDay(for: Date())
    @State private var dayOffset = 0
    /// Una sola hoja. Apilar `.sheet` en la misma vista deja mudos a todos
    /// menos a uno — ya nos costó que el color de fondo del editor no abriera
    /// nada.
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable {
        case calendar, newOutfit
        var id: String { rawValue }
    }
    /// El outfit que se está editando. Vive **aquí** y no dentro de la página
    /// porque la pila de navegación es de esta pantalla: cada página del pager
    /// vive en su propio `UIHostingController`, fuera del `NavigationStack`, y
    /// desde ahí un `navigationDestination` no llega a ninguna parte.
    @State private var editingOutfit: Outfit?
    /// Para que el editor crezca **desde** el lienzo que ya se está viendo, en
    /// vez de aparecer desde abajo como una pantalla distinta.
    @Namespace private var zoom
    /// Para que al cambiar de modo cada lienzo viaje a su sitio.
    @Namespace private var morph
    /// El lienzo que se está viendo ahora mismo. Lo reporta la página, porque
    /// el scroll vertical es suyo.
    /// Qué outfit se está viendo **en cada día**.
    ///
    /// Un diccionario y no una sola variable, y eso es el arreglo. El pager
    /// mantiene vivas las páginas de los días vecinos y todas reportan, en un
    /// orden que no se controla: al cambiar de día, la página nueva avisaba
    /// **antes** de que el índice se actualizara, así que filtrar por "¿eres
    /// el día actual?" descartaba justo el aviso bueno y el botón se quedaba
    /// con lo del día anterior.
    ///
    /// Guardando lo que dice cada día por separado, el orden deja de importar:
    /// se mira el del día visible cuando hace falta, no cuando llega.
    @State private var focusByDay: [Date: Outfit] = [:]

    /// El outfit del día que se está mirando. Ausente = el lienzo en blanco del
    /// final, y ahí el botón dice "Crear".
    private var focusedOutfit: Outfit? {
        focusByDay[date(forOffset: dayOffset)]
    }
    /// Cuánto se aleja la vista.
    ///
    /// Tres niveles de zoom sobre lo mismo: el librito para montar un outfit,
    /// la rejilla del día para elegir entre los de ese día, y todos para ver el
    /// mes. El botón va bajando un nivel y vuelve al principio, que es más
    /// corto que un selector de tres estados para algo que se cambia a ojo.
    @State private var layout: PlannerLayout = .book
    /// Lo que ocupa la hora y la muesca, arriba.
    ///
    /// **Los dos modos ignoran el área segura**, y tienen que hacerlo: si uno
    /// la respeta y el otro no, los dos miden distinto y al cruzarse en la
    /// transición el contenido pega un salto. Ignorándola los dos, el papel
    /// llega a los cuatro bordes en los dos modos y no hay nada que saltar.
    ///
    /// El precio es que el hueco de arriba lo pone el contenido, así que hay
    /// que saber cuánto vale el área segura. Se mide en la raíz, que es la
    /// única vista de aquí que todavía la respeta.
    @State private var safeTop: CGFloat = 0
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            // ## Quién anima y quién no
            //
            // El `ZStack` es el padre y **no se mueve**. Dentro, solo el
            // contenido cambia de modo y solo él lleva la animación; la tira y
            // la barra de abajo son hermanas suyas, no adornos colgados encima.
            //
            // Tenerlas como `overlay` del contenido las metía dentro del
            // subárbol que anima: al cambiar de revista a rejilla, el
            // contenedor se recalculaba y el calendario se recolocaba con él.
            // Un control que no cambia no debería moverse porque cambie otra
            // cosa.
            ZStack(alignment: .top) {
                content
                    .animation(WKAnimation.arrival, value: layout)

                topGradient
                strip
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { measured in
                guard measured > 0, abs(measured - safeTop) > 0.5 else { return }
                safeTop = measured
            }
            // **El mismo modificador que el CTA del armario.** Así el botón
            // queda exactamente a la misma altura sobre la tab bar en las dos
            // pantallas, en vez de a la que yo calcule a mano.
            // **Solo en revista.** En rejilla el hueco para crear ya está
            // dentro —la celda con el trazo discontinuo— y el botón de abajo
            // duplicaría la misma acción a dos centímetros. Y "Editar" no
            // significa nada ahí: en rejilla no hay un outfit a la vista, hay
            // todos los del día.
            // **Sin el botón de editar, de momento.** Se queda comentado y no
            // se borra: al lienzo se entra con doble toque o pulsación larga,
            // y la píldora de "crear nuevo outfit" del sobre-scroll aparece
            // justo donde estaba este botón.
            //
            // .adaptiveFloatingAccessory {
            //     if layout == .book {
            //         PlannerBottomBar(
            //             hasOutfit: focusedOutfit != nil,
            //             onEdit: { editCurrent() }
            //         )
            //         .transition(.move(edge: .bottom).combined(with: .opacity))
            //     }
            // }
            .animation(WKAnimation.arrival, value: layout)
            .rootTabBar(selection: $tab)
            .navigationDestination(item: $editingOutfit) { outfit in
                AdvancedCanvasScreen(outfit: outfit, store: appEnvironment.imageStore)
                    // El mismo id que la fuente: en rejilla es la celda, en
                    // revista el lienzo entero. En los dos casos el editor sale
                    // **de donde estaba** lo que se abre.
                    .adaptiveZoomDestination(id: outfit.stableID, in: zoom)
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
            .background(WK.Palette.canvas.ignoresSafeArea())
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(item: $sheet) { which in
                switch which {
                case .calendar:
                    CalendarJumpSheet(
                        selection: Binding(
                            get: { date(forOffset: dayOffset) },
                            set: { dayOffset = offset(for: $0) }
                        )
                    )
                case .newOutfit:
                    // **El "+" elige prendas primero.** Abría el editor con un
                    // lienzo vacío, y eso dejaba un outfit en blanco en el día
                    // en cuanto tocabas el hueco sin querer. Así no existe
                    // nada hasta que hay algo que poner dentro.
                    OutfitPickerSheet(store: appEnvironment.imageStore) { picked in
                        guard !picked.isEmpty else { return }
                        editingOutfit = makeOutfit(with: picked)
                    }
                }
            }
        }
    }

    /// Lo que cambia entre modos. Lo único que anima.
    @ViewBuilder
    private var content: some View {
        switch layout {
        case .book:
            // **El contenedor solo se funde. Lo que se mueve son las piezas.**
            //
            // Deslizar el bloque entero —arriba, abajo, da igual— tapa lo
            // único que de verdad cuenta lo que está pasando: cada lienzo
            // yendo a su sitio, uno hacia arriba y otro hacia abajo, cada uno
            // al suyo. Con el contenedor moviéndose, todos parecen ir en la
            // misma dirección y el viaje de cada uno deja de verse.
            pager.transition(.opacity)
        case .grid:
            // Scroll horizontal paginado, **no el pager de revista**: el paso
            // de hoja con curl es la metáfora del librito, y en rejilla no se
            // está pasando una página sino cambiando de día. Una página por
            // día, cada una ocupando la pantalla entera.
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(gridOffsets, id: \.self) { offset in
                        PlannerGrid(
                            date: date(forOffset: offset),
                            store: appEnvironment.imageStore,
                            // Área segura más un respiro. La rejilla pasa por
                            // debajo de la tira, que flota sobre ella, y con
                            // 24 la primera fila le quedaba pegada.
                            topInset: safeTop + WK.Spacing.l + 12,
                            morph: morph,
                            zoom: zoom,
                            onOpen: { editingOutfit = $0 },
                            onCreate: { sheet = .newOutfit }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .containerRelativeFrame(.horizontal)
                        .id(offset)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: gridPosition)
            .ignoresSafeArea()
            // El contenedor se funde y ya.
            //
            // Las celdas llevan `matchedGeometryEffect` con el id del outfit,
            // pero **hoy no emparejan con nada**: el otro extremo tendría que
            // estar en el librito, y el librito vive dentro de
            // `UIHostingController`s del pasador de hoja, que es otro árbol de
            // SwiftUI. Un efecto con un solo extremo no viaja. Queda anotado
            // aquí porque es la razón de que los dos sentidos no se sientan
            // iguales, y no la curva.
            .transition(.opacity)
        }
    }

    /// Los días que se materializan en la rejilla. Acotado: un scroll
    /// infinito en horizontal no se puede paginar por id.
    private var gridOffsets: [Int] { Array(-120...120) }

    /// El día visible en la rejilla, atado al mismo `dayOffset` que la tira.
    private var gridPosition: Binding<Int?> {
        Binding(
            get: { dayOffset },
            set: { if let value = $0 { dayOffset = clamp(value) } }
        )
    }

    /// El día elegido **con desplazamiento animado**.
    ///
    /// Tocar el jueves en la tira tiene que llevarte hasta el jueves
    /// deslizándose, no aparecer allí de golpe: el salto no dice si has ido
    /// hacia delante o hacia atrás, y en rejilla —donde todo son tarjetas
    /// parecidas— es fácil perder el sitio.
    private var animatedDay: Binding<Int> {
        Binding(
            get: { dayOffset },
            set: { value in
                withAnimation(WKAnimation.content) { dayOffset = clamp(value) }
            }
        )
    }

    /// Para que lo que pase por debajo no compita con los números.
    private var topGradient: some View {
        LinearGradient(
            colors: [WK.Palette.canvas, WK.Palette.canvas.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 150)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    /// La tira de días y el botón de modo. **Fijos.**
    private var strip: some View {
        DayStripBar(
            anchorDay: anchorDay,
            selectedOffset: animatedDay,
            onOpenCalendar: { sheet = .calendar },
            layoutSymbol: layout.symbol,
            onToggleLayout: {
                withAnimation(WKAnimation.arrival) { layout = layout.next }
            }
        )
    }

    /// El librito: una página por día.
    private var pager: some View {
        EdgeCurlPager(index: Binding(
            get: { dayOffset },
            set: { dayOffset = clamp($0) }
        )) { offset in
            DayPage(
                date: date(forOffset: offset),
                onEdit: { editingOutfit = $0 },
                // Cada día apunta lo suyo. Quién llega primero da igual.
                onFocus: { reported, outfit in
                    if let outfit {
                        focusByDay[reported] = outfit
                    } else {
                        focusByDay.removeValue(forKey: reported)
                    }
                }
            )
        }
        // Arriba **también**: el lienzo es la hoja entera. Si respeta el área
        // segura, la retícula empieza por debajo de la hora y deja una franja
        // muerta justo donde la tira tiene que flotar *sobre* el papel.
        .ignoresSafeArea()
        .adaptiveZoomSource(id: focusedOutfit?.stableID ?? Self.placeholderZoomID, in: zoom)
    }

    /// Id de repuesto cuando el lienzo visible todavía no tiene outfit. Nunca
    /// coincide con uno real, así que la transición cae al empuje normal en vez
    /// de crecer desde un sitio equivocado.
    private static let placeholderZoomID = UUID()

    /// Abre el lienzo que se está viendo, creándolo si está vacío.
    private func editCurrent(forcingNew: Bool = false) {
        if !forcingNew, let focusedOutfit {
            editingOutfit = focusedOutfit
            return
        }
        // Sin outfit en el lienzo visible: se crea uno para hoy y se abre.
        editingOutfit = makeOutfit(with: [])
    }

    /// Un outfit nuevo en el día que se está mirando, con las prendas
    /// elegidas ya en su hueco.
    private func makeOutfit(with garments: [Garment]) -> Outfit {
        let outfit = Outfit()
        modelContext.insert(outfit)
        let dayStart = date(forOffset: dayOffset)
        let existing = try? modelContext.fetch(
            FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.dayStart == dayStart })
        )
        let day = existing?.first ?? {
            let new = PlannedDay(dayStart: dayStart)
            modelContext.insert(new)
            return new
        }()
        outfit.plannedDay = day

        for garment in garments {
            let slot = OutfitSlot.slot(for: garment.kind)
            let item = CanvasItem(transform: slot.transform, garment: garment)
            item.outfit = outfit
            modelContext.insert(item)
        }
        return outfit
    }

    /// Frena el avance en el tope del plan y abre el paywall en su lugar.
    ///
    /// Se comprueba al **cambiar** de día y no al pintarlo: bloquear el render
    /// dejaría una pantalla en blanco sin explicación.
    private func clamp(_ offset: Int) -> Int {
        guard let limit = appEnvironment.gate.planningDayLimit, offset > limit else {
            return offset
        }
        appEnvironment.gate.require(.extendedPlanning) {}
        return limit
    }

    private func date(forOffset offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: anchorDay) ?? anchorDay
    }

    private func offset(for date: Date) -> Int {
        Calendar.current.dateComponents(
            [.day],
            from: anchorDay,
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
    }

    /// Estático: crear un formateador en cada `body` es una asignación por
    /// frame para nada.
    private static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter
    }()
}

extension String {
    /// Mayúscula solo en la primera letra.
    ///
    /// `.capitalized` pone mayúscula a **cada** palabra, y en español eso
    /// convierte "septiembre de 2026" en "Septiembre De 2026".
    var sentenceCased: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

/// Icono detrás del texto, como en los menús desplegables del sistema.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.font(.caption2.weight(.semibold))
        }
    }
}

#Preview {
    @Previewable @State var tab = RootTab.closet
    return PlannerScreen(tab: $tab)
        .environment(AppEnvironment.live())
        .modelContainer(try! WardrobeStore.makeContainer(inMemory: true))
}


/// Cómo se ve el plan.
///
/// Dos y no tres. Un tercer nivel "todos los outfits de todos los días" suena
/// bien y en la mano es otra pantalla distinta a la que llegar pulsando dos
/// veces un botón que no dice a dónde va.
enum PlannerLayout {
    /// Revista: un día por página, con sus lienzos en vertical.
    case book
    /// Todos los outfits de ese día, juntos.
    case grid

    var next: PlannerLayout {
        switch self {
        case .book: .grid
        case .grid: .book
        }
    }

    var symbol: String {
        switch self {
        case .book: "square.grid.2x2"
        case .grid: "book.pages"
        }
    }
}
