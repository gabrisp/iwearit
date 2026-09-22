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
    /// Solo para pasárselo a la vista que acompaña al dedo al arrastrar: ver
    /// el `draggable` de abajo.
    @Environment(AppEnvironment.self) private var appEnvironment
    /// Sobre qué prenda está el dedo ahora mismo, para hacerle sitio.
    @State private var hovered: UUID?
    /// El arrastre propio. Ver `ShelfDragModel`.
    @Environment(ShelfDragModel.self) private var drag

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.data == rhs.data }

    /// El hueco delante de una prenda, según por dónde va el arrastre.
    private func gap(before id: UUID) -> CGFloat {
        guard drag.target == .before(id) else { return 0 }
        return drag.isLanding ? WK.Shelf.garmentWidth + WK.Spacing.m : WK.Spacing.xl
    }

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
                // **Sin espaciado en la fila: cada prenda lleva el suyo.** Con
                // el espaciado del `HStack`, la prenda descolgada seguía
                // cobrando su separación a los dos lados aunque midiera cero, y
                // compensarlo con un margen negativo no funciona —SwiftUI no
                // deja que algo mida menos que nada—. El resultado era un
                // saltito al levantarla y otro al soltarla. Con el espacio
                // dentro de cada prenda, al descolgarla se va entero.
                LazyHStack(alignment: .bottom, spacing: 0) {
                    ForEach(data.garments) { garment in
                        HangingGarmentView(garment: garment)
                            // Entra creciendo desde su sitio, no de la nada.
                            // Salvo la que acaba de posarse: esa ya se ha
                            // visto bajar, y crecer otra vez sería repetirla.
                            .transition(
                                drag.justLanded == garment.id
                                    ? .identity
                                    : .scale(scale: 0.7).combined(with: .opacity)
                            )
                            // **Descolgada del todo.** Mientras va en el dedo
                            // ya no está en la balda: no se queda su hueco,
                            // las de al lado se juntan. La vista no se quita
                            // —el gesto que la lleva vive en ella— sino que se
                            // estrecha a cero y devuelve el espaciado que le
                            // tocaba.
                            .opacity(drag.dragged?.id == garment.id ? 0 : 1)
                            .frame(width: drag.dragged?.id == garment.id ? 0 : nil)
                            .padding(.trailing, drag.dragged?.id == garment.id ? 0 : WK.Spacing.m)
                            .animation(ShelfDragModel.lift, value: drag.dragged?.id == garment.id)
                            // El hueco que se abre delante de donde va a caer,
                            // **del ancho de una prenda de verdad**: se ve que
                            // cabe, y al soltarla no empuja a las demás otra vez.
                            // Pequeño mientras se mueve —una pista de dónde
                            // cae, sin empujar media balda con cada paso del
                            // dedo— y del ancho de la prenda al soltar, para
                            // que baje a un hueco en el que cabe.
                            .padding(.leading, gap(before: garment.id))
                            .onGeometryChange(for: CGRect.self) {
                                $0.frame(in: .named(ShelfDragModel.space))
                            } action: { frame in
                                drag.register(item: garment.id, in: data.id, frame: frame)
                            }
                            .onDisappear { drag.forget(item: garment.id) }
                            // **Mantener y llevársela.** Primero el toque
                            // largo —si no, pasar la balda con el dedo se
                            // llevaría la prenda por delante— y luego el
                            // arrastre, en el espacio del armario entero para
                            // poder cruzar de balda.
                            // **Con prioridad, no a la vez.** A la vez, el
                            // botón de la prenda también recibía el toque y al
                            // soltarla se abría su ficha. Con prioridad, si el
                            // toque largo gana el botón se cancela; si falla
                            // —un toque corto, o el dedo se mueve para pasar
                            // la balda— el botón y el scroll siguen como
                            // siempre.
                            .highPriorityGesture(
                                LongPressGesture(minimumDuration: 0.35)
                                    .sequenced(before: DragGesture(
                                        minimumDistance: 0,
                                        coordinateSpace: .named(ShelfDragModel.space)
                                    ))
                                    .onChanged { value in
                                        guard case let .second(true, dragValue) = value else { return }
                                        if let dragValue {
                                            if !drag.isDragging {
                                                drag.begin(garment, from: data.id, at: dragValue.startLocation)
                                            }
                                            drag.move(to: dragValue.location)
                                        }
                                    }
                                    .onEnded { _ in
                                        guard drag.isDragging else { return }
                                        Task {
                                            if await drag.land(in: modelContext) {
                                                appEnvironment.tips.complete(.dragGarment)
                                            }
                                        }
                                    }
                            )
                            .sensoryFeedback(.impact(weight: .medium), trigger: drag.dragged?.id == garment.id)
                    }

                    // El final de la balda: el hueco que se abre cuando va a
                    // caer la última, y sitio para soltar en una balda vacía.
                    Color.clear
                        .frame(
                            width: drag.target == .endOf(slug: data.id)
                                ? (drag.isLanding ? WK.Shelf.garmentWidth : WK.Spacing.xl * 2)
                                : WK.Spacing.xl,
                            height: WK.Shelf.height
                        )

                    // **El arrastre del sistema, retirado.** Copiaba en vez de
                    // mover —plancha cuadrada, "+" verde, la prenda quedándose
                    // en su sitio— y no dejaba soltar en una balda vacía. Se
                    // queda aquí comentado. Ver `ShelfDragModel`.
//                     ForEach(data.garments) { garment in
//                         HangingGarmentView(garment: garment)
//                             // Entra creciendo desde su sitio, no de la nada.
//                             .transition(.scale(scale: 0.7).combined(with: .opacity))
//                             // **Pulsar y mantener para llevársela.** El propio
//                             // `draggable` pide mantener el dedo antes de
//                             // arrancar; sin eso, pasar la balda con el dedo se
//                             // llevaría la prenda por delante.
//                             .draggable(GarmentTransfer(id: garment.id)) {
//                                 // Lo que se ve bajo el dedo: la prenda sola.
//                                 //
//                                 // **Con el entorno puesto a mano.** La vista
//                                 // que acompaña al dedo no se dibuja dentro de
//                                 // la jerarquía de la pantalla sino en una capa
//                                 // aparte del sistema, y ahí no llega nada de lo
//                                 // que se inyecta arriba. `HangingGarmentView`
//                                 // lee `AppEnvironment` para cargar la imagen, y
//                                 // sin él la app se caía en cuanto se levantaba
//                                 // la prenda.
//                                 HangingGarmentView(garment: garment)
//                                     .frame(width: WK.Shelf.garmentWidth)
//                                     .environment(appEnvironment)
//                             }
//                             // Soltar encima de otra prenda la pone **delante**
//                             // de ella, que es donde la estás dejando.
//                             .dropDestination(for: GarmentTransfer.self) { items, _ in
//                                 guard let dropped = items.first else { return false }
//                                 appEnvironment.tips.complete(.dragGarment)
//                                 withAnimation(WKAnimation.content) {
//                                     GarmentMover.move(
//                                         dropped.id, to: .before(garment.id), in: modelContext
//                                     )
//                                 }
//                                 return true
//                             } isTargeted: { isOver in
//                                 withAnimation(WKAnimation.selection) {
//                                     hovered = isOver ? garment.id : (hovered == garment.id ? nil : hovered)
//                                 }
//                             }
//                             // El hueco que se abre al pasar por encima: es lo
//                             // que dice dónde va a caer antes de soltarla.
//                             .padding(.leading, hovered == garment.id ? WK.Spacing.l : 0)
//                     }
//
//                     // El final de la balda, para dejarla la última. Estrecho,
//                     // pero es el único sitio que significa "al final".
//                     Color.clear
//                         .frame(width: WK.Spacing.xl, height: WK.Shelf.height)
//                         .dropDestination(for: GarmentTransfer.self) { items, _ in
//                             guard let dropped = items.first else { return false }
//                                 appEnvironment.tips.complete(.dragGarment)
//                             withAnimation(WKAnimation.content) {
//                                 GarmentMover.move(
//                                     dropped.id, to: .endOf(slug: data.id), in: modelContext
//                                 )
//                             }
//                             return true
//                         }
//                 }
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
            // Quieta mientras hay una prenda en el dedo: si no, arrastrar hacia
            // un lado desplaza la balda en vez de mover la prenda.
            .scrollDisabled(drag.isDragging)
            // Sin superficie propia: el hueco de la balda es la misma página.
            // Poner aquí un bloque blanco dejaba una plancha enorme en cuanto
            // la balda estaba vacía, y lo que separa una balda de la siguiente
            // es el canto y su sombra, no un cambio de color.

            // **La balda entera acepta prendas.** El canto es el sitio al que
            // apunta el dedo cuando lo que quieres decir es "esta balda", sin
            // tener que atinar entre dos prendas.
            ShelfPlank()
                // Con el arrastre propio, la balda entera es destino: ver
                // `onGeometryChange` de abajo.
                // .dropDestination(for: GarmentTransfer.self) { items, _ in
                //     guard let dropped = items.first else { return false }
                //     appEnvironment.tips.complete(.dragGarment)
                //     withAnimation(WKAnimation.content) {
                //         GarmentMover.move(dropped.id, to: .endOf(slug: data.id), in: modelContext)
                //     }
                //     return true
                // }
        }
        .padding(.bottom, WK.Spacing.l)
        // **La balda entera, cabecera incluida.** Es el sitio al que apunta
        // el dedo cuando lo que quiere decir es "aquí", haya ropa o no.
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(ShelfDragModel.space))
        } action: { frame in
            drag.register(shelf: data.id, frame: frame)
        }
        .animation(WKAnimation.selection, value: drag.target)
        // El hueco crece con el mismo muelle con el que baja la prenda.
        .animation(ShelfDragModel.lift, value: drag.isLanding)
    }
}
