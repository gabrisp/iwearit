import CoreGraphics
import SwiftUI
import WKCore
import WKDesign
import WKVision

/// Lo que ha salido de la foto, antes de generar nada.
///
/// ## Por qué este paso va antes
///
/// El detector se equivoca **hacia arriba**: parte un pantalón por el cinturón
/// y devuelve tres prendas, o se lleva un trozo de sofá. Hasta ahora eso
/// llegaba directo a la ficha, y con tres trozos había que ir pasando páginas
/// eligiendo entre cosas que no eran prendas — y encima cada una se
/// reconstruía, que se paga.
///
/// Aquí se decide primero: esto sí, esto no, y esto lo rodeo yo. Solo lo que
/// quede pasa a reconstruirse. Es el orden natural —recortar y luego dibujar—
/// y además es el barato.
struct ImportDetectedStep: View {
    let model: ImportModel
    /// La foto original, para rodear a mano lo que el detector no vio.
    let photo: CGImage

    @State private var isCroppingByHand = false
    /// Qué candidato se está recortando otra vez. `nil` = uno nuevo.
    @State private var recropping: UUID?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: WK.Spacing.m)]

    private var keptCount: Int { model.candidates.count(where: \.isKept) }

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            header

            ScrollView {
                LazyVGrid(columns: columns, spacing: WK.Spacing.m) {
                    ForEach(model.candidates) { candidate in
                        DetectedCell(
                            candidate: candidate,
                            onToggle: { model.setKeep(!candidate.isKept, forCandidateWithID: candidate.id) },
                            onRecrop: {
                                recropping = candidate.id
                                isCroppingByHand = true
                            },
                            onDiscard: { model.discard(candidateWithID: candidate.id) }
                        )
                    }

                    AddByHandCell {
                        recropping = nil
                        isCroppingByHand = true
                    }
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.bottom, WK.Spacing.m)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WK.Palette.canvas)
        .adaptiveSafeAreaBar(edge: .bottom) { continueBar }
        .fullScreenCover(isPresented: $isCroppingByHand) {
            ManualCropScreen(
                image: photo,
                onCrop: { cropped in
                    if let recropping {
                        model.setManualCrop(cropped, forCandidateWithID: recropping)
                    } else {
                        model.addManualCandidate(cropped)
                    }
                },
                // Rodeando prendas nuevas se sigue; rehaciendo el recorte de
                // una que ya está, se vuelve al acabar.
                keepsGoing: recropping == nil
            )
        }
    }

    private var header: some View {
        VStack(spacing: WK.Spacing.xs) {
            Text(model.candidates.isEmpty ? "No hemos visto ninguna prenda" : "Esto hemos detectado")
                .font(WK.Font.title)
                .foregroundStyle(WK.Palette.primaryText)

            Text(
                model.candidates.isEmpty
                    ? "Rodéala con el dedo y la recortamos igual."
                    : "Quita lo que no sea ropa. Si algo salió partido, recórtalo a mano."
            )
            .font(WK.Font.caption)
            .foregroundStyle(WK.Palette.secondaryText)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.top, WK.Spacing.m)
    }

    private var continueBar: some View {
        WKPrimaryButton(
            keptCount == 0 ? "Recorta o añade una prenda" : "Continuar con \(keptCount)"
        ) {
            Task { await model.confirmDetection() }
        }
        .disabled(keptCount == 0)
        .opacity(keptCount == 0 ? 0.4 : 1)
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.s)
        .animation(WKAnimation.selection, value: keptCount)
    }
}

/// Una prenda detectada, con sus dos decisiones.
///
/// El toque marca y desmarca —que es la decisión de cada día— y el toque largo
/// abre lo demás: rodearla otra vez o tirarla de la lista. Poner tres botones
/// en una celda de 104 puntos deja una celda que es tres botones y ninguna
/// prenda.
private struct DetectedCell: View {
    let candidate: ImportCandidate
    let onToggle: () -> Void
    let onRecrop: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        Button(action: onToggle) {
            candidate.image
                .resizable()
                .scaledToFit()
                .frame(height: 104)
                .padding(WK.Spacing.xs)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                        .fill(WK.Palette.ink(0.04))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                        .stroke(WK.Palette.accent, lineWidth: candidate.isKept ? 2 : 0)
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: candidate.isKept ? "checkmark.circle.fill" : "circle")
                        .font(.footnote)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            candidate.isKept ? WK.Palette.onAccent : WK.Palette.secondaryText,
                            candidate.isKept ? WK.Palette.accent : WK.Palette.ink(0.10)
                        )
                        .padding(WK.Spacing.xs)
                }
                .opacity(candidate.isKept ? 1 : 0.45)
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
        .contextMenu {
            Button("Recortar a mano", systemImage: "lasso", action: onRecrop)
            Button("Quitar de la lista", systemImage: "xmark", role: .destructive, action: onDiscard)
        }
        .animation(WKAnimation.selection, value: candidate.isKept)
    }
}

/// Añadir una prenda que el detector no vio.
private struct AddByHandCell: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: WK.Spacing.xs) {
                Image(systemName: "lasso")
                    .font(.title2)
                Text("Rodear a mano")
                    .font(WK.Font.caption)
            }
            .foregroundStyle(WK.Palette.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background {
                RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                    .strokeBorder(
                        WK.Palette.ink(0.15),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 5])
                    )
            }
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}
