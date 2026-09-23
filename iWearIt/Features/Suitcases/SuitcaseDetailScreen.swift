import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// Una maleta: sus outfits y su checklist de equipaje.
///
/// Se llega desde la balda "altillo" del Armario, empujando sobre el mismo
/// `NavigationStack`. No es una pestaña.
struct SuitcaseDetailScreen: View {
    @Query private var suitcases: [Suitcase]

    init(id: UUID) {
        _suitcases = Query(filter: #Predicate<Suitcase> { $0.id == id })
    }

    var body: some View {
        if let suitcase = suitcases.first {
            SuitcaseContent(suitcase: suitcase)
        } else {
            ContentUnavailableView("Maleta no encontrada", systemImage: "suitcase")
        }
    }
}

private enum SuitcaseTab: Hashable {
    case outfits, packing, inspo
}

/// Qué se está viendo: la pestaña y, dentro de Outfits, el modo.
private struct SuitcaseView: Hashable {
    let tab: SuitcaseTab
    let layout: PlannerLayout
}

/// El contenido real. Separado para poder usar `@Bindable` sobre una maleta que
/// ya sabemos que existe, sin desenvolver opcionales en el `@ViewBuilder`.
private struct SuitcaseContent: View {
    @Bindable var suitcase: Suitcase
    @State private var tab: SuitcaseTab = .outfits
    /// Lo que tarda en pasar de revista a rejilla.
    static let layoutChange = Animation.smooth(duration: 0.6)

    /// Revista (un día por página) o rejilla (todos los días), como en el plan.
    /// Solo con fechas: sin días no hay nada que pasar como páginas.
    @State private var layout: PlannerLayout = .book
    @State private var dayIndex = 0
    @State private var isPresentingStyle = false
    /// La hoja de a dónde vas, que da también el tiempo del viaje.
    @State private var isPickingDestination = false
    /// El "+" de la barra, **solo en Equipaje**: añadir prendas sueltas a la
    /// maleta. Lo atiende `PackingChecklistTab`.
    @State private var isPickingForNew = false
    /// El outfit que se está editando. Vive **aquí**, que es donde está la
    /// pila de navegación: las páginas del pager viven en sus propios
    /// controladores y desde ahí no se puede empujar nada.
    @State private var editingOutfit: Outfit?
    /// Si el que se edita se creó para esto. Ver `AdvancedCanvasScreen`.
    @State private var editingIsNew = false
    /// Para que el editor crezca desde el lienzo que ya se está viendo.
    @Namespace private var zoom

    @Environment(AppEnvironment.self) private var appEnvironment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            // La maleta **es** un lienzo, igual que un día del plan: el mismo
            // papel de puntos y el mismo color de fondo. Que una pantalla fuera
            // una lista con cabecera y la otra una hoja obligaba a cambiar de
            // idea sobre qué es un outfit según por dónde hubieras entrado.
            tintColor.ignoresSafeArea()
            // **Sin retícula global.** La ponía aquí *y* la pone cada página,
            // así que en la vista de día se veían dos superpuestas —con sus
            // puntos desalineados, porque cada una arranca en su origen— y en
            // la rejilla asomaba entre las celdas, donde no pinta nada. El
            // papel de puntos es del lienzo, no de la pantalla.

