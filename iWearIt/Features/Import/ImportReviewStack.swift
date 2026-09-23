import CoreGraphics
import PhotosUI
import SwiftUI
import UIKit
import WKVision
import WKCore
import WKDesign

/// Lo que se va a importar, una tarjeta debajo de otra.
///
/// ## Por qué no el pager
///
/// Con varias prendas la revisión era un scroll horizontal de fichas y, dentro
/// de cada una, otro scroll vertical. Dos scrolls cruzados para mirar cuatro
/// camisetas: no se sabía cuántas había sin pasarlas todas, y el gesto se
/// peleaba consigo mismo en los bordes.
///
/// Aquí se ven todas y se baja una vez. Cada tarjeta lleva lo justo: la prenda,
/// qué es, de qué color, de qué material, y las dos decisiones —quitarla del
/// lote o pedir que la redibujen—. Lo demás se edita luego en la ficha de la
/// prenda, que existe precisamente para eso.
///
/// El pager anterior se queda en `ImportReviewPager`, sin llamar: ver la nota
/// de ese fichero.
struct ImportReviewStack: View {
    let model: ImportModel
    let photos: [CGImage]
    /// Añadir más fotos a la misma importación: ya leídas y derechas.
    var onAddMore: (([CGImage]) async -> Void)?
    /// Guardar las prendas de la lista.
    let onSave: () async -> Void

    /// Qué prenda se está editando entera. Tocar la tarjeta abre su ficha.
    @State private var opened: UUID?
    @State private var isSaving = false
    /// Los botones de abajo, que aparecen un instante después de la lista.
    @State private var showsActions = false
    /// La galería de "Agregar más", **colgada del propio botón**. Puesta más
    /// arriba —en la hoja de importar— no llegaba a abrirse: el botón está
    /// dentro de otra jerarquía de presentación y el aviso se perdía por el
    /// camino. Es el mismo arreglo que el "+" del armario.
    @State private var isPickingMore = false
    @State private var morePhotos: [PhotosPickerItem] = []
    /// El sitio de la tarjeta de carga, para poder bajar hasta ella.
    private static let addingID = "adding-photos"

    private var saveTitle: String {
        let kept = model.keptCount
        if kept == 0 { return "Nada que guardar" }
        if kept == model.candidates.count { return "Guardar todo" }
        return kept == 1 ? "Guardar 1 prenda" : "Guardar \(kept) prendas"
    }

    /// Las fotos añadidas, derechas, a la importación que ya hay.
    private func loadMore() async {
        guard !morePhotos.isEmpty, let onAddMore else { return }
        let picked = morePhotos
        // **Vaciar al final, no al principio.** Esta tarea va atada a cuántas
        // fotos hay elegidas: vaciar la lista nada más empezar cambiaba ese
        // número, SwiftUI cancelaba la tarea en marcha y la lectura de las
        // fotos volvía vacía. Las prendas de "Agregar más" no llegaban nunca.
        defer { morePhotos = [] }
        var images: [CGImage] = []
        for item in picked {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UprightImage.cgImage(from: data)
            else { continue }
            images.append(image)
        }
        guard !images.isEmpty else { return }
        // **El análisis, suelto.** Leer las fotos es un momento; analizarlas
        // son veinte segundos por foto, y hacerlo dentro de la tarea del
        // botón lo ataba a la vida del botón: cualquier cosa que la cancelara
        // —la hoja de la galería al cerrarse, un redibujado— cortaba el
        // análisis a medias y la prenda no llegaba nunca a la lista. Por
        // separado, como cuando se importa de cero, no le pasa.
        Task { await onAddMore(images) }
    }

