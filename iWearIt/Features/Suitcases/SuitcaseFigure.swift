import SwiftUI
import WKCore
import WKDesign

/// El dibujo de una maleta.
///
/// ## Por qué se rehízo
///
/// La anterior era un rectángulo redondeado con dos cápsulas encima y un asa
/// puesta con un `offset` a ojo: las correas cruzaban el icono, el asa flotaba
/// separada del cuerpo y la pieza entera medía más que su marco, así que en la
/// balda quedaba descolgada. No se leía como una maleta; se leía como tres
/// formas apiladas.
///
/// ## Lo que hace que una maleta parezca una maleta
///
/// Cuatro cosas, y ninguna es el contorno:
///
/// 1. **El asa sale de dentro.** Va dibujada *detrás* del cuerpo y solapada, de
///    modo que nace de la tapa en vez de posarse encima.
/// 2. **La tapa y el cuerpo son dos piezas.** Una costura horizontal con su
///    luz por debajo es lo que dice que eso se abre. Sin ella es una caja.
/// 3. **Volumen por la luz, no por el trazo.** Un degradado vertical —claro
///    arriba, sombra abajo— y unas acanaladuras finas bastan; el contorno
///    grueso hace que parezca un icono, no un objeto.
/// 4. **Las esquinas protegidas y las ruedas.** Es lo que nadie dibuja y lo
///    que hace que se reconozca al tamaño de una miniatura.
///
/// Sigue siendo vectorial y plano a propósito: un render con volumen real es un
/// pozo sin fondo para lo que aporta en una celda de 132 puntos.
struct SuitcaseFigure: View {
    /// Lo que hay guardado en la maleta: un emoji, o el nombre de símbolo SF
    /// de las maletas creadas antes. `SuitcaseEmoji.display(for:)` traduce.
    let symbolName: String
    let tint: SuitcaseTint?
    /// Ancho del cuerpo. Todo lo demás se deriva de él, así que la pieza se
    /// escala entera cambiando un número.
    var width: CGFloat = 132

    /// El color elegido, o la superficie neutra si no hay ninguno.
    private var base: Color {
        guard let tint else { return WK.Palette.shelf }
        return Color(
            red: tint.components.red,
            green: tint.components.green,
            blue: tint.components.blue
        )
    }

    private var bodyHeight: CGFloat { width * 0.80 }
    private var handleHeight: CGFloat { width * 0.22 }
    private var corner: CGFloat { width * 0.16 }
    /// Dónde parte la tapa del cuerpo, desde arriba.
    private var seam: CGFloat { bodyHeight * 0.34 }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Detrás de todo: el asa y las ruedas asoman por fuera del cuerpo,
            // y tienen que quedar **por debajo** para que parezcan salir de él.
            handle
                .offset(y: -(bodyHeight - handleHeight * 0.45))
            wheels
                .offset(y: width * 0.035)

