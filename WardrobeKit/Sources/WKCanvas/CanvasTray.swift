import SwiftUI
import WKCore
import WKDesign

/// La bandeja de abajo del editor: de dónde salen las cosas.
///
/// Es **una sola bandeja con pestañas** y no cuatro botones que abren cuatro
/// hojas. Montar un outfit es ir y venir entre prendas y stickers docenas de
/// veces, y cerrar y abrir una hoja en cada salto convierte cinco segundos de
/// trabajo en cinco segundos de animaciones.
public struct CanvasTray: View {
    public enum Tab: String, CaseIterable, Sendable {
        case garments = "Prendas"
        case stickers = "Stickers"

        // "Outfits" y "Pruebas", comentadas y no borradas. La primera enseñaba
        // "aún no hay outfits" y la segunda esperaba al try-on: una pestaña
        // que solo sabe decir que no hay nada ocupa su parte de la bandeja y
        // enseña a no mirar ahí.
        // case outfits = "Outfits"
        // case tryOns = "Pruebas"
    }

    /// Las pestañas, o `nil` cuando la tarjeta enseña otra cosa —el color del
    /// fondo, por ejemplo—. Sin enlace no se dibuja la fila: unas pestañas de
    /// "Prendas / Stickers" encima del selector de color no llevan a ninguna
    /// parte.
    private let tab: Binding<Tab>?
    private let content: AnyView

    /// Alto de los controles flotantes del editor.
    ///
    /// **Uno solo para todos.** "Agregar", el círculo del color y la barra de
    /// herramientas de la prenda seleccionada viven en el mismo sitio y se
    /// turnan; con cada uno a su altura, cambiar de estado movía el cristal
    /// arriba y abajo unos puntos y se leía como un salto.
    public static let controlHeight: CGFloat = 44

    /// Alto de partida, hasta que se mide el contenido de verdad.
    ///
    /// Solo vive un fotograma: en cuanto la bandeja se dibuja, su altura real
    /// sustituye a esta. Pero tiene que ser algo razonable — con cero, la hoja
    /// aparece como una raya y luego da un salto.
    public static let initialHeight: CGFloat = 300

    /// Si la tarjeta **llena** la hoja en vez de medir lo que lleva dentro.
    ///
    /// Con prendas sí: la rejilla tiene que poder crecer cuando subes la hoja,
    /// que es de lo que va poder subirla. Con stickers o con el color, no: son
    /// cuatro cosas y estirarlas deja un palmo de vacío debajo.
    private let fills: Bool

    public init(
        tab: Binding<Tab>? = nil,
        fills: Bool = false,
        @ViewBuilder content: () -> some View
    ) {
        self.tab = tab
        self.fills = fills
        self.content = AnyView(content())
    }

    public var body: some View {
        VStack(spacing: WK.Spacing.m) {
            // El asidero. No es decoración: es lo que dice que esto se
            // arrastra, y sin él nadie lo intenta.
            Capsule()
                .fill(WK.Palette.ink(0.22))
                .frame(width: 36, height: 5)

            if let tab {
                CanvasTrayTabs(selection: tab)
            }
            content
                .frame(maxWidth: .infinity)
                // El cambio de pestaña cambia el alto de la hoja. Animarlo aquí
                // es lo que hace que la bandeja **crezca** de prendas a
                // stickers en vez de dar un salto y reaparecer con otro tamaño.
                .animation(WKAnimation.arrival, value: tab?.wrappedValue)
                .transition(.opacity)
        }
        .padding(.top, WK.Spacing.s)
        // **Ni fondo ni márgenes.** Ni cristal, ni material, ni tarjeta: lo
        // único que se ve aquí es el asidero, las pestañas y las prendas,
        // flotando sobre el lienzo. Cualquier superficie —por translúcida que
        // sea— parte la pantalla en dos y tapa justo el outfit que se está
        // montando, que es lo que hay que estar viendo mientras se elige la
        // prenda siguiente.
        //
        // La hoja tampoco pinta nada: se presenta con el fondo transparente
        // (ver `canvasTraySheet`), así que lo que hay detrás es el propio
        // lienzo, vivo y tocable.
        .modifier(CanvasTrayFit(fills: fills))
    }
}

/// Estirar o medir, según lo que lleve dentro. Ver `CanvasTray.fills`.
private struct CanvasTrayFit: ViewModifier {
    let fills: Bool

