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
    case outfits, packing
}

/// El contenido real. Separado para poder usar `@Bindable` sobre una maleta que
/// ya sabemos que existe, sin desenvolver opcionales en el `@ViewBuilder`.
private struct SuitcaseContent: View {
    @Bindable var suitcase: Suitcase
    @State private var tab: SuitcaseTab = .outfits
    @State private var dayIndex = 0
    @State private var isPresentingStyle = false
    /// El outfit que se está editando. Vive **aquí**, que es donde está la
    /// pila de navegación: las páginas del pager viven en sus propios
    /// controladores y desde ahí no se puede empujar nada.
    @State private var editingOutfit: Outfit?
    /// Para que el editor crezca desde el lienzo que ya se está viendo.
    @Namespace private var zoom

    @Environment(AppEnvironment.self) private var appEnvironment

    @Environment(\.dismiss) private var dismiss

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
                dayIndex: $dayIndex,
                zoom: zoom,
                onEdit: { editingOutfit = $0 }
            )
                .transition(.wkContent)
                .id(tab)
                .animation(WKAnimation.content, value: tab)
        }
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Sección", selection: $tab) {
                    Text("Outfits").tag(SuitcaseTab.outfits)
                    Text("Equipaje").tag(SuitcaseTab.packing)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isPresentingStyle = true } label: {
                    Image(systemName: "pencil")
                }
                .tint(WK.Palette.primaryText)
            }
        }
        // La barra de pestañas de la app estorba aquí: dentro de una maleta se
        // está montando contenido a pantalla completa, y tener debajo los tres
        // destinos de la app invita a salirse a mitad.
        .toolbarVisibility(.hidden, for: .tabBar)
        // Debajo de la barra, la tira de días: **solo** en Outfits. En Equipaje
        // no hay días —es una lista de lo que va dentro— y enseñar un selector
        // que no cambia nada promete una relación que no existe.
        .safeAreaInset(edge: .top) {
            if tab == .outfits, let dayCount = suitcase.tripDayCount {
                TripDayBar(suitcase: suitcase, dayCount: dayCount, selected: $dayIndex)
                    .padding(.bottom, WK.Spacing.xs)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(WKAnimation.content, value: tab)
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
            AdvancedCanvasScreen(outfit: outfit, store: appEnvironment.imageStore)
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

    private var tintColor: Color {
        guard
            let raw = suitcase.colorRaw,
            let tint = SuitcaseTint(rawValue: raw)
        else { return WK.Palette.canvas }
        return Color(red: tint.components.red, green: tint.components.green, blue: tint.components.blue)
            .opacity(0.35)
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
    @Binding var dayIndex: Int
    let zoom: Namespace.ID
    let onEdit: (Outfit) -> Void

    var body: some View {
        switch tab {
        case .outfits:
            SuitcaseOutfitsTab(
                suitcase: suitcase, dayIndex: $dayIndex, zoom: zoom, onEdit: onEdit
            )
        case .packing:
            PackingChecklistTab(suitcase: suitcase)
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
