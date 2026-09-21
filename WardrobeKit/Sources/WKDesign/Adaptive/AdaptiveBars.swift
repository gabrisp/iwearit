import SwiftUI

// Barras: tab bar, accesorio inferior y bordes de scroll.

public extension View {

    /// Barra global de ancho completo por encima de la tab bar.
    ///
    /// - Warning: una vez aplicado, **el contenedor pinta su superficie de
    ///   cristal aunque el contenido esté vacío**, así que devolver `EmptyView`
    ///   deja una cápsula vacía flotando. Y aplicarlo de forma condicional
    ///   cambia la identidad del `TabView`, que se reconstruiría entero
    ///   perdiendo scroll y pilas de navegación. Conclusión: úsalo solo para
    ///   algo que deba estar presente en **todas** las pestañas — el caso real
    ///   es la barra de progreso del escaneo en F8.
    ///
    ///   Para un CTA de una sola pantalla, `adaptiveFloatingAccessory`.
    @ViewBuilder
    func adaptiveBottomAccessory<Accessory: View>(
        @ViewBuilder _ accessory: @escaping () -> Accessory
    ) -> some View {
        if #available(iOS 26, *) {
            self.tabViewBottomAccessory(content: accessory)
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) { accessory() }
        }
    }

    /// Píldora flotante anclada al fondo de **una** pantalla.
    ///
    /// Va sobre el contenido, no sobre el `TabView`, así que aparece y
    /// desaparece con la pantalla sin tocar la identidad de nada. `safeAreaInset`
    /// además reserva el hueco, de modo que el scroll no queda tapado.
    ///
    /// No impone superficie: el contenido trae la suya (normalmente
    /// `adaptiveGlassInteractive(in: .capsule)`), porque una píldora y una barra
    /// no quieren la misma forma.
    func adaptiveFloatingAccessory<Accessory: View>(
        @ViewBuilder _ accessory: @escaping () -> Accessory
    ) -> some View {
        // **Por dentro de la barra de pestañas.**
        //
        // No hay que reservarle hueco a mano: la barra es ahora otro
        // `safeAreaInset`, puesto por fuera de este, así que el sistema apila
        // los dos y el accesorio queda justo encima de ella. Antes la barra
        // flotaba en un `overlay` que no empujaba nada y había que adivinar su
        // alto —y me quedaba corto, que es lo que dejaba "Crear outfits" medio
        // tapado.
        safeAreaInset(edge: .bottom, spacing: 0) {
            accessory()
                // Un pelo de aire sobre la barra. `safeAreaInset` los apila
                // pegados, y pegados se leen como una sola pieza partida en
                // dos en vez de como el botón de esta pantalla y, debajo, los
                // destinos de la app.
                .padding(.bottom, WK.Spacing.s)
        }
    }

    /// Barra anclada a un borde de la pantalla.
    ///
    /// En iOS 26 usa `safeAreaBar`, que es lo que hace que el contenido que
    /// pasa por debajo se difumine solo y que la barra flote como el resto del
    /// cromo del sistema. En iOS 18 cae a `safeAreaInset`, que reserva el mismo
    /// hueco aunque sin el desenfoque.
    ///
    /// En los dos casos **reserva espacio**, que es lo que evita que el
    /// contenido quede cortado por debajo de la barra.
    @ViewBuilder
    func adaptiveSafeAreaBar<Bar: View>(
        edge: VerticalEdge,
        spacing: CGFloat? = nil,
        @ViewBuilder _ bar: @escaping () -> Bar
    ) -> some View {
        if #available(iOS 26, *) {
            self.safeAreaBar(edge: edge, spacing: spacing, content: bar)
        } else {
            self.safeAreaInset(edge: edge, spacing: spacing, content: bar)
        }
    }

    /// La tab bar se encoge al bajar. No hay equivalente en iOS 18: se ignora,
    /// que es la degradación correcta — la barra simplemente no se minimiza.
    ///
    /// - Warning: **no se usa en esta app, y es deliberado.** Con tres
    ///   pestañas la barra ya ocupa poco, y encogerla al hacer scroll significa
    ///   que el destino de un toque cambia de sitio mientras el dedo va hacia
    ///   él. Se deja el modificador porque la rama de iOS 18 está resuelta y
    ///   volver a escribirla el día que haga falta es trabajo repetido.
    @ViewBuilder
    func adaptiveTabBarMinimize() -> some View {
        if #available(iOS 26, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    /// Difuminado del contenido bajo las barras del sistema.
    ///
    /// En iOS 18 se imita con una máscara de degradado en el borde superior.
    /// Sin esto, las prendas de la primera balda pasan por detrás del título y
    /// se lee fatal.
    @ViewBuilder
    func adaptiveScrollEdge(_ edges: Edge.Set = .top) -> some View {
        if #available(iOS 26, *) {
            self.scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
        }
    }
}

public extension View {
    /// Un carrusel horizontal que **no recorta lo que sobresale**.
    ///
    /// Un `ScrollView` horizontal dentro de un contenedor con márgenes corta
    /// por los lados, y justo ahí es donde vive lo que se sale: el aro del chip
    /// elegido, la sombra de una miniatura, el crecer al pulsar. Se ven
    /// cortados en el primero y en el último, que son los dos que más se miran.
    ///
    /// La solución es sacar el scroll **fuera** del margen y devolvérselo a su
    /// contenido por dentro: el recorte cae entonces en el borde de la pantalla
    /// —donde no molesta— y el margen lo sigue poniendo el contenido, así que
    /// nada se mueve de sitio.
    ///
    /// - Important: el contenido del scroll tiene que llevar el **mismo**
    ///   margen por dentro (`.padding(.horizontal, inset)` en su `HStack`), o
    ///   el primer elemento aparece pegado al canto.
    func wkBleedingStrip(_ inset: CGFloat = WK.Spacing.screenInset) -> some View {
        padding(.horizontal, -inset)
    }
}