    /// Las dos salidas de la pantalla, abajo y del tamaño del pulgar.
    ///
    /// Guardar no vive en la barra de navegación porque no es una
    /// confirmación de trámite: es el final de importar, y va donde está la
    /// mano. Los dos en cristal **interactivo** —se hunden y se iluminan al
    /// tocarlos— porque flotan sobre la lista, que sigue pasando por debajo.
    private var actions: some View {
        AdaptiveGlassContainer(spacing: WK.Spacing.s) {
        HStack(spacing: WK.Spacing.s) {
            if onAddMore != nil, showsActions {
                Button { isPickingMore = true } label: {
                    Label("Agregar más", systemImage: "plus")
                        .font(WK.Font.callout)
                        .foregroundStyle(WK.Palette.primaryText)
                        .padding(.horizontal, WK.Spacing.l)
                        .padding(.vertical, WK.Spacing.m)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .adaptiveGlassInteractive(in: .capsule)
                .photosPicker(
                    isPresented: $isPickingMore,
                    selection: $morePhotos,
                    maxSelectionCount: 10,
                    matching: .images
                )
                .task(id: morePhotos.count) { await loadMore() }
                .adaptiveGlassMaterialize()
            }

            if showsActions {
            Button {
                isSaving = true
                Task { await onSave() }
            } label: {
                // "Guardar todo" si entran todas; si no, cuántas.
                Text(saveTitle)
                    .font(WK.Font.headline)
                    .foregroundStyle(WK.Palette.onAccent)
                    // El número gira en su sitio al marcar o desmarcar, en vez
                    // de cambiar la etiqueta de golpe.
                    .contentTransition(.numericText(value: Double(model.keptCount)))
                    .animation(WKAnimation.content, value: model.keptCount)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WK.Spacing.m)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            // Cristal **interactivo**, como Agregar más: se hunde y se
            // ilumina al tocarlo. El que tenía era cristal quieto.
            .adaptiveGlassProminent(tint: WK.Palette.accent, in: .capsule)
            .disabled(model.keptCount == 0 || isSaving)
            .opacity(model.keptCount == 0 || isSaving ? 0.5 : 1)
            .adaptiveGlassMaterialize()
            }
        }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.s)
        // **Se forman después de la lista**, no con ella: primero se ve qué ha
        // salido, y luego qué se puede hacer con ello.
        .onAppear {
            withAnimation(.smooth(duration: 0.45).delay(0.2)) { showsActions = true }
        }
    }

    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: WK.Spacing.m) {
                ForEach(model.candidates) { candidate in
                    ImportGarmentCard(
                        candidate: candidate,
                        onToggleKeep: {
                            withAnimation(WKAnimation.selection) {
                                model.setKeep(!candidate.isKept, forCandidateWithID: candidate.id)
                            }
                        },
                        onImprove: { await model.restyle(candidateWithID: candidate.id) },
                        // La tarjeta entera abre la ficha: aquí caben cuatro
                        // datos, y a veces hace falta el resto —rodearla otra
                        // vez, mirarla contra la foto— sin salir de la
                        // importación.
                        onOpen: { opened = candidate.id }
                    )
                    .id(candidate.id)
                    // Entra deslizándose desde abajo, no de golpe.
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // **La carga de "Agregar más", al final de la lista**, que es
                // donde van a aparecer las prendas. Cristal, con cuántas fotos
                // quedan y una barra que avanza con cada una; la lista baja
                // hasta ella al empezar.
                if model.addingTotal > 0 {
                    AddingPhotosCard(done: model.addingDone, total: model.addingTotal)
                        .id(Self.addingID)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.45), value: model.candidates.count)
            .animation(.smooth(duration: 0.45), value: model.addingTotal > 0)
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.top, WK.Spacing.m)
            .padding(.bottom, WK.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas)
        // **Hasta la nueva, sin saltos.** Cuando "Agregar más" trae una
        // prenda, la lista baja hasta ella con calma: aparecía fuera de la
        // pantalla y no se sabía que había llegado.
        .onChange(of: model.candidates.count) { old, new in
            guard new > old, let last = model.candidates.last else { return }
            withAnimation(.smooth(duration: 0.5)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
        // Al empezar a analizar, hasta la tarjeta de carga.
        .onChange(of: model.addingTotal > 0) { _, isAdding in
            guard isAdding else { return }
            withAnimation(.smooth(duration: 0.5)) {
                proxy.scrollTo(Self.addingID, anchor: .bottom)
            }
        }
        }
        // La carga ya no va en medio de la pantalla sino al final de la lista:
        // se queda comentado.
        // .overlay {
        //     if model.addingTotal > 0 {
        //         AddingPhotosCard(done: model.addingDone, total: model.addingTotal)
        //     }
        // }
        .adaptiveSafeAreaBar(edge: .bottom) { actions }
        // Que la tarjeta se abre no lo dice nada en pantalla: parece una
        // lista de lo que se va a guardar y es además el sitio donde ajustar
        // cada prenda.
        .wkTip(.reviewCard, in: appEnvironment.tips)
        .sheet(item: $opened) { id in
            if let candidate = model.candidates.first(where: { $0.id == id }) {
                NavigationStack {
                    ImportSingleCard(
                        candidate: candidate,
                        photo: model.photo(for: candidate) ?? photos[0],
                        isKept: candidate.isKept,
                        onChangeKind: { model.setKind($0, forCandidateWithID: candidate.id) },
                        onChangeName: { model.setName($0, forCandidateWithID: candidate.id) },
                        onChangeColor: { model.setColorName($0, forCandidateWithID: candidate.id) },
                        onPickColor: { picked in
                            let rgb = UIColor(picked).rgb
                            model.setColor(
                                red: rgb.red, green: rgb.green, blue: rgb.blue,
                                forCandidateWithID: candidate.id
                            )
                        },
                        onChangeTags: { model.setTags($0, forCandidateWithID: candidate.id) },
                        onChangeCut: { model.setCut($0, forCandidateWithID: candidate.id) },
                        onChangeCategory: { model.setCategory($0, forCandidateWithID: candidate.id) },
                        onChangeSeasons: { model.setSeasons($0, forCandidateWithID: candidate.id) },
                        onChangeSubcategory: { model.setSubcategory($0, forCandidateWithID: candidate.id) },
                        onChangeMaterial: { model.setMaterial($0, forCandidateWithID: candidate.id) },
                        onToggleKeep: { model.setKeep($0, forCandidateWithID: candidate.id) },
                        onManualCrop: { cropped in
                            Task { await model.setManualCrop(cropped, forCandidateWithID: candidate.id) }
                        },
                        onRestyle: { await model.restyle(candidateWithID: candidate.id) }
                    )
                    .navigationTitle("Editar")
                    .navigationBarTitleDisplayMode(.inline)
                    // Como la hoja de editar: una X y nada más. Lo cambiado ya
                    // está cambiado; no hay nada que confirmar.
                    .navigationBarBackButtonHidden()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { opened = nil } label: {
                                Image(systemName: "xmark")
                                    .font(WK.Font.headline)
                                    .contentShape(.rect)
                            }
                            .tint(WK.Palette.primaryText)
                        }
                    }
                }
            }
        }
    }
}

