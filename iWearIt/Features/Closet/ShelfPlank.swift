import SwiftUI
import WKDesign

/// El tablero de la balda.
///
/// Vista pura sin entradas: no participa en el diffing y se dibuja una sola vez.
/// La sombra va **encima** del canto, no debajo, porque lo que da sensación de
/// profundidad es que las prendas parezcan apoyadas sobre el tablero.
struct ShelfPlank: View {
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(WK.Palette.shelfEdge)
                .frame(height: WK.Shelf.plankThickness)

            // `ink` y no negro: escrita como negro, la sombra se comía el
            // fondo en claro y desaparecía del todo en oscuro. Esto dice "un
            // poco del color de primer plano", que es lo que de verdad se quiere.
            LinearGradient(
                colors: [WK.Palette.ink(0.13), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            // Algo más larga que antes (10): se leía poco la balda.
            .frame(height: 20)
            .offset(y: WK.Shelf.plankThickness)
            .allowsHitTesting(false)
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        ShelfPlank()
        ShelfPlank()
    }
    .padding(.vertical, 40)
    .background(WK.Palette.canvas)
}