            SuitcaseTabContent(
                suitcase: suitcase,
                tab: tab,
                layout: layout,
                dayIndex: $dayIndex,
                isPickingForPacking: $isPickingForNew,
                zoom: zoom,
                onOpenDay: { index in
                    dayIndex = index
                    withAnimation(Self.layoutChange) { layout = .book }
                },
                onEdit: { outfit, isNew in
                    editingIsNew = isNew
                    editingOutfit = outfit
                }
            )
                .transition(.wkContent)
                // El cambio de modo también cambia la vista, así que entra en
                // la identidad: sin esto, pasar de revista a rejilla no
                // animaba nada, solo se sustituía.
                .id(SuitcaseView(tab: tab, layout: layout))
                .animation(WKAnimation.content, value: tab)
                // **Más despacio que un cambio de pestaña.** Pasar de revista
                // a rejilla es cambiar cómo se mira el viaje entero, y a la
                // velocidad de siempre se leía como un parpadeo.
                .animation(Self.layoutChange, value: layout)
        }
        // **Solo el lienzo.** El papel de puntos llega a los cuatro bordes; la
        // barra de Outfits · Equipaje se coloca **con** el área segura, encima
        // del indicador de inicio, y por eso el modificador va aquí y no
        // envolviendo también a la barra.
        .ignoresSafeArea(edges: [.top, .bottom])
        // **La barra del sistema, no una fila puesta a mano.**
        //
        // Antes esta pantalla escondía la barra y dibujaba encima su propio
        // chrome flotante. Dos cosas se rompían por eso y las dos las sufriste:
        //
        // 1. **No se podía volver deslizando.** UIKit desactiva el gesto en
        //    cuanto la barra no está.
        // 2. **El lápiz no respondía.** El botón de la esquina superior derecha
        //    quedaba tapado por la región de la barra escondida: el toque no
        //    llegaba nunca —comprobado instrumentando los dos botones: el de la
        //    izquierda registraba y el de la derecha no—.
        //
        // Con la barra de verdad las dos cosas las resuelve el sistema, y de
        // paso el selector de arriba pasa a ser el segmentado de Apple.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // **Volver deslizando, siempre.** Lo único que lo desactiva es el
        // editor, y lo desactiva él mismo mientras está abierto: ahí el lienzo
        // está lleno de arrastres y el borde izquierdo es donde se coloca una
        // prenda. Fuera del editor, el gesto es el gesto.
        //
        // Comparte borde con el paso de página del cuaderno y gana el gesto de
        // volver, que es lo pedido. Para cambiar de día quedan la tira de
        // arriba y el toque en el margen, que `pageCurl` también atiende.
        .interactivePopEnabled()
        // **Outfits · Equipaje y el lápiz, abajo**, en una segunda barra con el
        // mismo cristal que la de pestañas. Arriba queda sitio para el
        // calendario del viaje, como en el plan. El selector de arriba se
        // queda comentado:
        // .toolbar {
        //     ToolbarItem(placement: .principal) {
        //         Picker("Sección", selection: $tab) {
        //             Text("Outfits").tag(SuitcaseTab.outfits)
        //             Text("Equipaje").tag(SuitcaseTab.packing)
        //         }
        //         .pickerStyle(.segmented)
        //         .frame(width: 220)
        //     }
        //     ToolbarItem(placement: .topBarTrailing) {
        //         Button { isPresentingStyle = true } label: {
        //             Image(systemName: "pencil")
        //         }
        //         .tint(WK.Palette.primaryText)
        //     }
        // }
        // **Flotando, no recortando.** Como la tira del plan: el lienzo llega
        // a los dos bordes y la barra pasa por encima. En `safeAreaInset` le
        // comía su alto al papel de puntos y la maleta dejaba de ser una hoja
        // entera.
        .overlay(alignment: .bottom) {
            HStack(spacing: 12) {
                WKTextTabBar(tabs: [SuitcaseTab.outfits, .packing, .inspo], selection: $tab) { tab in
                    switch tab {
                    case .outfits: "Outfits"
                    case .packing: "Equipaje"
                    case .inspo: "Inspo"
                    }
                }
                Button { isPresentingStyle = true } label: {
                    Image(systemName: "pencil")
                        .font(.body.weight(.medium))
                        .foregroundStyle(WK.Palette.primaryText)
                        .frame(width: 52, height: 52)
                        .contentShape(Circle())
                }
                .buttonStyle(WKPlainGlassButtonStyle(shape: Circle()))
            }
            .padding(.bottom, WK.Spacing.xs)
        }
        // La barra de pestañas de la app estorba aquí: dentro de una maleta se
        // está montando contenido a pantalla completa, y tener debajo los tres
        // destinos de la app invita a salirse a mitad.
        .toolbarVisibility(.hidden, for: .tabBar)
        // Debajo de la barra, la tira de días: **solo** en Outfits. En Equipaje
        // no hay días —es una lista de lo que va dentro— y enseñar un selector
        // que no cambia nada promete una relación que no existe.
        // **En la barra de navegación**, no debajo: la tira del viaje en el
        // centro y revista/rejilla a la derecha. Debajo quedaba otra franja
        // más comiéndose el lienzo. Lo de antes, comentado:
        // .safeAreaInset(edge: .top) {
        //     if tab == .outfits, let dayCount = suitcase.tripDayCount {
        //         // La tira y, al lado, revista o rejilla. Igual que el plan.
        //         HStack(spacing: 0) {
        //             TripDayBar(suitcase: suitcase, dayCount: dayCount, selected: $dayIndex)
        //             Button {
        //                 withAnimation(WKAnimation.arrival) { layout = layout.next }
        //             } label: {
        //                 Image(systemName: layout.symbol)
        //                     .font(.system(size: 16, weight: .medium))
        //                     .foregroundStyle(WK.Palette.primaryText)
        //                     .frame(width: 56, height: 56)
        //                     .contentTransition(.symbolEffect(.replace.downUp))
        //                     .contentShape(.circle)
        //             }
        //             .buttonStyle(WKPressStyle())
        //             .adaptiveGlassInteractive(in: .circle)
        //             .padding(.trailing, WK.Spacing.m)
        //         }
        //         .padding(.bottom, WK.Spacing.xs)
        //         .transition(.move(edge: .top).combined(with: .opacity))
        //     }
        // }
        .toolbar {
            // **Solo en Equipaje.** En Outfits el outfit se crea tirando del
            // final o desde la celda de la rejilla, y un "+" ahí ofrecía una
            // tercera forma de hacer lo mismo.
            if tab == .packing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPickingForNew = true } label: {
                        Image(systemName: "plus")
                    }
                    .tint(WK.Palette.primaryText)
                }
            }
            // **El tiempo del destino, en el centro.** Como en la pestaña de
            // inspiración, solo que aquí el sitio es el de la maleta: tocarlo
            // cambia a dónde vas, no dónde vives.
            if tab == .inspo {
                ToolbarItem(placement: .principal) {
                    SuitcaseWeatherPill(suitcase: suitcase) { isPickingDestination = true }
                }
            }
            if tab == .outfits, let dayCount = suitcase.tripDayCount {
                ToolbarItem(placement: .principal) {
                    TripDayBar(suitcase: suitcase, dayCount: dayCount, selected: $dayIndex, isCompact: true)
                        // Lo justo para tres días: más ancha se metía por
                        // debajo de los botones de la derecha. Y de alto, lo
                        // que mida la barra, como cualquier botón suyo.
                        .frame(width: 186)
                        .frame(maxHeight: .infinity)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(Self.layoutChange) { layout = layout.next }
                    } label: {
                        Image(systemName: layout.symbol)
                            .contentTransition(.symbolEffect(.replace.downUp))
                    }
                    .tint(WK.Palette.primaryText)
                }

            }
        }
        .animation(WKAnimation.content, value: tab)

        .sheet(isPresented: $isPickingDestination) {
            PlaceSearchSheet(title: "¿A dónde vas?") { place in
                suitcase.destination = place
            }
        }
        .sheet(isPresented: $isPresentingStyle) {
            SuitcaseStyleSheet(suitcase: suitcase)
        }
        // **Empujado, no a pantalla completa.** Es el mismo editor que en el
        // plan y tiene que llegar igual: creciendo desde el lienzo, con la
        // maleta debajo en la pila.
        // **Con fechas**, el origen es la pantalla entera: se está viendo un
        // solo lienzo y crecer "desde él" es crecer desde todo. Sin fechas, el
        // origen lo pone cada celda de la rejilla, que es de donde viene de
        // verdad — por eso aquí el id es el del outfit y no uno fijo.
        .adaptiveZoomSource(id: "suitcase-editor", in: zoom)
        .navigationDestination(item: $editingOutfit) { outfit in
            AdvancedCanvasScreen(
                outfit: outfit,
                store: appEnvironment.imageStore,
                isNew: editingIsNew
            )
                .adaptiveZoomDestination(
                    id: suitcase.tripDayCount == nil
                        ? AnyHashable(outfit.stableID)
                        : AnyHashable("suitcase-editor"),
                    in: zoom
                )
        }
    }

    // **El chrome flotante, comentado y no borrado.**
    //
    // Es lo que había hasta ahora: una fila de botones de cristal sobre el
    // lienzo, con la barra del sistema escondida. Se queda aquí de referencia
    // —y porque la idea de que el papel de puntos llegue hasta arriba era
    // buena—, pero costaba el gesto de volver y el botón de editar.
    //
    // /// Volver, cambiar de pestaña y editar. Nada más.
    // ///
    // /// Los datos de la maleta —destino, fechas, icono— viven tras el lápiz y no
    // /// permanentemente en pantalla: se consultan una vez y se cambian pocas, y
    // /// ocupando sitio fijo empujan el contenido hacia abajo en cada visita.
    // @ViewBuilder
    // private var chrome: some View {
    // VStack(spacing: WK.Spacing.xs) {
    // HStack(spacing: WK.Spacing.s) {
    // ChromeCircle(symbol: "chevron.left") { dismiss() }
    // Spacer(minLength: 0)
    // SuitcaseTabBar(tab: $tab)
    // Spacer(minLength: 0)
    // ChromeCircle(symbol: "pencil") { isPresentingStyle = true }
    // }
    // .padding(.horizontal, WK.Spacing.screenInset)
    //
    // // La tira **solo en Outfits**. En Equipaje no hay días: es una
    // // lista de lo que va dentro, y enseñar un selector de día que no
    // // cambia nada es prometer una relación que no existe.
    // if tab == .outfits, let dayCount = suitcase.tripDayCount {
    // TripDayBar(suitcase: suitcase, dayCount: dayCount, selected: $dayIndex)
    // }
    // }
    // .padding(.vertical, WK.Spacing.xs)
    // .animation(WKAnimation.content, value: tab)
    // }

    // El outfit que creaba el "+" de la barra, cuando lo había en Outfits.
    // Se queda comentado: ahí se crea tirando del final o desde la rejilla.
    //
    // /// Un outfit nuevo **para el día que se está viendo**, con las prendas
    // /// elegidas ya colocadas. Sin fechas, simplemente uno más de la maleta.
    // private func makeOutfit(with garments: [Garment]) -> Outfit {
    //     let outfit = Outfit(name: suitcase.tripDayCount == nil ? nil : "Día \(dayIndex + 1)")
    //     if suitcase.tripDayCount != nil { outfit.suitcaseDayIndex = dayIndex }
    //     modelContext.insert(outfit)
    //     outfit.suitcase = suitcase
    //     for garment in garments {
    //         let slot = OutfitSlot.slot(for: garment.kind)
    //         let item = CanvasItem(transform: slot.transform, garment: garment)
    //         item.outfit = outfit
    //         modelContext.insert(item)
    //     }
    //     return outfit
    // }

    private var tintColor: Color {
        guard
            let raw = suitcase.colorRaw,
            let tint = SuitcaseTint(rawValue: raw)
        else { return WK.Palette.canvas }
        return WK.Palette.canvasTint(red: tint.components.red, green: tint.components.green, blue: tint.components.blue)
    }
}

