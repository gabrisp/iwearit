import SwiftUI
import WKDesign

/// Una balda del armario: cabecera, prendas colgadas y el tablero.
///
/// **No tiene estado ni `@Query`.** Recibe un `ShelfData` ya construido, que es
/// un valor. Ese es el punto: `ClosetScreen` se reevalúa cuando cambia
/// cualquier prenda — es inevitable, SwiftData observa el tipo entero — pero
/// solo la balda cuyo `ShelfData` haya cambiado ejecuta su `body`.
///
/// Tener el `@Query` aquí dentro parecía más limpio y era justo lo contrario:
/// convertía la vista en no-POD y obligaba a las cuatro baldas visibles a
/// reevaluarse en cada edición. Medido con `_logChanges`.
struct ShelfSection: View, Equatable {
    let data: ShelfData

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.data == rhs.data }

    var body: some View {
        #if DEBUG
        let _ = Self._logChanges()
        #endif
        VStack(alignment: .leading, spacing: 0) {
            ShelfHeaderButton(
                slug: data.id,
                name: data.name,
                symbol: data.symbol,
                count: data.garments.count
            )

            ScrollView(.horizontal) {
                LazyHStack(alignment: .bottom, spacing: WK.Spacing.m) {
                    ForEach(data.garments) { garment in
                        HangingGarmentView(garment: garment)
                    }
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .frame(height: WK.Shelf.height, alignment: .bottom)
            }
            .scrollIndicators(.hidden)
            // Sin superficie propia: el hueco de la balda es la misma página.
            // Poner aquí un bloque blanco dejaba una plancha enorme en cuanto
            // la balda estaba vacía, y lo que separa una balda de la siguiente
            // es el canto y su sombra, no un cambio de color.

            ShelfPlank()
        }
        .padding(.bottom, WK.Spacing.l)
    }
}
