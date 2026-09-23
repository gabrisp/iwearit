import SwiftUI
import WKDesign

/// Dos pestañas: Armario · Plan.
///
/// **El perfil tampoco es pestaña**: es un botón arriba a la izquierda del
/// armario. Ajustes, estado de los modelos y suscripción se visitan de vez en
/// cuando, y gastar un tercio de la barra permanente en eso deja menos sitio
/// para lo que sí se usa a diario.
///
/// Las **maletas** tampoco: viven como balda "altillo" al final del Armario.
/// Encaja con la metáfora del armario real y evita una pestaña que la mayoría
/// de usuarios tocaría dos veces al año.
struct RootTabView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    /// Selección de pestaña.
    @State private var selection: RootTab = .initialFromLaunchArguments
    /// Quién presenta las hojas. Ver `AppRouter`.
    @State private var router = AppRouter()
    /// Qué raíces de pestaña están en pantalla, para saber si la barra se ve.
    // @State private var chrome = TabBarChrome()

    var body: some View {
        // La barra nativa se esconde y se pone la propia: iconos sin texto,
        // como en Lockty. Con dos destinos la etiqueta no aporta y obliga a una
        // barra más alta que se come contenido en todas las pantallas.
        //
        // ## Dónde se dibuja la barra propia
        //
        // **Aquí no.** La pone cada pantalla en la raíz de su propia pila de
        // navegación, con `rootTabBar(selection:)`. Puesta aquí como `overlay`
        // del `TabView` flotaba por encima de **todo**, incluidas las pantallas
        // empujadas: abrir una maleta dejaba la barra de pestañas encima del
        // detalle, que no es donde va. Dentro de la pila, empujar una pantalla
        // la tapa como tapa cualquier otra cosa, que es lo que hace el sistema
        // con la barra nativa y lo que se espera al abrir una maleta.
        TabView(selection: $selection) {
            // El modificador va en **el contenido de cada pestaña**, no en el
            // `TabView`: puesto fuera no esconde nada, y la barra nativa se
            // quedaba asomando por debajo de la nuestra.
            Tab(value: RootTab.closet) {
                ClosetScreen(tab: $selection)
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab(value: RootTab.planner) {
                PlannerScreen(tab: $selection)
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
        }
        // Y en el propio `TabView` además de en cada pestaña. Ninguno de los
        // dos sitios basta por sí solo en todas las versiones, y que asome un
        // resto de la barra nativa por debajo de la nuestra se ve fatal.
        .toolbarVisibility(.hidden, for: .tabBar)
        // Una sola vez en la raíz: `scrollIndicators` se propaga por el árbol,
        // así que la regla vale también para las pantallas que aún no existen.
        // **Una sola barra, por encima de las dos pestañas.**
        //
        // Antes cada pantalla dibujaba la suya: al cambiar de pestaña
        // aparecía **la otra copia**, que durante un instante enseñaba todavía
        // la pestaña de antes y luego saltaba a la nueva. Ese era el parpadeo
        // de los iconos. Con una sola, la píldora viaja de un icono al otro y
        // no hay nada que saltar.
        //
        // Cada pantalla sigue reservando el hueco —ver `rootTabBar`— y avisa
        // de cuándo está en la raíz: al empujar una pantalla encima, la barra
        // se va, igual que antes se iba tapada.
        // **Vuelve a ir una por pantalla raíz**, y ahora es la de Lockty tal
        // cual (`WKLocktyTabBar`). Con la barra dentro de la pila de cada
        // pestaña, una pantalla empujada la tapa: no se funde ni desaparece.
        // La barra única de encima se queda comentada:
        // .overlay(alignment: .bottom) {
        //     if chrome.visibleRoots.contains(selection) {
        //         WKIconTabBar(tabs: [RootTab.closet, .planner], selection: $selection) { tab in
        //             switch tab {
        //             case .closet: "cabinet"
        //             case .planner: "calendar"
        //             case .profile: "person.crop.circle"
        //             }
        //         }
        //         .transition(.opacity)
        //     }
        // }
        // .animation(.smooth(duration: 0.25), value: chrome.visibleRoots.contains(selection))
        .environment(router)
        // **La ficha de una prenda, aquí.** Presentada por su percha se iba con
        // ella en cuanto la prenda salía de la lista. Ver `AppRouter`.
        .sheet(item: $router.garment) { garment in
            GarmentDetailLoader(persistentID: garment.persistentID)
        }
        // **La inspiración, también desde aquí.** Ver `AppRouter`.
        .sheet(isPresented: $router.isShowingInspo) {
            InspoSheet(feed: appEnvironment.inspo)
        }
        .ignoresSafeArea(.keyboard)
        // .environment(chrome)
        .featureGatePaywall(appEnvironment.gate)
        // **Los avisos, aquí arriba y una sola vez.** Puestos dentro de una
        // pantalla se irían con ella al empujar la siguiente, y los que salen
        // sobre una hoja quedarían por debajo. Ver `wkTipLayer`.
        .wkTipLayer(appEnvironment.tips)
        // Y el centro en el entorno, para que los propios gestos —el tirón,
        // el arrastre— den su aviso por aprendido sin que cada pantalla tenga
        // que acordarse de hacerlo.
        .environment(appEnvironment.tips)
        .scrollIndicators(.hidden)
    }
}

enum RootTab: Hashable {
    case closet, planner, profile

    /// En Debug, `-tab profile` arranca en esa pestaña. Sirve para capturar
    /// cualquier pantalla sin tener que tocarla.
    static var initialFromLaunchArguments: RootTab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
            switch args[i + 1] {
            case "planner": return .planner
            case "profile": return .profile
            default: break
            }
        }
        #endif
        return .closet
    }
}

