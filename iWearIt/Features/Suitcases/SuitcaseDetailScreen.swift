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
            ContentUnavailableView(String(localized: "suitcases.suitcasedetailscreen.suitcaseNotFound", defaultValue: "Suitcase not found"), systemImage: "suitcase")
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
    // @State private var isPresentingStyle = false
    /// La hoja abierta: el destino o los datos de la maleta.
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable {
        case destination, style
        var id: String { rawValue }
    }
    /// La hoja de a dónde vas, que da también el tiempo del viaje.
    // @State private var isPickingDestination = false
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
            // **Sin el color de la maleta de fondo.** Cada pestaña pinta el
            // suyo, y este solo asomaba al cambiar de una a otra: un
            // fogonazo del color de la maleta en mitad de la transición.
            // tintColor.ignoresSafeArea()
            WK.Palette.canvas.ignoresSafeArea()
            // **Sin retícula global.** La ponía aquí *y* la pone cada página,
            // así que en la vista de día se veían dos superpuestas —con sus
            // puntos desalineados, porque cada una arranca en su origen— y en
            // la rejilla asomaba entre las celdas, donde no pinta nada. El
            // papel de puntos es del lienzo, no de la pantalla.

            SuitcaseTabContent(
                suitcase: suitcase,
                tab: tab,
                layout: $layout,
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
                // **Solo la pestaña.** El modo estaba aquí dentro porque la
                // pestaña vieja cambiaba de vista entera al pasar de revista a
                // rejilla. La nueva no: son las mismas tarjetas colocadas de
                // otra manera, y viajan de un sitio a otro con la transición
                // de geometría. Con el modo en la identidad se destruía todo y
                // se volvía a construir, así que no viajaba nada y encima el
                // scroll de cada día se perdía.
                .id(tab)
                .animation(WKAnimation.content, value: tab)
                // **Más despacio que un cambio de pestaña.** Pasar de revista
                // a rejilla es cambiar cómo se mira el viaje entero, y a la
                // velocidad de siempre se leía como un parpadeo.
                .animation(Self.layoutChange, value: layout)
        }
        // **Ya no se ignora el área segura.** Se hacía para que el papel llegara
        // a los cuatro bordes, y a cambio cada pestaña tenía que contar a mano
        // lo que tapan las barras: la de navegación, la de Outfits · Equipaje,
        // el corte de la pantalla. Esas cuentas nunca cuadraron con las del
        // plan —que sí respeta el área segura— y de ahí salían las tarjetas
        // pequeñas y la tira debajo del botón de volver. El fondo sigue
        // llegando a los bordes (`tintColor.ignoresSafeArea()`, arriba); lo
        // que se coloca, se coloca con el sistema.
        // .ignoresSafeArea(edges: [.top, .bottom])
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
        // **Sin barra en Outfits.** Ahí la pestaña pone su propia tira —volver,
        // los días y el modo— y dos franjas arriba en una pantalla cuyo papel
        // llega a los cuatro bordes es una de más. En Equipaje e Inspiración
        // la barra se queda: llevan el "+" y la píldora del tiempo.
        // La barra vuelve también en Outfits, con su botón de volver: los días
        // y el modo van dentro de ella. Lo que había:
        // .toolbarVisibility(tab == .outfits ? .hidden : .automatic, for: .navigationBar)
        // **Volver deslizando, siempre.** Lo único que lo desactiva es el
        // editor, y lo desactiva él mismo mientras está abierto: ahí el lienzo
        // está lleno de arrastres y el borde izquierdo es donde se coloca una
        // prenda. Fuera del editor, el gesto es el gesto.
        //
        // Comparte borde con el paso de página del cuaderno y gana el gesto de
        // volver, que es lo pedido. Para cambiar de día quedan la tira de
        // arriba y el toque en el margen, que `pageCurl` también atiende.
        // **Menos en inspiración.** Ahí las tarjetas se arrastran a los lados
        // —a la derecha se guarda, a la izquierda se descarta— y el borde
        // izquierdo de la pantalla es donde empieza ese gesto tanto como el de
        // volver. Con los dos vivos, tirar de una tarjeta desde la izquierda
        // sacaba la maleta de la pila en vez de descartar el conjunto.
        .interactivePopEnabled { tab != .inspo }
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
        //         Button { sheet = .style } label: {
        //             Image(systemName: "pencil")
        //         }
        //         .tint(WK.Palette.primaryText)
        //     }
        // }
        // **Flotando, no recortando.** Como la tira del plan: el lienzo llega
        // a los dos bordes y la barra pasa por encima. En `safeAreaInset` le
        // comía su alto al papel de puntos y la maleta dejaba de ser una hoja
        // entera.
        // **Como barra de área segura, no flotando encima.** Así reserva su
        // sitio, igual que la barra de pestañas en el plan, y el scroll de
        // cada pestaña sabe lo que tiene debajo sin que nadie se lo cuente.
        // Lo de antes era `.overlay(alignment: .bottom)`.
        .adaptiveSafeAreaBar(edge: .bottom) {
            HStack(spacing: 12) {
                WKTextTabBar(tabs: [SuitcaseTab.outfits, .packing, .inspo], selection: $tab) { tab in
                    switch tab {
                    case .outfits: String(localized: "suitcases.suitcasedetailscreen.outfits", defaultValue: "Outfits")
                    case .packing: String(localized: "suitcases.suitcasedetailscreen.luggage", defaultValue: "Luggage")
                    case .inspo: String(localized: "suitcases.suitcasedetailscreen.inspo", defaultValue: "Inspo")
                    }
                }
                // La misma medida que cualquier otro botón redondo de la app.
                // Ver `WKCircleButton`.
                WKCircleButton("pencil") { sheet = .style }
                    .tint(WK.Palette.primaryText)
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
            // **Un solo hueco en el centro, siempre puesto**, y lo que va dentro
            // cambia con la pestaña. Eran dos `ToolbarItem` que aparecían y
            // desaparecían, y la barra los recolocaba de cero en cada cambio:
            // a mitad de la transición los días caían encima del botón de
            // volver.
            ToolbarItem(placement: .principal) {
                ZStack {
                    switch tab {
                    case .outfits:
                        // **Los días**, con "sin día" al final. Ver
                        // `TripDayCapsule`.
                        if let dayCount = suitcase.tripDayCount {
                            TripDayCapsule(
                                suitcase: suitcase,
                                dayCount: dayCount,
                                selected: $dayIndex,
                                isInBar: true
                            )
                            // **El ancho que cabe, no uno puesto a ojo.** Ver
                            // `principalWidth`.
                            .frame(width: min(
                                CGFloat(dayCount + 1) * 40 + 8,
                                WKTabBarMetrics.principalWidth(sideButtons: 1)
                            ))
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    case .inspo:
                        // **El tiempo del destino**: tocarlo cambia a dónde
                        // vas, no dónde vives.
                        SuitcaseWeatherPill(suitcase: suitcase) { sheet = .destination }
                            // **Su tamaño, dicho.** Sin él la barra le daba
                            // un hueco más estrecho que lo que se dibuja, y el
                            // toque caía fuera: "Elegir destino" no abría nada.
                            .fixedSize()
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    case .packing:
                        EmptyView()
                    }
                }
                .animation(WKAnimation.content, value: tab)
            }
            // Lo de antes: un `ToolbarItem` por pestaña.
            // // **El tiempo del destino, en el centro.** Como en la pestaña de
            // // inspiración, solo que aquí el sitio es el de la maleta: tocarlo
            // // cambia a dónde vas, no dónde vives.
            // if tab == .inspo {
            //     ToolbarItem(placement: .principal) {
            //         SuitcaseWeatherPill(suitcase: suitcase) { DiagnosticsLog.record("MALETA", "tocar destino"); sheet = .destination }
            //     }
            // }
            // // **Los días y el modo, en la barra.** Con el botón de volver del
            // // sistema a la izquierda, los días en el centro —con "sin día" al
            // // final— y el cambio entre una y dos columnas a la derecha. El
            // // cambio está **siempre**, con fechas y sin ellas: antes iba en el
            // // mismo `if` que los días y en una maleta sin fechas desaparecía.
            // if tab == .outfits {
            //     if let dayCount = suitcase.tripDayCount {
            //         ToolbarItem(placement: .principal) {
            //             TripDayCapsule(
            //                 suitcase: suitcase,
            //                 dayCount: dayCount,
            //                 selected: $dayIndex,
            //                 isInBar: true
            //             )
            //             // **El ancho que cabe, no uno puesto a ojo.** Lo que
            //             // piden los chips o, si es más, lo que queda entre el
            //             // botón de volver y el de modo: pedir más hace que la
            //             // barra lo recorte. Ver `principalWidth`.
            //             .frame(width: min(
            //                 CGFloat(dayCount + 1) * 40 + 8,
            //                 WKTabBarMetrics.principalWidth(sideButtons: 1)
            //             ))
            //         }
            //     }

            if tab == .outfits {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(Self.layoutChange) { layout = layout.next }
                    } label: {
                        // Una columna o dos. Nada de "revista".
                        Image(systemName: layout == .book ? "square.grid.2x2" : "rectangle.portrait")
                            .contentTransition(.symbolEffect(.replace.downUp))
                    }
                    .tint(WK.Palette.primaryText)
                }
            }
        }
        .animation(WKAnimation.content, value: tab)

        // **Una sola hoja.** Eran dos `.sheet` en la misma vista y la de
        // elegir destino se quedaba muda: tocar "Elegir destino" no abría
        // nada. Ver `Sheet`.
        .sheet(item: $sheet) { which in
            switch which {
            case .destination:
                PlaceSearchSheet(title: String(localized: "common.whereAreYouGoing", defaultValue: "Where are you going?")) { place in
                    suitcase.destination = place
                }
            case .style:
                SuitcaseStyleSheet(suitcase: suitcase)
            }
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
    // ChromeCircle(symbol: "pencil") { sheet = .style }
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
            SuitcaseTabButton(title: String(localized: "suitcases.suitcasedetailscreen.outfits", defaultValue: "Outfits"), tab: .outfits, selection: $tab, indicator: indicator)
            SuitcaseTabButton(title: String(localized: "suitcases.suitcasedetailscreen.luggage", defaultValue: "Luggage"), tab: .packing, selection: $tab, indicator: indicator)
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
    /// Revista o rejilla. Llega como enlace porque el botón que lo cambia vive
    /// dentro de la pestaña de outfits, en su tira. Ver `SuitcaseOutfitsFeedTab`.
    @Binding var layout: PlannerLayout
    @Binding var dayIndex: Int
    @Binding var isPickingForPacking: Bool
    let zoom: Namespace.ID
    let onOpenDay: (Int) -> Void
    let onEdit: (Outfit, Bool) -> Void

    var body: some View {
        switch tab {
        case .outfits:
            // **Como el plan**: un lienzo por pantalla, los días de lado y la
            // tarjeta de añadir al final. La pestaña vieja —revista con curl,
            // rejilla con fechas y lista de preparados— sigue en el repositorio
            // sin tocar: volver es poner aquí `SuitcaseOutfitsTab` otra vez.
            // Ver `SuitcaseOutfitsFeedTab`.
            SuitcaseOutfitsFeedTab(
                suitcase: suitcase,
                dayIndex: $dayIndex,
                layout: $layout,
                // Sin huecos a mano: los pone el área segura.
                topInset: 0,
                bottomInset: 0,
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
                // Sin huecos a mano: los pone el área segura.
                topInset: 0,
                bottomInset: 0
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
                Label(String(localized: "suitcases.suitcasedetailscreen.noDates", defaultValue: "No dates"), systemImage: "calendar.badge.exclamationmark")
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
                Text(String(localized: "suitcases.suitcasedetailscreen.ofInTheSuitcase", defaultValue: "\(String(describing: packed)) of \(String(describing: total)) in the suitcase"))
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
        // Toque directo y no `Button`: dentro de la barra, el botón no
        // recibía el toque —"Elegir destino" no abría nada—.
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
            .padding(.vertical, WK.Spacing.s)
            .contentShape(.capsule)
            // Cristal **sin** interacción propia: en la barra el sistema ya
            // pone la suya, y dos capas interactivas se quedaban con el toque
            // —tocar "Elegir destino" no hacía nada—.
            // .adaptiveGlassInteractive(in: .capsule)
            .adaptiveGlass(in: .capsule)
            .onTapGesture(perform: onTap)
            .accessibilityAddTraits(.isButton)
        .task(id: suitcase.destinationName) { await load() }
    }

    private var title: String {
        guard let destination = suitcase.destination else { return String(localized: "suitcases.suitcasedetailscreen.chooseDestination", defaultValue: "Choose destination") }
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
