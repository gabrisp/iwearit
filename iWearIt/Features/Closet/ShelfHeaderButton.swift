import SwiftUI
import WKDesign

/// Cabecera de balda. Tocarla abre la categoría en vertical.
///
/// Vista propia porque la usan tanto `ShelfSection` como
/// `SuitcaseShelfSection`: si estuviera inline en el `@ViewBuilder` de cada una,
/// sería la misma UI escrita dos veces.
struct ShelfHeaderButton: View {
    let slug: String
    let name: String
    let symbol: String?
    let count: Int
    /// A dónde lleva.
    ///
    /// Parámetro y no un enlace por fuera: envolver esta vista en otro
    /// `NavigationLink` anida dos enlaces, y el de dentro se come el toque. Es
    /// exactamente lo que dejó muerto el botón de Ajustes.
    var route: ClosetRoute?

    private var destination: ClosetRoute {
        route ?? .category(slug: slug, name: name)
    }

    var body: some View {
        NavigationLink(value: destination) {
            ShelfHeaderLabel(name: name, count: count)
        }
        .buttonStyle(WKPressStyle())
    }
}

/// Cómo se ve la cabecera de una balda.
///
/// Separada del enlace porque **no siempre lleva al mismo sitio**: en el
/// armario empuja una `ClosetRoute`, y en la hoja de crear outfit empuja la
/// balda dentro de la propia hoja. Lo que no puede cambiar es el aspecto: una
/// balda tiene que verse igual la abras desde donde la abras, y teniendo cada
/// sitio su propia cabecera acabaron siendo dos cosas distintas.
struct ShelfHeaderLabel: View {
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: WK.Spacing.xs) {
            Text(name)
                .font(WK.Font.shelfTitle)
                .foregroundStyle(WK.Palette.primaryText)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WK.Palette.secondaryText)
            Spacer()
            Text(count.formatted())
                .font(.footnote)
                .foregroundStyle(WK.Palette.secondaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.s)
        .contentShape(.rect)
    }
}

/// Destinos de navegación del armario. `Hashable` y de valor, para que el
/// `NavigationStack` los pueda serializar y restaurar.
enum ClosetRoute: Hashable {
    /// Ajustes. **Empujado, no en hoja**: es una pantalla más de la app —con
    /// sus secciones, su scroll y sus propias subpantallas— y meterla en una
    /// hoja la dejaba sin barra de navegación propia y sin sitio al que
    /// empujar nada desde dentro.
    case settings
    case category(slug: String, name: String)
    case suitcase(id: UUID)
    /// Todas las maletas. La cabecera del altillo prometía abrirse —tenía
    /// chevron— y estaba desactivada.
    case suitcases
    /// Las prendas marcadas con el corazón, de todas las baldas.
    case favourites
}