/// Una prenda a punto de entrar al armario.
///
/// La prenda a la izquierda y lo que se sabe de ella a la derecha: en qué
/// parte va, cuánto abriga y con qué pega. Nada de nombre —ver
/// `ImportModel.displayName`— y nada de nombre de color: la muestra lo dice
/// mejor. Tocar la tarjeta abre la ficha entera.
private struct ImportGarmentCard: View {
    let candidate: ImportCandidate
    /// Marcar o desmarcar: solo se guardan las marcadas.
    let onToggleKeep: () -> Void
    let onImprove: () async -> Void
    let onOpen: () -> Void

    /// El ancho de la franja de la casilla: el último ~18% de la tarjeta.
    private static let checkZone: CGFloat = 72

    var body: some View {
        // **Dos zonas, sin mezclarse.** Casi toda la tarjeta abre la ficha; la
        // franja de la derecha, a toda altura, marca y desmarca. Antes la
        // casilla era un círculo de 44 puntos dentro de una tarjeta que abría
        // la ficha, y tocar un poco al lado la abría en vez de desmarcar.
        HStack(spacing: 0) {
            HStack(spacing: WK.Spacing.m) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: WK.Spacing.xs) {
                    swatch
                    // El texto, del tamaño que le toca: es un dato de la
                    // prenda, no un titular. Con tipografía de título cada
                    // tarjeta gritaba "PARTE SUPERIOR" y lo que se mira de una
                    // tarjeta es la prenda.
                    Text(headline)
                        .font(WK.Font.callout)
                        .foregroundStyle(WK.Palette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                // Sin estilo: se queda comentado.
                // if !candidate.tags.isEmpty {
                //     Text(candidate.tags.joined(separator: " · "))
                //         .font(WK.Font.caption)
                //         .foregroundStyle(WK.Palette.tertiaryText)
                //         .lineLimit(1)
                // }

                // Cuánto abriga y de qué es: lo que se mira antes de guardar
                // sin tener que abrir la ficha.
                Text(details)
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .lineLimit(1)

                if candidate.duplicateOf != nil {
                    Text("Ya tienes una parecida")
                        .font(WK.Font.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }

                // Mejorar solo en la ficha de la prenda, no en la lista: aquí
                // se decide qué entra, y el botón competía con la casilla.
                // Se queda comentado.
                // improveButton
                //     .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // **Desmarcada, apagada entera.** No solo la casilla: todo lo de
            // su lado, para que de un vistazo se vea qué entra y qué no.
            .opacity(candidate.isKept ? 1 : 0.35)
            }
            .padding([.vertical, .leading], WK.Spacing.s)
            .contentShape(.rect)
            .onTapGesture(perform: onOpen)

            keepCheck
        }
        .frame(maxWidth: .infinity)
        .background(
            WK.Palette.shelf,
            in: .rect(cornerRadius: WK.Radius.card, style: .continuous)
        )
        .overlay {
            // Naranja si ya tienes una parecida: se ve de lejos, antes de leer
            // nada, y es justo lo que hay que mirar antes de guardarla.
            RoundedRectangle(cornerRadius: WK.Radius.card, style: .continuous)
                .stroke(
                    candidate.duplicateOf != nil ? Color.orange : WK.Palette.ink(0.06),
                    lineWidth: candidate.duplicateOf != nil ? 2 : 1
                )
        }
    }

    private var thumbnail: some View {
        candidate.previewImage
            .resizable()
            .scaledToFit()
            .padding(WK.Spacing.xs)
            .frame(width: 96, height: 112)
            .background(
                WK.Palette.ink(0.04),
                in: .rect(cornerRadius: WK.Radius.medium, style: .continuous)
            )
            .wkShimmer(isActive: candidate.isRestyling)
    }

    /// El color, sin palabra: sale de un k-means y ponerle nombre es donde se
    /// equivoca —un azul marino medido como negro—, y ese nombre se queda
    /// escrito y se busca por él.
    @ViewBuilder
    private var swatch: some View {
        if let color = candidate.colors.first {
            Circle()
                .fill(Color(red: color.red, green: color.green, blue: color.blue))
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(WK.Palette.ink(0.12), lineWidth: 1))
        }
    }

