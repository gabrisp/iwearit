import SwiftUI
import WKDesign

/// **Los botones de un conjunto propuesto**, en un solo sitio.
///
/// Guardar, ponerle día, llevarlo de viaje, abrirlo y descartarlo. Los mismos
/// cinco en la inspiración y en el chat del estilista, en el mismo orden y con
/// el mismo aspecto: eran dos copias escritas a mano, y en cuanto una cambiaba
/// —el corazón que se llena, el rojo al guardar— la otra se quedaba atrás.
/// Ahora hay una y las dos pantallas la ponen.
///
/// Lo único que cambia entre ellas es **cómo se colocan**: en columna a un
/// lado de la tarjeta grande de la inspiración, y en fila arriba de la tarjeta
/// del chat, que es más baja que ancha.
struct LookActions: View {
    enum Layout {
        case column
        case row
    }

    /// Qué significa guardar aquí: el corazón del armario, o el "+" de una
    /// maleta. Ver `InspoLookCard.Keep`.
    var keep: InspoLookCard.Keep = .favourite
    let isSaved: Bool
    /// Cuánto le falta al arrastre para contar como me gusta, de 0 a 1. Cero
    /// donde no hay arrastre.
    var keepProgress: CGFloat = 0
    /// Si se puede poner día. En una maleta sin fechas no hay días.
    var showsPlan = true
    let onSave: () -> Void
    let onPlan: () -> Void
    /// A la maleta. `nil` dentro de una maleta: ya estás en una.
    var onPack: (() -> Void)?
    let onEdit: () -> Void
    let onDislike: () -> Void
    var layout: Layout = .column

    var body: some View {
        switch layout {
        case .column:
            VStack(spacing: WK.Spacing.xs) { buttons }
        case .row:
            HStack(spacing: WK.Spacing.xs) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        // **El corazón se llena con el dedo.** Arrastrando a la derecha se
        // tiñe de rojo desde abajo —lleno justo cuando el gesto ya cuenta—, y
        // tocándolo se enciende de golpe; volver a tocarlo lo apaga.
        //
        // **Una sola pieza, un solo camino.** Guardado no es otro dibujo: es
        // el mismo símbolo con el progreso a tope. Así el botón y el
        // indicador del centro de la pantalla —que es `FillingSymbol` también—
        // no pueden dejar de parecerse.
        WKCircleButton(size: .compact, action: onSave) {
            FillingSymbol(
                empty: keep.symbol,
                full: keep.doneSymbol,
                progress: isSaved ? 1 : keepProgress,
                fill: keep.fill
            )
        }
        .animation(WKAnimation.selection, value: isSaved)
        if showsPlan { circle("calendar", action: onPlan) }
        // Lo que se propone para un viaje no es un favorito ni es del jueves.
        if let onPack { circle("suitcase", action: onPack) }
        // El lápiz hace lo mismo que el doble toque: el gesto está bien para
        // quien lo conoce; el botón, para quien no.
        circle("pencil", action: onEdit)
        // Y decir que no también es un botón: un gesto que no se ve deja media
        // decisión sin contar, y el estilista se queda sin la mitad de lo que
        // necesita saber.
        circle("hand.thumbsdown", action: onDislike)
    }

    private func circle(_ symbol: String, action: @escaping () -> Void) -> some View {
        WKCircleButton(symbol, size: .compact, action: action)
            .tint(WK.Palette.primaryText)
    }
}
