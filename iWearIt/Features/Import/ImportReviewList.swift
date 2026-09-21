import SwiftUI
import WKCore
import WKDesign
import WKVision

/// Revisión de lo que el pipeline propone, **en lista**.
///
/// - Warning: ya no se usa. La sustituye `ImportReviewPager`, que pagina la
///   misma ficha grande que se enseña cuando la foto trae una sola prenda. Se
///   queda aquí, sin borrar, porque es la referencia de lo que había: una
///   miniatura de 64 puntos, un menú de tipo y una casilla — con eso no se
///   podía ni ver si el recorte había partido la prenda, ni corregir el nombre
///   o el color, que es justo lo que había que corregir.
///
/// Es la pantalla que hace honesto el modo degradado: la categoría sale de
/// geometría, así que el usuario tiene la última palabra **antes** de que nada
/// entre al armario, no después.
struct ImportReviewList: View {
    let model: ImportModel

    var body: some View {
        ScrollView {
            WKSection(
                footer: "Las categorías son una propuesta. Corrígelas si hace falta."
            ) {
                ForEach(Array(model.candidates.enumerated()), id: \.element.id) { index, candidate in
                    ImportCandidateRow(
                        candidate: candidate,
                        showsSeparator: index < model.candidates.count - 1,
                        onToggleKeep: { model.setKeep($0, forCandidateWithID: candidate.id) },
                        onChangeKind: { model.setKind($0, forCandidateWithID: candidate.id) }
                    )
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas)
    }
}

/// Fila de una prenda propuesta.
///
/// Vista propia y no inline: se repite por cada prenda y tiene su propio picker.
private struct ImportCandidateRow: View {
    let candidate: ImportCandidate
    var showsSeparator = true
    let onToggleKeep: (Bool) -> Void
    let onChangeKind: (GarmentKind) -> Void

    var body: some View {
        WKRow(showsSeparator: showsSeparator) {
            HStack(spacing: WK.Spacing.m) {
            candidate.image
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 76)
                .opacity(candidate.isKept ? 1 : 0.3)

            VStack(alignment: .leading, spacing: WK.Spacing.xs) {
                Picker("Tipo", selection: Binding(
                    get: { candidate.kind },
                    set: { onChangeKind($0) }
                )) {
                    ForEach(GarmentKind.allCases, id: \.self) { kind in
                        Text(ImportCandidateLabels.label(for: kind)).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                if let duplicateOf = candidate.duplicateOf {
                    // **Con el nombre de la prenda a la que se parece.** Un
                    // "ya la tienes" a secas obliga a ir al armario a buscar
                    // cuál, y a decidir a ciegas mientras tanto.
                    Label("Ya la tienes: \(duplicateOf)", systemImage: "square.on.square")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }

                // **Lo que el pipeline ya sabe, enseñado.**
                //
                // Marca, color, estilo y temporada se calculan en cada
                // importación y hasta ahora se tiraban: la fila enseñaba el
                // tipo y el color y nada más. El usuario aprobaba una prenda
                // sin ver lo que se iba a guardar con ella, y lo primero que
                // hacía después era abrirla para comprobarlo.
                CandidateFactsRow(candidate: candidate)
            }

            Spacer()

            Button {
                onToggleKeep(!candidate.isKept)
            } label: {
                Image(systemName: candidate.isKept ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(candidate.isKept ? WK.Palette.accent : WK.Palette.secondaryText)
                    .contentShape(.rect)
            }
            .buttonStyle(WKPressStyle())
            }
        }
    }

}