    func body(content: Content) -> some View {
        if fills {
            content.frame(maxHeight: .infinity, alignment: .top)
        } else {
            // Mide lo que mide su contenido, y esa medida es el alto de la
            // hoja. Forzándola a llenar el detent, la hoja mandaría sobre la
            // tarjeta en vez de al revés.
            content.fixedSize(horizontal: false, vertical: true)
        }
    }
}

public extension View {
    /// Presenta la bandeja como hoja, **del alto de su contenido** y sin el
    /// panel de la hoja.
    ///
    /// Tres cosas y cada una hace falta:
    ///
    /// - `presentationBackground(.clear)` es una excepción consciente a la
    ///   regla de no tocar el fondo de las hojas en iOS 26: aquí lo que tiene
    ///   que verse es la tarjeta de cristal, y el panel del sistema la taparía
    ///   con una superficie opaca del tamaño del detent.
    /// - `presentationBackgroundInteraction(.enabled)` es lo que la separa de
    ///   una hoja normal: el lienzo de debajo **sigue vivo**. Montar un outfit
    ///   es ir y venir entre la bandeja y el lienzo docenas de veces, y una
    ///   hoja que bloquea lo de atrás convierte cada salto en abrir y cerrar.
    /// - Y el detent sale de **medir el contenido**, no de un número. Con uno
    ///   fijo, los stickers —que son una fila de cuatro— ocupaban lo mismo que
    ///   la rejilla entera de prendas, y debajo quedaba un palmo de nada.
    /// - Parameter height: lo que mide la bandeja, **hacia fuera**.
    ///
    ///   Es lo que permite que el editor se aparte: una hoja no empuja nada de
    ///   lo que hay detrás, así que quien presenta se reserva ese hueco por su
    ///   cuenta con un `Color.clear` del mismo alto. Sin esto, la bandeja tapa
    ///   los botones del editor en vez de levantarlos, que es lo que hacía la
    ///   versión de antes cuando vivía dentro del layout.
    /// - Parameter isExpandable: si el usuario puede **subir** la hoja.
    ///
    ///   Con prendas, sí: el alto de partida enseña dos filas y subiendo se ven
    ///   más de golpe. Y el hueco que se reserva en el editor **no cambia** al
    ///   subirla — se queda en el de partida —, porque lo que se aparta son los
    ///   botones del editor y esos no tienen por qué irse al techo solo porque
    ///   estés mirando el armario.
    func canvasTraySheet<Content: View>(
        isPresented: Binding<Bool>,
        height: Binding<CGFloat>,
        isExpandable: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(
            CanvasTraySheet(
                isPresented: isPresented,
                height: height,
                isExpandable: isExpandable,
                sheetContent: content
            )
        )
    }
}

private struct CanvasTraySheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    /// Lo que mide la bandeja, compartido con quien la presenta.
    @Binding var height: CGFloat
    let isExpandable: Bool
    @ViewBuilder var sheetContent: () -> SheetContent

    /// A qué altura está puesta **ahora mismo**.
    ///
    /// Con enlace y no dejándoselo al sistema: es lo que permite devolverla a
    /// su sitio al cambiar de pestaña sin cerrarla ni volver a presentarla.
    @State private var detent: PresentationDetent = .height(CanvasTray.initialHeight)

    /// Alto de partida cuando la hoja se puede subir.
    ///
    /// Fijo y no medido, y es la diferencia entre poder subirla o no: si el
    /// alto saliera de medir el contenido, al estirarse la rejilla crecería la
    /// medida, la medida movería el detent y el detent volvería a estirar la
    /// rejilla. La hoja se perseguiría a sí misma hasta el techo.
    static var expandableBase: CGFloat { 320 }

    /// El alto de partida de lo que haya puesto dentro.
    private var base: CGFloat {
        isExpandable ? Self.expandableBase : height
    }

    /// **Solo las prendas se pueden estirar.**
    ///
    /// Es lo único que tiene más contenido del que cabe. Los stickers son
    /// cuatro iconos, la pintura son tres controles y el color son diez
    /// muestras: darles un detent grande deja media pantalla vacía debajo y
    /// encima invita a estirarlos para no ver nada nuevo.
    private var detents: Set<PresentationDetent> {
        isExpandable ? [.height(base), .large] : [.height(base)]
    }

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            sheetContent()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured in
                    // Solo se mide lo que de verdad manda sobre su alto. Con
                    // prendas el hueco es siempre el de partida: subir la hoja
                    // enseña más armario, no empuja más el editor.
                    guard !isExpandable else { return }
                    // El medio punto de margen evita el bucle: medir cambia el
                    // detent, el detent cambia el tamaño disponible, y sin
                    // histéresis los dos se persiguen fotograma a fotograma.
                    guard measured > 0, abs(measured - height) > 0.5 else { return }
                    height = measured
                }
                .presentationDetents(detents, selection: $detent)
                .presentationBackground(.clear)
                // El asidero lo dibuja la bandeja: con los dos, salen dos.
                .presentationDragIndicator(.hidden)
                // **Sin atenuar nada, a ninguna altura.**
                //
                // Con `upThrough:`, la capa oscura del sistema volvía en
                // cuanto la hoja pasaba de esa altura: se veía un velo sobre
                // el lienzo por el mero hecho de haber una hoja puesta. Aquí
                // no hay nada encima del lienzo en ningún momento, y además
                // sigue estando vivo y tocable, que es lo que permite ir y
                // venir entre la bandeja y el outfit sin cerrar nada.
                .presentationBackgroundInteraction(.enabled)
                // Volver al alto de partida al cambiar de pestaña, **animado**:
                // es la misma bandeja creciendo o encogiendo, no otra hoja.
                .onChange(of: base) { _, new in
                    withAnimation(.snappy(duration: 0.28)) { detent = .height(new) }
                }
                .onAppear { detent = .height(base) }
        }
    }
}

