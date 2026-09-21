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
    /// Las fotos originales, para rodear a mano lo que el detector no vio.
    let photos: [CGImage]

    @State private var isCroppingByHand = false
    /// Qué candidato se está recortando otra vez. `nil` = uno nuevo.
    @State private var recropping: UUID?
    /// Sobre qué foto se va a dibujar el lazo.
    @State private var croppingPhoto = 0

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: WK.Spacing.m)]

    private var keptCount: Int { model.candidates.count(where: \.isKept) }

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            header

            ScrollView {
                // **Cada foto con lo suyo debajo.**
                //
                // Con varias fotos, una rejilla única de recortes deja de
                // poder comprobarse: no se sabe de cuál salió cada cosa, y la
                // comprobación es justo esa —mirar la foto y ver que a ese
                // recorte le falta media manga, o que aquello era el sofá.
                LazyVStack(spacing: WK.Spacing.l) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                        PhotoSection(
                            photo: photo,
                            number: index + 1,
                            total: photos.count,
                            candidates: model.candidates.filter { $0.photoIndex == index },
                            columns: columns,
                            onToggle: { model.setKeep(!$0.isKept, forCandidateWithID: $0.id) },
                            onRecrop: { candidate in
                                recropping = candidate.id
                                croppingPhoto = index
                                isCroppingByHand = true
                            },
                            onDiscard: { model.discard(candidateWithID: $0.id) },
                            onAddByHand: {
                                recropping = nil
                                croppingPhoto = index
                                isCroppingByHand = true
                            }
                        )
                    }
                }
                .padding(.bottom, WK.Spacing.m)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WK.Palette.canvas)
        .adaptiveSafeAreaBar(edge: .bottom) { continueBar }
        .fullScreenCover(isPresented: $isCroppingByHand) {
            ManualCropScreen(
                image: photos[min(croppingPhoto, photos.count - 1)],
                onCrop: { cropped in
                    if let recropping {
                        model.setManualCrop(cropped, forCandidateWithID: recropping)
                    } else {
                        model.addManualCandidate(cropped, photoIndex: croppingPhoto)
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

/// Una foto del lote y las prendas que salieron de ella.
private struct PhotoSection: View {
    let photo: CGImage
    let number: Int
    let total: Int
    let candidates: [ImportCandidate]
    let columns: [GridItem]
    let onToggle: (ImportCandidate) -> Void
    let onRecrop: (ImportCandidate) -> Void
    let onDiscard: (ImportCandidate) -> Void
    let onAddByHand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            if total > 1 {
                Text("Foto \(number) de \(total)")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .padding(.horizontal, WK.Spacing.screenInset)
            }

            Image(decorative: photo, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: WK.Radius.card, style: .continuous))
                .padding(.horizontal, WK.Spacing.screenInset)

            LazyVGrid(columns: columns, spacing: WK.Spacing.m) {
                ForEach(candidates) { candidate in
                    DetectedCell(
                        candidate: candidate,
                        onToggle: { onToggle(candidate) },
                        onRecrop: { onRecrop(candidate) },
                        onDiscard: { onDiscard(candidate) }
                    )
                }

                AddByHandCell(action: onAddByHand)
            }
            .padding(.horizontal, WK.Spacing.screenInset)
        }
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
                // **Todas iguales.** El recorte de una zapatilla es ancho y el
                // de un vestido, alto: dejando que cada celda midiera lo suyo,
                // la rejilla salía con filas de alturas distintas y parecía
                // rota. Con la celda cuadrada y la imagen ajustada dentro,
                // todas ocupan lo mismo y lo que cambia es la prenda.
                .padding(WK.Spacing.xs)
                .frame(maxWidth: .infinity)
                .frame(height: 112)
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
