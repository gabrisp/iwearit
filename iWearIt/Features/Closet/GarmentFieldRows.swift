import SwiftUI
import WKCore
import WKDesign

// Las filas con las que se describe una prenda.
//
// En su propio fichero y no dentro de la hoja de editar porque las usan las
// dos pantallas que enseñan los datos de una prenda: la de editar una que ya
// está en el armario y la de revisar una recién importada. Eran la misma
// pantalla dibujada dos veces, y se notaba en que una tenía chevrones y la
// otra píldoras para lo mismo.

/// Fila de dato: valor grande arriba, etiqueta pequeña debajo.
struct EditRow: View {
    let value: String
    let label: String
    var showsSeparator = true
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(value)
                            .font(WK.Font.rowTitle)
                            .foregroundStyle(WK.Palette.primaryText)
                            .lineLimit(1)
                        Text(label)
                            .font(WK.Font.caption)
                            .foregroundStyle(WK.Palette.tertiaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(WK.Palette.tertiaryText)
                }
                .padding(.vertical, WK.Spacing.m - 2)
                .contentShape(.rect)
            }
            .buttonStyle(WKRowButtonStyle())

            if showsSeparator {
                Rectangle().fill(WK.Palette.ink(0.07)).frame(height: 1)
            }
        }
    }
}

/// El nombre, escribible.
///
/// Es el **único** campo de texto libre de la hoja, y lo es a propósito: el
/// resto son vocabularios cerrados porque escribir "pantaón" a mano rompe la
/// clasificación sin que nadie se entere. Pero el nombre no clasifica nada —lo
/// propone la IA juntando color, tipo y marca— y acierta a medias muy a menudo:
/// "Zapatilla negro" cuando es azul marino. Sin poder tocarlo, el error se
/// queda ahí para siempre.
/// Notas libres de la prenda.
///
/// **Sin formato y sin sugerencias.** Es el sitio donde cabe lo que no cabe en
/// ningún otro campo: el enlace de la ficha de la tienda, la talla que
/// compraste, con qué la sueles llevar, que encoge al lavarla. Cualquier
/// estructura que le pusiéramos dejaría fuera la mitad de esos usos.
///
/// Varias líneas, no una: un enlace no cabe en una sola y cortarlo con puntos
/// suspensivos lo vuelve inútil para lo único que sirve, que es copiarlo.
struct NotesRow: View {
    @Binding var notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            TextField("Un enlace, una talla, una referencia…", text: $notes, axis: .vertical)
                .font(WK.Font.rowTitle)
                .foregroundStyle(WK.Palette.primaryText)
                .textInputAutocapitalization(.sentences)
                // Sin autocorrector: la mitad de lo que se escribe aquí son
                // enlaces y referencias, y el corrector los destroza.
                .autocorrectionDisabled()
                .lineLimit(1...6)

            Text("Notas")
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.tertiaryText)
        }
        .padding(.vertical, WK.Spacing.m - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NameRow: View {
    @Binding var name: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                TextField("Nombre", text: $name)
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.primaryText)
                    .textInputAutocapitalization(.sentences)
                    // Sin autocorrector: los nombres de marca no están en el
                    // diccionario y acabas con "Stussy" convertido en "Sucio".
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                Text("Nombre")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
            }
            .padding(.vertical, WK.Spacing.m - 2)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(WK.Palette.ink(0.07)).frame(height: 1)
        }
    }
}

/// El color, con su muestra circular.
///
/// Escribible solo donde tiene sentido. En el armario el color ya está medido
/// y lo que se quiere es verlo; al importar acaba de salir de un k-means —una
/// zapatilla azul marino se mide como negra más veces de las que parece— y
/// corregirlo ahí evita guardar un nombre que ya sabes que está mal.
struct ColorRow: View {
    let color: NamedColor?
    /// Si se pasa, el color se puede cambiar con el selector del sistema.
    var picked: Binding<Color>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let picked {
                    // **El selector de iOS, tal cual.**
                    //
                    // Nada de escribir el nombre del color ni de elegir de una
                    // lista: los nombres los pone la tabla y se equivocan
                    // —azul marino medido como negro—, y una lista corta nunca
                    // tiene el tono que es. El color se señala, que es como se
                    // mira una prenda.
                    ColorPicker(selection: picked, supportsOpacity: false) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Color")
                                .font(WK.Font.rowTitle)
                                .foregroundStyle(WK.Palette.primaryText)
                            Text("Toca la muestra para ajustarlo")
                                .font(WK.Font.caption)
                                .foregroundStyle(WK.Palette.tertiaryText)
                        }
                    }
                } else {
                    Text("Color")
                        .font(WK.Font.rowTitle)
                        .foregroundStyle(WK.Palette.primaryText)
                    Spacer()
                    if let color {
                        Circle()
                            .fill(Color(red: color.red, green: color.green, blue: color.blue))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(WK.Palette.ink(0.15), lineWidth: 1))
                    }
                }
            }
            .padding(.vertical, WK.Spacing.m - 2)

            Rectangle().fill(WK.Palette.ink(0.07)).frame(height: 1)
        }
    }
}
