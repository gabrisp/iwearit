import CoreGraphics
import SwiftUI
import WKCore
import WKDesign
import WKVision

/// Lo que ha salido de la foto, antes de generar nada.
///
/// **Sin usar.** Este paso intermedio ya no se muestra: de analizar se pasa
/// directo a la lista de prendas, donde cada tarjeta se abre, se recorta a
/// mano y se tira igual. Se conserva entero porque el recuadro editable sobre
/// la foto —`ImportDetectionBoxes`— puede volver a hacer falta.
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
    /// Qué foto se está mirando, que es también sobre la que se dibuja el lazo.
    @State private var focused: Int?

    private var current: Int { focused ?? 0 }
    private var keptCount: Int { model.candidates.count(where: \.isKept) }

    /// Lo que asoma de las fotos vecinas por cada lado.
    private static let peek: CGFloat = 44
    private static let spacing: CGFloat = 12

    var body: some View {
        // **La misma pantalla de antes, continuada.**
        //
        // Durante el análisis se está mirando un carrete de fotos con un texto
        // debajo; al acabar, lo que cambia es que la foto se hace grande,
        // aparecen los recuadros encima y las prendas salen debajo. Poner aquí
        // un título y una rejilla nueva rompía esa continuidad: parecía que la
        // app te había mandado a otro sitio en vez de haber terminado.
        VStack(spacing: WK.Spacing.m) {
            pager
            caption
            tools
            cutouts
        }
        .padding(.top, WK.Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WK.Palette.canvas)
        .adaptiveSafeAreaBar(edge: .bottom) { continueBar }
        // **Hoja, no `fullScreenCover`.** La cubierta a pantalla completa
        // presentada desde dentro de otra hoja dejaba la de debajo en negro al
        // cerrarse, y encima es un elemento que aquí no se usa. Con la hoja, el
        // cierre por arrastre se desactiva: a mitad de un recorte, un desliz
        // sin querer tira el trabajo.
        .sheet(isPresented: $isCroppingByHand) {
            ManualCropScreen(
                image: photos[min(current, photos.count - 1)],
                // Lo rodeado se recorta y dentro se busca el sujeto. Ver
                // `ImportModel.addManualCandidate`.
                onCrop: { cropped in
                    let photo = current
                    let target = recropping
                    Task {
                        if let target {
                            await model.setManualCrop(cropped, forCandidateWithID: target)
                        } else {
                            await model.addManualCandidate(cropped, photoIndex: photo)
                        }
                    }
                },
                // Rodeando prendas nuevas se sigue; rehaciendo el recorte de
                // una que ya está, se vuelve al acabar.
                keepsGoing: recropping == nil
            )
            .interactiveDismissDisabled()
        }
    }

    // MARK: Las fotos

    /// Una foto por página, con lo detectado encima.
    ///
    /// Paginado y no apilado: con tres fotos, una debajo de otra y cada una con
    /// su rejilla de recortes, la pantalla era un rollo de papel por el que
    /// había que scrollear para saber siquiera cuántas fotos había. Así se ve
    /// una entera, las vecinas asoman, y lo que sale de la que estás mirando
    /// está justo debajo.
    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: Self.spacing) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                    // **Entera, no recortada.** Con `scaledToFill` la foto
                    // llena la página pero se come los bordes, y ahí es donde
                    // suele estar la prenda que se quedó fuera —además de que
                    // los recuadros dejarían de caer donde toca.
                    Image(decorative: photo, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(.rect(cornerRadius: WK.Radius.card, style: .continuous))
                        // Lo detectado, señalado encima. Ver
                        // `ImportDetectionBoxes`.
                        .overlay {
                            ImportDetectionBoxes(
                                photo: photo,
                                candidates: model.candidates.filter { $0.photoIndex == index },
                                onChange: { model.setRect($1, forCandidateWithID: $0.id) },
                                onDiscard: { model.discard(candidateWithID: $0.id) }
                            )
                        }
                        .containerRelativeFrame(.horizontal) { width, _ in
                            max(width - 2 * (Self.peek + Self.spacing), 160)
                        }
                        .scrollTransition(.interactive) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.97)
                                .opacity(phase.isIdentity ? 1 : 0.6)
                        }
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $focused, anchor: .center)
        // **El margen se calcula, no se pone a ojo.**
        //
        // Cada página mide el ancho menos lo que asoma por los dos lados, así
        // que para que la primera quede **centrada** el contenido tiene que
        // empezar exactamente a esa distancia del borde. Sin esto, con una
        // sola foto la imagen se quedaba pegada a la izquierda.
        .contentMargins(.horizontal, Self.peek + Self.spacing, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .wkBleedingStrip()
        .task { if focused == nil { focused = 0 } }
    }

    // MARK: Lo que ha salido

    /// Los recortes de la foto que se está mirando.
    ///
    /// En una tira y no en una rejilla: son tres o cuatro por foto, y una
    /// rejilla de tres celdas deja media pantalla en blanco debajo de la foto.
    private var cutouts: some View {
        VStack(spacing: WK.Spacing.xs) {
            ScrollView(.horizontal) {
                HStack(spacing: WK.Spacing.s) {
                    ForEach(model.candidates.filter { $0.photoIndex == current }) { candidate in
                        DetectedCell(
                            candidate: candidate,
                            onToggle: { model.setKeep(!candidate.isKept, forCandidateWithID: candidate.id) },
                            onRecrop: {
                                recropping = candidate.id
                                isCroppingByHand = true
                            },
                            onDiscard: { model.discard(candidateWithID: candidate.id) },
                            onImprove: { await model.restyle(candidateWithID: candidate.id) }
                        )
                    }

                }
                .padding(.horizontal, WK.Spacing.screenInset)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .wkBleedingStrip()
        }
        .animation(WKAnimation.arrival, value: model.candidates.count)
        .animation(WKAnimation.content, value: current)
    }

    /// Las dos salidas cuando lo detectado no vale.
    ///
    /// **Reintentar** porque el detector no da siempre lo mismo: depende de
    /// qué tenga ocupada la ANE y de cuánto le dé tiempo, así que volver a
    /// mirar la misma foto cambia el resultado más veces de las que parece.
    /// **Recortar a mano** porque cuando no lo cambia, ya está claro que esa
    /// foto hay que rodearla con el dedo.
    private var tools: some View {
        HStack(spacing: WK.Spacing.s) {
            Button {
                recropping = nil
                isCroppingByHand = true
            } label: {
                Label("recortar a mano", systemImage: "lasso")
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.primaryText)
                    .padding(.horizontal, WK.Spacing.m)
                    .padding(.vertical, WK.Spacing.s)
                    .background(WK.Palette.ink(0.07), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(WKPressStyle())

            Button {
                Task { await model.reanalyse(photoAt: current) }
            } label: {
                Label(
                    model.reanalysing == current
                        // Qué está probando, porque no es lo mismo otra vez:
                        // "separando piezas" o "siendo más estricto".
                        ? (model.reanalysingLabel ?? "mirando otra vez…")
                        : "reintentar",
                    systemImage: "arrow.clockwise"
                )
                .font(WK.Font.callout)
                .foregroundStyle(WK.Palette.primaryText)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .background(WK.Palette.ink(0.07), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(WKPressStyle())
            .disabled(model.reanalysing != nil)
        }
        .animation(WKAnimation.content, value: model.reanalysing)
    }

    /// La línea de debajo de la foto, donde antes iba el texto del análisis.
    private var caption: some View {
        VStack(spacing: 2) {
            Text(
                model.searchingInRegion
                    ? "Levantando la prenda de lo que has rodeado…"
                    : model.manualCropMissed
                        ? "No hemos encontrado ninguna prenda en lo que has rodeado. Prueba con un poco más de margen."
                    : model.candidates.isEmpty
                        ? "No hemos visto ninguna prenda: rodéala con el dedo."
                        : "Mueve o estira un recuadro, y quita con la X lo que no sea ropa."
            )
            .font(WK.Font.callout)
            .foregroundStyle(WK.Palette.secondaryText)
            .multilineTextAlignment(.center)

            if photos.count > 1 {
                Text("Foto \(current + 1) de \(photos.count)")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
                    .contentTransition(.numericText(value: Double(current)))
                    .animation(WKAnimation.content, value: current)
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
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
    /// Redibujar la prenda fuera. Ver `ImportModel.restyle`.
    let onImprove: () async -> Void

    var body: some View {
        VStack(spacing: WK.Spacing.xs) {
            cell
            improveButton
        }
    }

    /// **Mejorar, al lado de la prenda.**
    ///
    /// Aquí y no escondido en la ficha: es mirando el recorte cuando se ve que
    /// le falta media manga, y es entonces cuando se quiere pedir que lo
    /// redibujen. Se pide **a mano y de una en una**: cada una es una petición
    /// que se paga, así que no se lanza sola por el hecho de mirar la prenda.
    @ViewBuilder
    private var improveButton: some View {
        if candidate.canRestyle {
            WKProgressPill(
                candidate.isRestyling ? "mejorando…" : "mejorar",
                symbol: "wand.and.sparkles",
                isWorking: candidate.isRestyling,
                size: .compact
            ) {
                Task { await onImprove() }
            }
            .animation(WKAnimation.content, value: candidate.isRestyling)
        } else {
            Label("mejorada", systemImage: "checkmark")
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
                .padding(.vertical, 5)
        }
    }

    private var cell: some View {
        Button(action: onToggle) {
            candidate.previewImage
                .resizable()
                .scaledToFit()
                // **Todas iguales.** El recorte de una zapatilla es ancho y el
                // de un vestido, alto: dejando que cada celda midiera lo suyo,
                // la rejilla salía con filas de alturas distintas y parecía
                // rota. Con la celda cuadrada y la imagen ajustada dentro,
                // todas ocupan lo mismo y lo que cambia es la prenda.
                .padding(WK.Spacing.xs)
                .frame(width: 92, height: 92)
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
                .overlay {
                    if candidate.isRestyling {
                        ProgressView().controlSize(.small).tint(WK.Palette.accent)
                    }
                }
                .wkShimmer(isActive: candidate.isRestyling)
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

// **La celda de rodear a mano, retirada.** Ahora es un botón debajo de la
// foto, junto a reintentar: un hueco de puntos al final de la tira de
// recortes se leía como "aquí falta una prenda" en vez de como una acción.
// Se queda comentada por si vuelve a hacer falta.
//
// /// Añadir una prenda que el detector no vio.
// private struct AddByHandCell: View {
//     let action: () -> Void
//
//     var body: some View {
//         Button(action: action) {
//             VStack(spacing: WK.Spacing.xs) {
//                 Image(systemName: "lasso")
//                     .font(.title2)
//                 Text("Rodear a mano")
//                     .font(WK.Font.caption)
//             }
//             .foregroundStyle(WK.Palette.secondaryText)
//             .frame(width: 92, height: 92)
//             .background {
//                 RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
//                     .strokeBorder(
//                         WK.Palette.ink(0.15),
//                         style: StrokeStyle(lineWidth: 2, dash: [6, 5])
//                     )
//             }
//             .contentShape(.rect)
//         }
//         .buttonStyle(WKPressStyle())
//     }
// }