/// Un botón redondo del chrome.
private struct ChromeCircle: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(WK.Font.headline)
                .foregroundStyle(WK.Palette.primaryText)
                .frame(width: 42, height: 42)
                .contentShape(.circle)
        }
        .buttonStyle(WKPressStyle())
        .adaptiveGlassInteractive(in: .circle)
    }
}

/// Outfits o Equipaje, en cristal sobre el lienzo.
private struct SuitcaseTabBar: View {
    @Binding var tab: SuitcaseTab
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: WK.Spacing.xs) {
            SuitcaseTabButton(title: "Outfits", tab: .outfits, selection: $tab, indicator: indicator)
            SuitcaseTabButton(title: "Equipaje", tab: .packing, selection: $tab, indicator: indicator)
        }
        .padding(WK.Spacing.xs)
        .adaptiveGlassInteractive(in: .capsule)
        .padding(.top, WK.Spacing.s)
    }
}

private struct SuitcaseTabButton: View {
    let title: String
    let tab: SuitcaseTab
    @Binding var selection: SuitcaseTab
    let indicator: Namespace.ID

    private var isSelected: Bool { selection == tab }

    var body: some View {
        Button {
            withAnimation(WKAnimation.selection) { selection = tab }
        } label: {
            Text(title)
                .font(WK.Font.captionMedium)
                .foregroundStyle(isSelected ? WK.Palette.onAccent : WK.Palette.primaryText)
                .padding(.horizontal, WK.Spacing.l)
                .padding(.vertical, WK.Spacing.s)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(WK.Palette.accent)
                            // El indicador se **mueve** entre pestañas en vez
                            // de aparecer y desaparecer: así se lee como una
                            // selección y no como dos cosas distintas.
                            .matchedGeometryEffect(id: "suitcase-tab", in: indicator)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
    }
}

/// Qué pestaña se muestra. Vista aparte para que el `switch` no viva dentro de
/// un `@ViewBuilder` con más cosas.
private struct SuitcaseTabContent: View {
    let suitcase: Suitcase
    let tab: SuitcaseTab
    let layout: PlannerLayout
    @Binding var dayIndex: Int
    @Binding var isPickingForPacking: Bool
    let zoom: Namespace.ID
    let onOpenDay: (Int) -> Void
    let onEdit: (Outfit, Bool) -> Void

