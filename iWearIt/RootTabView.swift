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

    /// Selección de pestaña. Es el único estado de esta vista.
    @State private var selection: RootTab = .initialFromLaunchArguments

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
    func rootTabBar(selection: Binding<RootTab>) -> some View {
        adaptiveSafeAreaBar(edge: .bottom) {
            WKIconTabBar(
                tabs: [RootTab.closet, .planner],
                selection: selection
            ) { tab in
                switch tab {
                case .closet: "cabinet"
                case .planner: "calendar"
                case .profile: "person.crop.circle"
                }
            }
        }
    }
}

#Preview {
    RootTabView()
}
