import CoreGraphics
import SwiftUI
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

    @State private var editing: Target?

    /// Qué campo de qué prenda se está cambiando.
    struct Target: Identifiable {
        let candidate: UUID
        let field: Field
        var id: String { "\(candidate)-\(field.rawValue)" }
    }

    enum Field: String { case type, material }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: WK.Spacing.m) {
                ForEach(model.candidates) { candidate in
                    ImportGarmentCard(
                        candidate: candidate,
                        onToggleKeep: { model.setKeep($0, forCandidateWithID: candidate.id) },
                        onEditType: { editing = Target(candidate: candidate.id, field: .type) },
                        onEditMaterial: { editing = Target(candidate: candidate.id, field: .material) },
                        onImprove: { await model.restyle(candidateWithID: candidate.id) }
                    )
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.top, WK.Spacing.m)
            .padding(.bottom, WK.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas)
        .sheet(item: $editing) { target in
            if let candidate = model.candidates.first(where: { $0.id == target.candidate }) {
                sheet(for: target.field, of: candidate)
            }
        }
    }

    @ViewBuilder
    private func sheet(for field: Field, of candidate: ImportCandidate) -> some View {
        switch field {
        case .type:
            // Todas las prendas, no solo las de su parte del cuerpo: eligiendo
            // la prenda se corrige también dónde va, que es lo que solía estar
            // mal cuando estaba mal.
            WKChipSheet(
                title: "Qué prenda es",
                subtitle: "Manga larga, corta, vaqueros… lo que la distingue",
                options: GarmentVocabulary.allTypes.map { .init(id: $0, label: $0) }
                    + [.init(id: "", label: "Sin definir")],
                selection: Binding(
                    get: { Set([candidate.subcategory?.capitalized].compactMap { $0 }) },
                    set: { chosen in
                        let type = chosen.first?.isEmpty == false ? chosen.first : nil
                        model.setSubcategory(type, forCandidateWithID: candidate.id)
                        if let type, let kind = GarmentVocabulary.kind(forType: type) {
                            model.setKind(kind, forCandidateWithID: candidate.id)
                        }
                    }
                ),
                limit: 1
            )
        case .material:
            WKChipSheet(
                title: "Material",
                subtitle: "De qué está hecha, tal y como la llevas",
                options: GarmentVocabulary.materials.map { .init(id: $0, label: $0) }
                    + [.init(id: "", label: "Sin definir")],
                selection: Binding(
                    get: { Set([candidate.material?.capitalized].compactMap { $0 }) },
                    set: { model.setMaterial($0.first?.isEmpty == false ? $0.first : nil, forCandidateWithID: candidate.id) }
                ),
                limit: 1
            )
        }
    }
}

/// Una prenda a punto de entrar al armario.
private struct ImportGarmentCard: View {
    let candidate: ImportCandidate
    let onToggleKeep: (Bool) -> Void
    let onEditType: () -> Void
    let onEditMaterial: () -> Void
    let onImprove: () async -> Void

    var body: some View {
        VStack(spacing: WK.Spacing.s) {
            candidate.previewImage
                .resizable()
                .scaledToFit()
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .shadow(color: WK.Palette.ink(0.4), radius: 14, y: 8)
                .wkShimmer(isActive: candidate.isRestyling)
                .overlay(alignment: .topTrailing) { keepButton }
                .padding(.top, WK.Spacing.s)

            chips

            if let duplicateOf = candidate.duplicateOf {
                Label("Ya tienes una parecida: \(duplicateOf)", systemImage: "square.on.square")
                    .font(WK.Font.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, WK.Spacing.m)
        .padding(.bottom, WK.Spacing.m)
        .frame(maxWidth: .infinity)
        .background(
            WK.Palette.shelf,
            in: .rect(cornerRadius: WK.Radius.card, style: .continuous)
        )
        .opacity(candidate.isKept ? 1 : 0.5)
        .animation(WKAnimation.selection, value: candidate.isKept)
    }

    /// Quitarla del lote, o devolverla. Sin etiqueta que diga "se va a
    /// guardar": lo que está en la lista se guarda, y lo que no quieres se
    /// quita con la X.
    private var keepButton: some View {
        Button {
            withAnimation(WKAnimation.selection) { onToggleKeep(!candidate.isKept) }
        } label: {
            Image(systemName: candidate.isKept ? "xmark" : "arrow.uturn.backward")
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.primaryText)
                .frame(width: 32, height: 32)
                .background(Circle().fill(WK.Palette.ink(0.07)))
                .contentShape(.circle)
        }
        .buttonStyle(WKPressStyle())
    }

    /// Qué es, de qué color y de qué está hecha. El color no se toca aquí: se
    /// mide y se corrige en la ficha de la prenda, con la prenda delante.
    private var chips: some View {
        HStack(spacing: WK.Spacing.xs) {
            Chip(label: "Tipo", value: candidate.subcategory?.capitalized ?? "Sin definir", action: onEditType)

            if let color = candidate.colors.first {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: color.red, green: color.green, blue: color.blue))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(WK.Palette.ink(0.15), lineWidth: 1))
                    Text(color.nameKey.capitalized)
                        .font(WK.Font.caption)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, WK.Spacing.s)
                .padding(.vertical, 6)
                .background(WK.Palette.ink(0.05), in: .capsule)
            }

            Chip(
                label: "Material",
                value: candidate.material?.capitalized ?? "—",
                action: onEditMaterial
            )

            Spacer(minLength: 0)

            improveButton
        }
    }

    /// Redibujar la prenda fuera. A mano y de una en una: cada una se paga.
    @ViewBuilder
    private var improveButton: some View {
        if candidate.catalogImage == nil {
            Button { Task { await onImprove() } } label: {
                Image(systemName: "wand.and.sparkles")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.primaryText)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(WK.Palette.ink(0.07)))
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())
            .disabled(candidate.isRestyling)
        }
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