            shell
        }
        // El marco declara lo que ocupa la pieza **con** el asa y las ruedas.
        // La versión anterior medía solo el cuerpo y luego pintaba fuera, que
        // es lo que la descolgaba de la balda.
        .frame(width: width, height: bodyHeight + handleHeight * 0.55 + width * 0.05)
    }

    /// El asa: un arco hueco que nace de la tapa.
    private var handle: some View {
        RoundedRectangle(cornerRadius: width * 0.07, style: .continuous)
            .stroke(base.mix(with: .black, by: 0.22), lineWidth: width * 0.055)
            .frame(width: width * 0.36, height: handleHeight)
    }

    /// Dos ruedas asomando por debajo.
    private var wheels: some View {
        HStack(spacing: width * 0.48) {
            Capsule()
                .fill(.black.opacity(0.35))
                .frame(width: width * 0.11, height: width * 0.09)
            Capsule()
                .fill(.black.opacity(0.35))
                .frame(width: width * 0.11, height: width * 0.09)
        }
    }

    /// El cuerpo: degradado, acanaladuras, costura, esquineras e icono.
    private var shell: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return ZStack {
            shape.fill(base)

            // La luz. Tres paradas y no dos: con solo claro→oscuro la cara
            // queda lavada por el centro, que es justo donde se mira.
            //
            // Y **floja**: lo que tiene que reconocerse de un vistazo es el
            // color que elegiste. Con el blanco al 32% de antes, un salvia y un
            // celeste acababan pareciendo la misma maleta clara.
            LinearGradient(
                colors: [
                    .white.opacity(0.16),
                    .white.opacity(0.02),
                    .black.opacity(0.12),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            ribs
            seamLine
            corners

            badge
        }
        .frame(width: width, height: bodyHeight)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.black.opacity(0.14), lineWidth: 1)
        }
        // La sombra la lleva el cuerpo y no el contenedor: puesta fuera,
        // también la proyectaban el asa y las ruedas, y se veían tres sombras
        // sueltas en vez de un objeto apoyado.
        .shadow(color: .black.opacity(0.18), radius: width * 0.06, y: width * 0.03)
    }

    /// El emoji elegido, como **pegatina de viaje**.
    ///
    /// Emoji y no un símbolo SF: un glifo monocromo sobre la maleta se lee como
    /// parte del dibujo —una maleta pintada sobre una maleta— y por eso el
    /// conjunto parecía el emoji 🧳 en vez de una maleta con una pegatina. El
    /// emoji trae su color, así que se separa del cuerpo sin inventarle nada.
    ///
    /// Sobre un disco claro y descentrado, que es donde va una pegatina. Y **no
    /// se dibuja la genérica**: una maleta sin pegatina se reconoce igual.
    @ViewBuilder
    private var badge: some View {
        let emoji = SuitcaseEmoji.display(for: symbolName)
        if emoji != SuitcaseEmoji.suitcase.rawValue {
            Circle()
                .fill(.white.opacity(0.72))
                .frame(width: width * 0.30, height: width * 0.30)
                .overlay {
                    Text(emoji)
                        .font(.system(size: width * 0.16))
                }
                .offset(x: width * 0.22, y: bodyHeight * 0.18)
        }
    }

    /// Acanaladuras verticales, como las de una maleta rígida.
    private var ribs: some View {
        HStack(spacing: width * 0.105) {
            ForEach(0..<5, id: \.self) { _ in
                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 1.5)
            }
        }
    }

    /// La costura de la tapa: la línea oscura y su luz justo debajo.
    ///
    /// Las dos, o no hay relieve. Una línea sola se lee como una raya pintada.
    private var seamLine: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.black.opacity(0.16)).frame(height: 1.5)
            Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
            Spacer(minLength: 0)
        }
        .padding(.top, seam)
    }

    /// Esquineras inferiores.
    private var corners: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                CornerGuard(size: width * 0.17, corner: corner)
                Spacer(minLength: 0)
                CornerGuard(size: width * 0.17, corner: corner)
                    .scaleEffect(x: -1)
            }
        }
    }
}

/// Una esquinera. Vista propia porque se usa dos veces y una de ellas
/// espejada: repetida dentro del `@ViewBuilder` costaría dos diffs.
private struct CornerGuard: View {
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: corner * 0.6, style: .continuous)
            .fill(.black.opacity(0.13))
            .frame(width: size, height: size * 0.8)
            // Desplazada hacia fuera: lo que se ve es el cuarto que queda
            // dentro del recorte del cuerpo, que es la forma de una esquinera.
            .offset(x: -size * 0.35, y: size * 0.3)
    }
}

#Preview {
    HStack(spacing: 20) {
        SuitcaseFigure(symbolName: SuitcaseEmoji.suitcase.rawValue, tint: .teal)
        SuitcaseFigure(symbolName: SuitcaseEmoji.beach.rawValue, tint: .coral, width: 96)
        SuitcaseFigure(symbolName: SuitcaseEmoji.plane.rawValue, tint: nil, width: 72)
    }
    .padding(40)
    .background(WK.Palette.canvas)
}