    /// **El nombre de la prenda**: el de la tienda si se leyó en la ficha,
    /// y si no el generado —"Pantalón rojo", "Polo Golden Goose"—. Es lo que
    /// se va a guardar, así que es lo que se lee antes de guardar.
    private var headline: String { candidate.displayName }

    // Antes: "Camiseta · Manga corta", qué es y su corte.
    // /// "Camiseta · Manga corta": qué es y su corte. La parte del cuerpo no
    // /// sale aquí: es un filtro para buscar, no un dato de la prenda.
    // ///
    // /// Si se leyó el nombre del producto en la ficha de la tienda, ese: es lo
    // /// que dice qué prenda es exactamente.
    // private var headline: String {
    //     if let productName = candidate.productName { return productName }
    //     return [
    //         candidate.subcategory?.capitalized ?? GarmentVocabulary.shelfName(for: candidate.kind),
    //         candidate.cut,
    //     ].compactMap { $0 }.joined(separator: " · ")
    // }

    /// "Manga corta · Entretiempo · Algodón · Zara". El corte vive aquí
    /// desde que el titular es el nombre.
    private var details: String {
        [
            candidate.cut,
            GarmentVocabulary.Warmth.label(for: candidate.seasons),
            candidate.material?.capitalized,
            candidate.detected.brand,
        ].compactMap { $0 }.joined(separator: " · ")
    }

