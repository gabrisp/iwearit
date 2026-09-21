import SwiftUI

// Transición de zoom: la vista de destino emerge del elemento que la abrió.
//
// `matchedTransitionSource` y `.navigationTransition(.zoom:)` son iOS 18, así
// que no necesitan gate. Se envuelven igualmente para que las features no
// dependan de la forma exacta de la API y para tener un único sitio donde
// cambiarlas si iOS 26 aporta algo mejor.

public extension View {
    /// Marca el origen del zoom: la prenda que se toca, el botón "+".
    func adaptiveZoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        matchedTransitionSource(id: id, in: namespace)
    }

    /// Marca el destino: el sheet o la pantalla que aparece.
    func adaptiveZoomDestination(id: some Hashable, in namespace: Namespace.ID) -> some View {
        navigationTransition(.zoom(sourceID: id, in: namespace))
    }
}