    var body: some View {
        switch tab {
        case .outfits:
            SuitcaseOutfitsTab(
                suitcase: suitcase,
                layout: layout,
                dayIndex: $dayIndex,
                zoom: zoom,
                onOpenDay: onOpenDay,
                onEdit: onEdit
            )
        case .packing:
            PackingChecklistTab(suitcase: suitcase, isPresentingTray: $isPickingForPacking)
        case .inspo:
            // Con lo que te llevas y para los días de este viaje. Ver
            // `SuitcaseInspoTab`.
            // Los huecos de arriba y de abajo los pone la pantalla: la maleta
            // ignora el área segura a propósito —el lienzo llega a los dos
            // bordes— así que aquí hay que contar a mano lo que tapan la barra
            // de navegación y la de pestañas de la maleta.
            SuitcaseInspoTab(
                suitcase: suitcase,
                // Lo que mide de verdad la barra de arriba en esta pantalla
                // —el corte de la pantalla más la propia barra—, y no un 64
                // puesto a ojo: con el número corto, las tarjetas de la maleta
                // salían más grandes que las de la pestaña de inspiración y al
                // pasar de una a otra se notaba el salto.
                topInset: WKTabBarMetrics.topClearance,
                bottomInset: WKTabBarMetrics.barHeight + 2 * WK.Spacing.l
            )
        }
    }
}

/// Cabecera: fechas y cuánto llevas metido.
private struct SuitcaseHeader: View {
    let suitcase: Suitcase

