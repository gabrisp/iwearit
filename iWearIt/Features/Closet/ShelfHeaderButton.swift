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

    var body: some View {
        NavigationLink(value: ClosetRoute.category(slug: slug, name: name)) {
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
        .buttonStyle(WKPressStyle())
    }
}

/// Destinos de navegación del armario. `Hashable` y de valor, para que el
/// `NavigationStack` los pueda serializar y restaurar.
enum ClosetRoute: Hashable {
    case category(slug: String, name: String)
    case suitcase(id: UUID)
}
