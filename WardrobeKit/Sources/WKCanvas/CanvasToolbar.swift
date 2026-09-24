import SwiftUI
import WKDesign

/// Lo que se puede hacer con la prenda seleccionada.
///
/// Va **abajo y fija**, no colgando de la prenda. Las asas alrededor del
/// recuadro se encogen con el lienzo, tapan justo lo que estás intentando ver
/// al superponer, y obligan a apuntar a una esquina de 30 puntos en una prenda
/// que puede estar girada 32 grados. Una barra en un sitio fijo siempre está
/// donde la dejaste — y mover, pellizcar y girar se hacen con los dedos sobre
/// la prenda, no con asas.
public struct CanvasToolbar: View {
    private let onDelete: () -> Void
    private let onDuplicate: () -> Void
    private let onFlip: () -> Void
    private let onSendBackward: () -> Void
    private let onBringForward: () -> Void
    private let onMore: () -> Void

    public init(
        onDelete: @escaping () -> Void,
        onDuplicate: @escaping () -> Void,
        onFlip: @escaping () -> Void,
        onSendBackward: @escaping () -> Void,
        onBringForward: @escaping () -> Void,
        onMore: @escaping () -> Void
    ) {
        self.onDelete = onDelete
        self.onDuplicate = onDuplicate
        self.onFlip = onFlip
        self.onSendBackward = onSendBackward
        self.onBringForward = onBringForward
        self.onMore = onMore
    }

    @State private var isConfirmingDelete = false

    public var body: some View {
        AdaptiveGlassContainer(spacing: WK.Spacing.s) {
            // Sin aire entre ellos: cada botón ya lleva el suyo dentro —44
            // puntos para un icono de 30—, y sumarle separación dejaba la
            // barra más ancha que un iPhone pequeño.
            HStack(spacing: 0) {
                // En rojo y con confirmación. Quitar no destruye la prenda
                // —sigue en el armario— pero sí deshace el trabajo de
                // colocarla, y en una barra de seis botones el de la papelera
                // está a un dedo de distancia de duplicar.
                CanvasToolButton(symbol: "trash", tint: .red) {
                    isConfirmingDelete = true
                }
                .popover(isPresented: $isConfirmingDelete) {
                    DeleteConfirmation {
                        isConfirmingDelete = false
                        onDelete()
                    }
                }
                CanvasToolButton(symbol: "plus.square.on.square", action: onDuplicate)
                CanvasToolButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", action: onFlip)
                CanvasToolButton(symbol: "square.2.layers.3d.bottom.filled", action: onSendBackward)
                CanvasToolButton(symbol: "square.2.layers.3d.top.filled", action: onBringForward)
                CanvasToolButton(symbol: "ellipsis", action: onMore)
            }
            .padding(.horizontal, WK.Spacing.xs)
            // La misma altura que "Agregar" y que el color: los tres ocupan el
            // mismo sitio y se turnan, así que tienen que medir lo mismo o el
            // cristal salta al cambiar de uno a otro.
            .frame(height: CanvasTray.controlHeight)
        }
        .adaptiveGlassInteractive(in: .capsule)
    }
}

/// Un botón de la barra.
///
/// Vista propia y no un `@ViewBuilder` repetido cinco veces: repetir el cuerpo
/// dentro del builder cuesta cinco diffs en vez de uno por botón, y es
/// exactamente el caso que la regla del proyecto quiere evitar.
private struct CanvasToolButton: View {
    let symbol: String
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(WK.Font.headline)
                .foregroundStyle(tint ?? WK.Palette.primaryText)
                // **Lo que se toca mide lo que mide un dedo.** El icono son
                // treinta puntos y el área de toque era la misma: seis dianas
                // de 30×30 pegadas unas a otras, así que la papelera fallaba o
                // —peor— acertaba la de al lado. El icono no cambia de tamaño;
                // lo que crece es el hueco que escucha.
                .frame(width: 44, height: CanvasTray.controlHeight)
                // `background` dibuja pero **no** extiende el área de toque.
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}


/// La confirmación de quitar.
///
/// Un popover y no una alerta: sale **pegado al botón** que lo ha abierto, así
/// que se entiende qué va a pasar sin leer, y se descarta tocando fuera sin
/// tener que apuntar a "Cancelar".
private struct DeleteConfirmation: View {
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: WK.Spacing.s) {
            Text(String(localized: "wkcanvas.canvastoolbar.removeFromTheOutfit", defaultValue: "Remove from the outfit?", bundle: .module))
                .font(WK.Font.headline)
                .foregroundStyle(WK.Palette.primaryText)
            Text(String(localized: "wkcanvas.canvastoolbar.thePieceStaysInYour", defaultValue: "The piece stays in your closet.", bundle: .module))
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
                .multilineTextAlignment(.center)

            Button(role: .destructive, action: onConfirm) {
                Text(String(localized: "common.remove", defaultValue: "Remove", bundle: .module))
                    .font(WK.Font.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WK.Spacing.s + 2)
                    .background(.red, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(WKPressStyle())
        }
        .padding(WK.Spacing.m)
        .frame(width: 240)
        // Del tamaño de su contenido: un popover a tamaño de hoja para tres
        // líneas deja medio panel vacío.
        .presentationCompactAdaptation(.popover)
    }
}