    private static let range: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.xs) {
            if let start = suitcase.startDate, let end = suitcase.endDate {
                Label(
                    Self.range.string(from: start, to: end),
                    systemImage: "calendar"
                )
                .font(.subheadline)
                .foregroundStyle(WK.Palette.secondaryText)
            } else {
                Label("Sin fechas", systemImage: "calendar.badge.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(WK.Palette.secondaryText)
            }

            PackingProgress(
                packed: suitcase.packedCount,
                total: suitcase.packingEntries.count
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, WK.Spacing.m)
        .padding(.bottom, WK.Spacing.m)
    }
}

/// Barra de progreso del equipaje. Vista propia: es lo único de la cabecera que
/// cambia al marcar una prenda, y así no se reevalúa el resto.
private struct PackingProgress: View {
    let packed: Int
    let total: Int

    var body: some View {
        if total > 0 {
            VStack(alignment: .leading, spacing: WK.Spacing.xs) {
                Text("\(packed) de \(total) en la maleta")
                    .font(.footnote)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .monospacedDigit()
                ProgressView(value: Double(packed), total: Double(total))
                    .tint(WK.Palette.accent)
            }
        }
    }
}


/// El tiempo del destino, en píldora, como en la pestaña de inspiración.
///
/// Con el sitio puesto dice a dónde vas y qué hace allí el primer día; sin él,
/// es el sitio donde ponerlo. Editarlo cambia el destino de **esta maleta**:
/// el tiempo de un viaje no tiene nada que ver con el de casa.
private struct SuitcaseWeatherPill: View {
    let suitcase: Suitcase
    let onTap: () -> Void

    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var forecast: WeatherSnapshot?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: WK.Spacing.xs) {
                // En color, como en la pestaña de inspiración: el parte del
                // destino se lee de un vistazo.
                Image(systemName: forecast?.condition.symbolName ?? "location")
                    .symbolRenderingMode(.multicolor)
                Text(title)
            }
            .font(WK.Font.callout)
            .foregroundStyle(WK.Palette.primaryText)
            .fixedSize()
            .padding(.horizontal, WK.Spacing.m)
            .padding(.vertical, WK.Spacing.xs)
            .adaptiveGlassInteractive(in: .capsule)
        }
        .tint(WK.Palette.primaryText)
        .task(id: suitcase.destinationName) { await load() }
    }

    private var title: String {
        guard let destination = suitcase.destination else { return "Elegir destino" }
        // Solo la ciudad: el país repetido no cabe en la barra.
        let city = destination.name.split(separator: ",").first.map(String.init)
            ?? destination.name
        guard let forecast else { return city }
        return "\(city), \(Int(forecast.highCelsius.rounded()))°"
    }

    private func load() async {
        guard let destination = suitcase.destination else {
            forecast = nil
            return
        }
        // El primer día del viaje, que es el que se está preparando; sin
        // fechas, hoy.
        let date = suitcase.date(forDayIndex: 0) ?? Date()
        forecast = await appEnvironment.weather.snapshot(for: date, at: destination)
    }
}