    /// Redibujar la prenda fuera. A mano y de una en una: cada una se paga.
    @ViewBuilder
    private var improveButton: some View {
        if candidate.catalogImage == nil {
            Button { Task { await onImprove() } } label: {
                Label(
                    candidate.isRestyling ? "mejorando…" : "mejorar",
                    systemImage: "wand.and.sparkles"
                )
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.primaryText)
                .padding(.horizontal, WK.Spacing.s)
                .padding(.vertical, 7)
                .background(WK.Palette.ink(0.07), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(WKPressStyle())
            .disabled(candidate.isRestyling)
        } else {
            Label("mejorada", systemImage: "checkmark")
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
        }
    }

    /// **Marcada o no.** Sin papelera: las que no quieres se desmarcan y no
    /// se guardan, y si cambias de idea se vuelven a marcar — tirarlas era
    /// irreversible para algo que no hacía falta que lo fuera.
    private var keepCheck: some View {
        Button(action: onToggleKeep) {
            Image(systemName: candidate.isKept ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    candidate.isKept ? WK.Palette.onAccent : WK.Palette.tertiaryText,
                    candidate.isKept ? WK.Palette.accent : WK.Palette.ink(0.08)
                )
                .contentTransition(.symbolEffect(.replace))
                // La franja entera, de arriba abajo: es la zona de la casilla,
                // no un círculo que haya que acertar.
                .frame(width: Self.checkZone)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
        .sensoryFeedback(.selection, trigger: candidate.isKept)
    }
}

/// Una ficha tocable de la tarjeta.
private struct Chip: View {
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
                Text(value)
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, WK.Spacing.s)
            .padding(.vertical, 5)
            .background(WK.Palette.ink(0.05), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
    }
}


// `sheet(item:)` pide identidad, y un `UUID` **es** una identidad: envolverlo
// en un tipo nuevo solo para decirlo otra vez no aporta nada.
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}


// El color del selector, en números.
//
// `Color` no da sus componentes: son un espacio de color y un entorno, no tres
// números. `UIColor` sí, y aquí hacen falta tres números porque es lo que se
// guarda y lo que se compara contra la tabla de colores con nombre.
extension UIColor {
    var rgb: (red: Double, green: Double, blue: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}


/// Lo que se está analizando todavía, al final de la lista.
private struct PendingPhotosCard: View {
    let count: Int

    var body: some View {
        HStack(spacing: WK.Spacing.m) {
            RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                .fill(WK.Palette.ink(0.06))
                .frame(width: 96, height: 112)
                .wkShimmer(isActive: true)

            Text(count == 1 ? "Buscando prendas en 1 foto…" : "Buscando prendas en \(count) fotos…")
                .font(WK.Font.callout)
                .foregroundStyle(WK.Palette.secondaryText)
                .contentTransition(.numericText(value: Double(count)))

            Spacer(minLength: 0)
        }
        .padding(WK.Spacing.s)
        .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.card, style: .continuous))
        .animation(WKAnimation.content, value: count)
    }
}


/// "Analizando 3 fotos", con su barra, en medio de la pantalla.
private struct AddingPhotosCard: View {
    let done: Int
    let total: Int

    private var remaining: Int { max(total - done, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            HStack(spacing: WK.Spacing.xs) {
                Text("Analizando")
                Text("\(remaining)")
                    .contentTransition(.numericText(value: Double(remaining)))
                Text(remaining == 1 ? "foto" : "fotos")
            }
            .font(WK.Font.headline)
            .foregroundStyle(WK.Palette.primaryText)

            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(WK.Palette.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WK.Spacing.l)
        .adaptiveGlass(in: .rect(cornerRadius: WK.Radius.card, style: .continuous))
        .animation(WKAnimation.content, value: done)
    }
}
