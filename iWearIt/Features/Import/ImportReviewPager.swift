import CoreGraphics
import SwiftUI
import WKCore
import WKDesign
import WKVision

/// Revisar **varias** prendas detectadas, una ficha por prenda.
///
/// ## Por qué se tiró la lista
///
/// Lo que había era una lista: miniatura de 64 puntos, un menú de tipo y una
/// casilla. Con eso no se puede decidir nada. No se veía el recorte —a ese
/// tamaño una camiseta partida por la mitad parece una camiseta—, no se podía
/// corregir el nombre ni el color, y la única acción real era marcar y
/// desmarcar. El usuario acababa guardando a ciegas y arreglando después en el
/// armario, prenda por prenda.
///
/// Y ya existía la pantalla buena: la ficha que se enseña cuando la foto trae
/// **una** prenda, con la imagen grande, el conmutador de recorte/catálogo/foto
/// y el nombre y el color escribibles. Lo que no tenía sentido era tener dos
/// calidades de revisión según cuántas prendas hubiera salido en la foto.
///
/// Así que aquí se pagina esa misma ficha. Lo único que añade esta pantalla es
/// lo que de verdad cambia con varias: **en cuál estás** y **cuáles te
/// quedas**.
struct ImportReviewPager: View {
    let model: ImportModel
    let photo: CGImage

    /// En qué prenda está puesta la vista. Compartido con la tira de arriba,
    /// que es a la vez índice y atajo: tocar una miniatura salta a su ficha.
    @State private var current: UUID?

    /// Lo que mide la tira. Se mide y no se fija: cambia con el tipo de letra
    /// del sistema, y con un número a mano la reserva de abajo se queda corta
    /// justo en los tamaños grandes.
    @State private var stripHeight: CGFloat = 96

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(model.candidates) { candidate in
                    ImportPagerPage(
                        model: model,
                        candidate: candidate,
                        photo: photo,
                        isCurrent: candidate.id == current,
                        topInset: stripHeight
                    )
                    .id(candidate.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $current)
        .scrollIndicators(.hidden)
        // **Encima, sin recortar.** En un `VStack` la tira quedaba dentro de su
        // celda y el aro de la miniatura elegida —que se sale un par de puntos
        // por arriba— salía cortado.
        .overlay(alignment: .top) {
            ImportCandidateStrip(
                candidates: model.candidates,
                current: $current,
                onToggleKeep: { id, keep in model.setKeep(keep, forCandidateWithID: id) }
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured in
                guard measured > 0, abs(measured - stripHeight) > 0.5 else { return }
                stripHeight = measured
            }
        }
        .background(WK.Palette.canvas)
        .task {
            // Empieza en la primera, pero solo si no hay ninguna puesta: al
            // volver de editar no tiene que saltar al principio.
            if current == nil { current = model.candidates.first?.id }
        }
    }
}

/// Una página del pager: la ficha de una prenda, con el hueco de la tira.
///
/// Vista aparte y no un bloque dentro del `ForEach` por dos razones: el
/// compilador no llega a comprobar la expresión entera de una sola pieza, y
/// pasar de página no tiene por qué reevaluar las fichas vecinas.
private struct ImportPagerPage: View {
    let model: ImportModel
    let candidate: ImportCandidate
    let photo: CGImage
    let isCurrent: Bool
    let topInset: CGFloat

    var body: some View {
        ImportSingleCard(
            candidate: candidate,
            photo: photo,
            isKept: candidate.isKept,
            onChangeKind: { model.setKind($0, forCandidateWithID: candidate.id) },
            onChangeName: { model.setName($0, forCandidateWithID: candidate.id) },
            onChangeColor: { model.setColorName($0, forCandidateWithID: candidate.id) },
            // **Solo la que estás mirando pide su reconstrucción.** Cada una es
            // una petición facturable, y el detector se equivoca hacia arriba:
            // un pantalón partido en tres serían tres facturas por una foto mal
            // detectada.
            generatesCatalog: isCurrent,
            onToggleKeep: { model.setKeep($0, forCandidateWithID: candidate.id) },
            onManualCrop: { model.setManualCrop($0, forCandidateWithID: candidate.id) },
            onRestyle: { await model.restyle(candidateWithID: candidate.id) }
        )
        // El hueco de la tira, reservado **dentro de cada ficha**: la tira flota
        // por encima —si no, su contenedor le recorta el borde de la miniatura
        // elegida— y lo que flota no aparta nada por su cuenta.
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: topInset)
        }
        // Cada ficha ocupa una pantalla exacta: es lo que hace que el gesto se
        // sienta como pasar de prenda y no como un scroll que se para donde le
        // apetece.
        .containerRelativeFrame(.horizontal)
    }
}

