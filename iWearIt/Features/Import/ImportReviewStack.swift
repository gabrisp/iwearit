import CoreGraphics
import SwiftUI
import UIKit
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
    /// Añadir más fotos a la misma importación.
    var onAddMore: (() -> Void)?
    /// Guardar las prendas de la lista.
    let onSave: () async -> Void

    /// Qué prenda se está editando entera. Tocar la tarjeta abre su ficha.
    @State private var opened: UUID?
    @State private var isSaving = false

    /// Las dos salidas de la pantalla, abajo y del tamaño del pulgar.
    ///
    /// Guardar no vive en la barra de navegación porque no es una
    /// confirmación de trámite: es el final de todo el proceso de importar, y
    /// va donde está la mano.
    private var actions: some View {
        HStack(spacing: WK.Spacing.s) {
            if let onAddMore {
                Button(action: onAddMore) {
                    Label("Agregar más", systemImage: "plus")
                        .font(WK.Font.callout)
                        .foregroundStyle(WK.Palette.primaryText)
                        .padding(.horizontal, WK.Spacing.l)
                        .padding(.vertical, WK.Spacing.m)
                        .background(WK.Palette.canvas, in: .capsule)
                        .overlay(Capsule().stroke(WK.Palette.ink(0.10), lineWidth: 1))
                        .contentShape(.capsule)
                }
                .buttonStyle(WKPressStyle())
            }

            WKPrimaryButton(model.candidates.isEmpty ? "Nada que guardar" : "Guardar") {
                isSaving = true
                Task { await onSave() }
            }
            .disabled(model.candidates.isEmpty || isSaving)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.s)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: WK.Spacing.m) {
                ForEach(model.candidates) { candidate in
                    ImportGarmentCard(
                        candidate: candidate,
                        onDiscard: {
                            withAnimation(WKAnimation.content) {
                                model.discard(candidateWithID: candidate.id)
                            }
                        },
                        onImprove: { await model.restyle(candidateWithID: candidate.id) },
                        // La tarjeta entera abre la ficha: aquí caben cuatro
                        // datos, y a veces hace falta el resto —rodearla otra
                        // vez, mirarla contra la foto— sin salir de la
                        // importación.
                        onOpen: { opened = candidate.id }
                    )
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.top, WK.Spacing.m)
            .padding(.bottom, WK.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas)
        .adaptiveSafeAreaBar(edge: .bottom) { actions }
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
                        onChangeSeasons: { model.setSeasons($0, forCandidateWithID: candidate.id) },
                        onChangeSubcategory: { model.setSubcategory($0, forCandidateWithID: candidate.id) },
                        onChangeMaterial: { model.setMaterial($0, forCandidateWithID: candidate.id) },
                        onToggleKeep: { model.setKeep($0, forCandidateWithID: candidate.id) },
                        onManualCrop: { model.setManualCrop($0, forCandidateWithID: candidate.id) },
                        onRestyle: { await model.restyle(candidateWithID: candidate.id) }
                    )
                    .navigationTitle("Prenda")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Listo") { opened = nil }
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
    let onDiscard: () -> Void
    let onImprove: () async -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: WK.Spacing.m) {
            thumbnail

            VStack(alignment: .leading, spacing: WK.Spacing.xs) {
                swatch
                Text(headline)
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if !candidate.tags.isEmpty {
                    Text(candidate.tags.joined(separator: " · "))
                        .font(WK.Font.caption)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .lineLimit(1)
                }

                if let duplicateOf = candidate.duplicateOf {
                    Label("Ya tienes una parecida: \(duplicateOf)", systemImage: "square.on.square")
                        .font(WK.Font.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }

                HStack(spacing: WK.Spacing.s) {
                    improveButton
                    Spacer(minLength: 0)
                    discardButton
                }
                .padding(.top, WK.Spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(WK.Spacing.s)
        .frame(maxWidth: .infinity)
        .background(
            WK.Palette.shelf,
            in: .rect(cornerRadius: WK.Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WK.Radius.card, style: .continuous)
                .stroke(WK.Palette.ink(0.06), lineWidth: 1)
        }
        // Toda la tarjeta abre la ficha; los botones de dentro siguen a lo
        // suyo porque un `Button` se queda el toque antes que el gesto.
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
    }

    private var thumbnail: some View {
        candidate.previewImage
            .resizable()
            .scaledToFit()
            .padding(WK.Spacing.xs)
            .frame(width: 104, height: 128)
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
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(WK.Palette.ink(0.12), lineWidth: 1))
        }
    }

    /// "Chaquetas · Entretiempo": dónde va y cuánto abriga.
    private var headline: String {
        [
            ImportCandidateLabels.label(for: candidate.kind),
            GarmentVocabulary.Warmth.from(candidate.seasons).label,
        ].joined(separator: " · ")
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
                .font(WK.Font.callout)
                .foregroundStyle(WK.Palette.primaryText)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .background(WK.Palette.ink(0.07), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(WKPressStyle())
            .disabled(candidate.isRestyling)
        } else {
            Label("mejorada", systemImage: "checkmark")
                .font(WK.Font.callout)
                .foregroundStyle(WK.Palette.secondaryText)
        }
    }

    /// **Tirarla, no desmarcarla.** Aquí ya no hay "se va a guardar": lo que
    /// está en la lista entra, y lo que no es ropa se va con la papelera.
    private var discardButton: some View {
        Button(action: onDiscard) {
            Image(systemName: "trash")
                .font(WK.Font.callout)
                .foregroundStyle(.red)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.red.opacity(0.12)))
                .contentShape(.circle)
        }
        .buttonStyle(WKPressStyle())
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