extension View {
    /// La barra de pestañas, **dentro** de la pila de navegación de la pantalla
    /// que la pone.
    ///
    /// Se aplica a la raíz de la pila, nunca a un destino: es justo eso lo que
    /// hace que una pantalla empujada —el detalle de una maleta, el editor de
    /// un outfit— la tape, en vez de quedarse por debajo de una barra que sigue
    /// flotando encima de algo que ya no es una pestaña.
    ///
    /// `adaptiveSafeAreaBar` y no un `overlay`: además de dibujarla, reserva su
    /// hueco, de modo que el scroll no queda cortado por debajo y el accesorio
    /// flotante de la pantalla se apila justo encima sin cuentas a mano.
    /// - Parameter isHidden: la barra se va y deja el hueco libre. Lo usa el
    ///   modo de edición en bloque del armario, que pone ahí sus acciones.
    func rootTabBar(
        _ tab: RootTab,
        selection: Binding<RootTab>,
        isHidden: Bool = false,
        onAssistant: (() -> Void)? = nil,
        onPlus: @escaping () -> Void
    ) -> some View {
        modifier(
            RootTabBarSlot(
                tab: tab,
                selection: selection,
                isHidden: isHidden,
                onAssistant: onAssistant,
                onPlus: onPlus
            )
        )
    }
}

/// Qué raíces de pestaña están en pantalla ahora mismo.
@MainActor
@Observable
final class TabBarChrome {
    var visibleRoots: Set<RootTab> = []
}

/// El hueco de la barra en una pantalla raíz, y el aviso de que está a la vista.
///
/// La barra de verdad la dibuja `RootTabView`, una sola para todas. Aquí se
/// reserva su sitio —para que el scroll no quede debajo y los accesorios se
/// apilen encima sin cuentas a mano— con una vista transparente del mismo
/// tamaño.
private struct RootTabBarSlot: ViewModifier {
    let tab: RootTab
    @Binding var selection: RootTab
    var isHidden = false
    /// Qué hace el botón de la derecha. `nil` = lo de siempre, abrir la
    /// inspiración; una pantalla puede quedárselo para otra cosa sin que haya
    /// que tocar la barra.
    let onAssistant: (() -> Void)?
    let onPlus: () -> Void

    /// Quién presenta la hoja. Ver `AppRouter`.
    @Environment(AppRouter.self) private var router

    /// `morphingBottomBar` de Lockty: la barra a la izquierda y los dos
    /// círculos —la carita y el "+"— a la derecha.
    func body(content: Content) -> some View {
        content
            .adaptiveSafeAreaBar(edge: .bottom) {
                if isHidden {
                    // Nada, y sin reservar sitio: quien la esconde pone algo
                    // suyo en su lugar.
                    Color.clear.frame(height: 0)
                } else {
                HStack(alignment: .bottom, spacing: 12) {
                    // **El hueco del botón, a la izquierda.** Sin él, la barra
                    // se iría hacia la izquierda justo lo que ocupa el círculo
                    // de la derecha: con el hueco, la barra queda centrada en
                    // la pantalla y el botón en el borde, que es donde estaba
                    // en Lockty.
                    Color.clear
                        .frame(width: 52, height: 1)
                        .allowsHitTesting(false)

                    Spacer(minLength: 0)

                    WKLocktyTabBar(tabs: [RootTab.closet, .planner], home: tab, selection: $selection) { tab in
                        switch tab {
                        case .closet: "cabinet"
                        case .planner: "calendar"
                        case .profile: "person.crop.circle"
                        }
                    }
                    .sensoryFeedback(.selection, trigger: selection)

                    Spacer(minLength: 0)

                    // El de Lockty, en su sitio de siempre: abre la
                    // inspiración. La carita se queda comentada por si vuelve.
                    Button { (onAssistant ?? router.openInspo)() } label: {
                        Image(systemName: "sparkles")
                            .font(.body.weight(.medium))
                            .foregroundStyle(WK.Palette.primaryText)
                            .frame(width: 52, height: 52)
                            .contentShape(Circle())
                    }
                    .buttonStyle(WKPlainGlassButtonStyle(shape: Circle()))

                    // Button(action: onAssistant) {
                    //     Text("🙂")
                    //         .font(.system(size: 22))
                    //         .frame(width: 52, height: 52)
                    //         .contentShape(Circle())
                    // }
                    // .buttonStyle(WKPlainGlassButtonStyle(shape: Circle()))

                    // Button(action: onPlus) {
                    //     Image(systemName: "plus")
                    //         .font(.body.weight(.light))
                    //         .foregroundStyle(WK.Palette.primaryText)
                    //         .frame(width: 52, height: 52)
                    //         .contentShape(Circle())
                    // }
                    // .buttonStyle(WKPlainGlassButtonStyle(shape: Circle()))
                }
                .padding(.horizontal, 20)
                .transition(.opacity)
                }
            }
    }
}

// El hueco transparente de cuando la barra era una sola encima del `TabView`.
//
// private struct RootTabBarSlot: ViewModifier {
//     let tab: RootTab
//     @Environment(TabBarChrome.self) private var chrome
//
//     func body(content: Content) -> some View {
//         content
//             .adaptiveSafeAreaBar(edge: .bottom) {
//                 Color.clear
//                     .frame(height: WKTabBarMetrics.barHeight + 2 * WK.Spacing.xs)
//                     .allowsHitTesting(false)
//             }
//             .onAppear { chrome.visibleRoots.insert(tab) }
//             .onDisappear { chrome.visibleRoots.remove(tab) }
//     }
// }

#Preview {
    RootTabView()
}
