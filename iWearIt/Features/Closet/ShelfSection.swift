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

    @Environment(\.modelContext) private var modelContext
    /// Sobre qué prenda está el dedo ahora mismo, para hacerle sitio.
    @State private var hovered: UUID?

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
                            // Entra creciendo desde su sitio, no de la nada.
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                            // **Pulsar y mantener para llevársela.** El propio
                            // `draggable` pide mantener el dedo antes de
                            // arrancar; sin eso, pasar la balda con el dedo se
                            // llevaría la prenda por delante.
                            .draggable(GarmentTransfer(id: garment.id)) {
                                // Lo que se ve bajo el dedo: la prenda sola.
                                HangingGarmentView(garment: garment)
                                    .frame(width: WK.Shelf.garmentWidth)
                            }
                            // Soltar encima de otra prenda la pone **delante**
                            // de ella, que es donde la estás dejando.
                            .dropDestination(for: GarmentTransfer.self) { items, _ in
                                guard let dropped = items.first else { return false }
                                withAnimation(WKAnimation.content) {
                                    GarmentMover.move(
                                        dropped.id, to: .before(garment.id), in: modelContext
                                    )
                                }
                                return true
                            } isTargeted: { isOver in
                                withAnimation(WKAnimation.selection) {
                                    hovered = isOver ? garment.id : (hovered == garment.id ? nil : hovered)
                                }
                            }
                            // El hueco que se abre al pasar por encima: es lo
                            // que dice dónde va a caer antes de soltarla.
                            .padding(.leading, hovered == garment.id ? WK.Spacing.l : 0)
                    }

                    // El final de la balda, para dejarla la última. Estrecho,
                    // pero es el único sitio que significa "al final".
                    Color.clear
                        .frame(width: WK.Spacing.xl, height: WK.Shelf.height)
                        .dropDestination(for: GarmentTransfer.self) { items, _ in
                            guard let dropped = items.first else { return false }
                            withAnimation(WKAnimation.content) {
                                GarmentMover.move(
                                    dropped.id, to: .endOf(slug: data.id), in: modelContext
                                )
                            }
                            return true
                        }
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .frame(height: WK.Shelf.height, alignment: .bottom)
                // **Las prendas llegan y se van, no aparecen.**
                //
                // Al importar, al arrastrar de una balda a otra y al borrar,
                // lo que cambia es *qué hay colgado aquí*: sin animar, tres
                // prendas nuevas se materializan de golpe y la balda parece
                // otra. Animando sobre la lista de identificadores —y no sobre
                // el array entero— solo se mueve lo que de verdad entra o sale.
                .animation(WKAnimation.arrival, value: data.garments.map(\.id))
            }
            .scrollIndicators(.hidden)
            // Sin superficie propia: el hueco de la balda es la misma página.
            // Poner aquí un bloque blanco dejaba una plancha enorme en cuanto
            // la balda estaba vacía, y lo que separa una balda de la siguiente
            // es el canto y su sombra, no un cambio de color.

            // **La balda entera acepta prendas.** El canto es el sitio al que
            // apunta el dedo cuando lo que quieres decir es "esta balda", sin
            // tener que atinar entre dos prendas.
            ShelfPlank()
                .dropDestination(for: GarmentTransfer.self) { items, _ in
                    guard let dropped = items.first else { return false }
                    withAnimation(WKAnimation.content) {
                        GarmentMover.move(dropped.id, to: .endOf(slug: data.id), in: modelContext)
                    }
                    return true
                }
        }
        .padding(.bottom, WK.Spacing.l)
    }
}
