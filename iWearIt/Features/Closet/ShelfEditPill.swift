import SwiftUI
import WKDesign

/// Editar las baldas, **al final del armario**.
///
/// ## Por qué aquí abajo y no en el menú del "+"
///
/// Porque es donde se te ocurre. Ordenar las baldas no es algo que se decida al
/// abrir la app: se decide cuando llegas al fondo del armario y ves que la
/// balda de accesorios está antes que la de zapatos, o que sobra una. Tener que
/// subir hasta arriba y abrir un menú para arreglar lo que estás mirando es el
/// camino largo a un cambio pequeño.
///
/// Sigue estando en el menú del "+" además de aquí: quien lo busque ahí lo
/// encuentra, y quien llegue hasta abajo se lo encuentra puesto.
///
/// ## Por qué una píldora y no una fila más
///
/// Porque no es armario. Todo lo que hay encima son prendas y maletas —cosas
/// tuyas—; esto es un control. Con el mismo cristal interactivo que la barra de
/// pestañas queda claro de un vistazo que pertenece a la app y no al armario,
/// sin necesidad de un separador ni de un título de sección.
struct ShelfEditPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // **Peso medio y no ligero.** En ligero se leía como una nota al
            // pie del armario, y esto es un control: la misma letra que el
            // resto de cosas pulsables pequeñas.
            //
            // Y un lápiz, no los tiradores de un ecualizador: `slider` dice
            // "ajustar valores", que es lo que hace un filtro. Aquí se
            // renombra, se reordena y se borra, y eso es editar.
            Label(String(localized: "closet.shelfeditpill.editShelves", defaultValue: "Edit shelves"), systemImage: "pencil")
                .font(WK.Font.captionMedium)
                .foregroundStyle(WK.Palette.secondaryText)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
        .adaptiveGlassInteractive(in: .capsule)
        .frame(maxWidth: .infinity)
        // Aire por arriba para que no se lea como parte de la última balda, y
        // por abajo para que el accesorio flotante no se le siente encima.
        // Arriba ya va el recuento de prendas, que lo separa de la balda.
        .padding(.top, WK.Spacing.s)
        .padding(.bottom, WK.Spacing.xxl)
    }
}