/// Las pestañas. Vista propia con su `@Namespace`: el indicador se mueve entre
/// pestañas en vez de aparecer y desaparecer, que es lo que hace que se lea
/// como una selección y no como dos cosas distintas.
private struct CanvasTrayTabs: View {
    @Binding var selection: CanvasTray.Tab
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: WK.Spacing.xs) {
            ForEach(CanvasTray.Tab.allCases, id: \.self) { tab in
                CanvasTrayTab(
                    tab: tab,
                    isSelected: selection == tab,
                    indicator: indicator
                ) {
                    withAnimation(WKAnimation.selection) { selection = tab }
                }
            }
        }
        .padding(.horizontal, WK.Spacing.m)
    }
}

private struct CanvasTrayTab: View {
    let tab: CanvasTray.Tab
    let isSelected: Bool
    let indicator: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tab.rawValue)
                .font(WK.Font.captionMedium)
                .foregroundStyle(isSelected ? WK.Palette.primaryText : WK.Palette.secondaryText)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .frame(maxWidth: .infinity)
                .background {
                    if isSelected {
                        // Tinta translúcida y no el color de la app: sobre el
                        // lienzo, un relleno opaco se lee como un parche
                        // pegado encima.
                        Capsule()
                            .fill(WK.Palette.ink(0.10))
                            .matchedGeometryEffect(id: "tray-tab", in: indicator)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
    }
}

/// Las cuatro cosas que se pueden pegar.
public struct StickerPicker: View {
    private let onPick: (CanvasSticker.Kind) -> Void

    public init(onPick: @escaping (CanvasSticker.Kind) -> Void) {
        self.onPick = onPick
    }

    public var body: some View {
        HStack(spacing: WK.Spacing.m) {
            StickerTile(symbol: "photo", label: String(localized: "common.photo", defaultValue: "Photo", bundle: .module)) { onPick(.photo) }
            StickerTile(symbol: "calendar", label: String(localized: "wkcanvas.canvastray.date", defaultValue: "Date", bundle: .module)) { onPick(.date) }
            StickerTile(symbol: "textformat", label: String(localized: "wkcanvas.canvastray.text", defaultValue: "Text", bundle: .module)) { onPick(.text) }
            StickerTile(symbol: "cloud.sun", label: String(localized: "wkcanvas.canvastray.weather", defaultValue: "Weather", bundle: .module)) { onPick(.weather) }
        }
        .padding(.horizontal, WK.Spacing.m)
    }
}

private struct StickerTile: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: WK.Spacing.s) {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(WK.Palette.primaryText)
                    .frame(width: 64, height: 64)
                    .background(
                        WK.Palette.ink(0.08),
                        in: .rect(cornerRadius: WK.Radius.medium, style: .continuous)
                    )
                Text(label)
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
            }
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}