/// La tira de arriba: cuántas hay, en cuál estás y cuáles entran.
///
/// Vista propia porque cambia con cada gesto de paginación, y tenerla dentro
/// del pager reevaluaría las fichas —con sus imágenes— en cada desplazamiento.
private struct ImportCandidateStrip: View {
    let candidates: [ImportCandidate]
    @Binding var current: UUID?
    let onToggleKeep: (UUID, Bool) -> Void

    private var keptCount: Int { candidates.count(where: \.isKept) }

    var body: some View {
        VStack(spacing: WK.Spacing.xs) {
            Text("\(keptCount) de \(candidates.count) se van a guardar")
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
                .contentTransition(.numericText())
                .animation(WKAnimation.selection, value: keptCount)

            ScrollView(.horizontal) {
                HStack(spacing: WK.Spacing.s) {
                    ForEach(candidates) { candidate in
                        ImportCandidateThumb(
                            candidate: candidate,
                            isCurrent: candidate.id == current,
                            onTap: {
                                withAnimation(WKAnimation.content) { current = candidate.id }
                            },
                            onToggleKeep: { onToggleKeep(candidate.id, !candidate.isKept) }
                        )
                    }
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                // Aire arriba y abajo **dentro** del scroll: el aro de la
                // elegida se sale del cuadrado, y sin este margen el scroll se
                // lo come por el canto.
                .padding(.vertical, WK.Spacing.xs)
            }
            .scrollIndicators(.hidden)
            .wkBleedingStrip()
            // **Sin recortar.** El aro de la miniatura elegida se sale por
            // arriba y por abajo, y un `ScrollView` recorta por los cuatro
            // lados: se veía cortado justo en la que estás mirando.
            .scrollClipDisabled()
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.vertical, WK.Spacing.s)
        // **Sin superficie.** Flota sobre la ficha y el contenido pasa por
        // debajo, como el resto de barras de la app.
    }
}

/// Una miniatura de la tira.
///
/// El toque **salta a su ficha** y no la marca: marcar desde aquí sería decidir
/// sobre una prenda que se está viendo a 54 puntos, que es justo lo que hacía
/// inútil la lista de antes. Para quitarla está el toque largo —y el botón
/// grande de la ficha, donde sí se la ve.
private struct ImportCandidateThumb: View {
    let candidate: ImportCandidate
    let isCurrent: Bool
    let onTap: () -> Void
    let onToggleKeep: () -> Void

    var body: some View {
        Button(action: onTap) {
            candidate.image
                .resizable()
                .scaledToFit()
                .padding(WK.Spacing.xs)
                .frame(width: 54, height: 62)
                .background {
                    RoundedRectangle(cornerRadius: WK.Radius.small, style: .continuous)
                        .fill(WK.Palette.ink(isCurrent ? 0.10 : 0.04))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: WK.Radius.small, style: .continuous)
                        .stroke(WK.Palette.accent, lineWidth: isCurrent ? 2 : 0)
                }
                // Descartada: se ve, pero apagada. Quitarla de la tira haría
                // desaparecer la forma de recuperarla.
                .opacity(candidate.isKept ? 1 : 0.35)
                .overlay(alignment: .topTrailing) {
                    if !candidate.isKept {
                        Image(systemName: "slash.circle.fill")
                            .font(.caption)
                            .foregroundStyle(WK.Palette.secondaryText)
                            .padding(2)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
        .onLongPressGesture { onToggleKeep() }
        .animation(WKAnimation.selection, value: isCurrent)
        .animation(WKAnimation.selection, value: candidate.isKept)
    }
}
