import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// El "altillo": la última balda del armario, con las maletas.
///
/// Las maletas **no son pestaña**. Viven aquí porque encaja con la metáfora del
/// armario real y porque una pestaña que la mayoría de usuarios toca dos veces
/// al año no se gana su sitio en la barra.
///
/// Reutiliza `ShelfHeaderButton` y `ShelfPlank` tal cual; solo cambia el
/// contenido del scroll. Por eso es una vista aparte y no una rama dentro de
/// `ShelfSection`: sería repetir UI dentro de un `@ViewBuilder`.
struct SuitcaseShelfSection: View {
    @Query(FetchDescriptor<Suitcase>.visibleSuitcases())
    private var suitcases: [Suitcase]

    @State private var isPresentingNew = false
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Abre la balda entera, como cualquier otra. Estaba desactivada:
            // el chevron prometía algo que no pasaba.
            ShelfHeaderButton(
                slug: "__suitcases__",
                name: "Maletas",
                symbol: "suitcase",
                count: suitcases.count,
                route: .suitcases
            )

            ScrollView(.horizontal) {
                LazyHStack(alignment: .bottom, spacing: WK.Spacing.m) {
                    ForEach(suitcases) { suitcase in
                        SuitcaseCard(suitcase: suitcase)
                    }
                    NewSuitcaseCard {
                        // La puerta vive aquí y no dentro de la hoja: abrir un
                        // formulario para bloquearlo al guardar es hacer perder
                        // el tiempo al usuario.
                        appEnvironment.gate.require(.suitcases) { isPresentingNew = true }
                    }
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                // **Aire entre las maletas y la balda.** Con el nombre
                // debajo, la fila llegaba pegada al tablón.
                .padding(.bottom, WK.Spacing.l)
                .frame(height: WK.Shelf.height + WK.Spacing.l, alignment: .bottom)
            }
            .scrollIndicators(.hidden)

            ShelfPlank()
        }
        // El mismo margen que las demás baldas. El aire de más que llevaba
        // —para despegarla del botón flotante— se notaba como un salto: es la
        // única balda que medía distinto. Lo que hace falta debajo lo pone el
        // scroll, que ya reserva el hueco de la barra.
        .padding(.bottom, WK.Spacing.l)
        .sheet(isPresented: $isPresentingNew) { NewSuitcaseSheet() }
    }
}

/// Maleta semi-realista: cuerpo, tapa, correas y etiqueta.
///
/// Vectorial y no render 3D: el volumen real es un pozo sin fondo para lo que
/// aporta, y esto ya lee inequívocamente como maleta.
struct SuitcaseCard: View {
    let suitcase: Suitcase

    var body: some View {
        NavigationLink(value: ClosetRoute.suitcase(id: suitcase.id)) {
            VStack(spacing: WK.Spacing.xs) {
                SuitcaseFigure(
                    symbolName: suitcase.symbolName,
                    tint: SuitcaseTint(rawValue: suitcase.colorRaw ?? "")
                )
                Text(suitcase.name)
                    .font(WK.Font.garmentName)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .lineLimit(1)
                    .frame(width: 132)
            }
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}

// **Sustituida por `SuitcaseFigure`.** Se queda comentada y no borrada: era
// la forma de la balda hasta ahora y sirve de referencia de lo que había.
// El fallo no era de detalle —le faltaban piezas— sino de construcción: el
// asa se ponía con un `offset` fuera del marco declarado, así que la pieza
// medía menos de lo que pintaba y quedaba descolgada de la balda.
//
// private struct SuitcaseShape: View {
//     let symbolName: String
//     let tint: SuitcaseTint?
//
//     /// El color elegido, o la superficie neutra si no hay ninguno.
//     private var body_: Color {
//         guard let tint else { return WK.Palette.shelf }
//         return Color(red: tint.components.red, green: tint.components.green, blue: tint.components.blue)
//     }
//
//     var body: some View {
//         ZStack {
//             RoundedRectangle(cornerRadius: 14, style: .continuous)
//                 .fill(body_)
//                 .overlay(
//                     RoundedRectangle(cornerRadius: 14, style: .continuous)
//                         .strokeBorder(WK.Palette.shelfEdge, lineWidth: 1)
//                 )
//                 .frame(width: 132, height: 104)
//
//             // Correas
//             HStack(spacing: 46) {
//                 Capsule().fill(WK.Palette.ink(0.10)).frame(width: 10, height: 104)
//                 Capsule().fill(WK.Palette.ink(0.10)).frame(width: 10, height: 104)
//             }
//
//             // El icono elegido, en el centro. Es lo que distingue una maleta de
//             // otra a la velocidad a la que se mira una balda: el nombre, en
//             // pequeño y debajo, llega tarde.
//             Image(systemName: symbolName)
//                 .font(.system(size: 30))
//                 .foregroundStyle(.black.opacity(0.45))
//
//             // Asa
//             RoundedRectangle(cornerRadius: 4)
//                 .stroke(WK.Palette.shelfEdge, lineWidth: 7)
//                 .frame(width: 44, height: 22)
//                 .offset(y: -60)
//         }
//         .frame(width: 132, height: 128, alignment: .bottom)
//     }
// }

/// La tarjeta de "nueva maleta".
///
/// Deja de ser privada porque la usan las dos: la fila del altillo y la balda
/// abierta. Duplicarla habría dejado dos trazos discontinuos que se separan al
/// primer retoque.
struct NewSuitcaseCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: WK.Spacing.xs) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(WK.Palette.shelfEdge, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .frame(width: 132, height: 104)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundStyle(WK.Palette.secondaryText)
                    }
                    .frame(width: 132, height: 128, alignment: .bottom)
                Text("Nueva maleta")
                    .font(WK.Font.garmentName)
                    .foregroundStyle(WK.Palette.secondaryText)
            }
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}
