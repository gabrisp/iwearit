import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Con qué prendas quieres que monte.
///
/// ## Para qué
///
/// Porque a veces la idea ya la tienes a medias: sabes que quieres ponerte
/// estas zapatillas, o esta camisa que te acabas de comprar, y lo que falta es
/// el resto. Eligiéndolas aquí, todos los conjuntos las llevan y lo demás se
/// monta alrededor.
///
/// Es lo mismo que decírselo al estilista por escrito —"con las zapatillas
/// blancas"—, pero señalando, que para dos prendas es más rápido que
/// describirlas.
///
/// ## Tres como mucho
///
/// Con cuatro ya no queda nada que proponer: el conjunto está puesto y lo que
/// devolvería es esas cuatro prendas otra vez.
struct InspoAnchorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment

    /// Lo que había elegido, para poder quitarlo.
    let initial: Set<UUID>
    let onDone: (Set<UUID>) -> Void

    @Query(FetchDescriptor<Garment>.visibleGarments())
    private var garments: [Garment]

    @State private var picked: Set<UUID> = []

    static let limit = 3

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: WK.Spacing.m)],
                    spacing: WK.Spacing.l
                ) {
                    ForEach(garments) { garment in
                        AnchorCell(
                            garment: garment,
                            store: appEnvironment.imageStore,
                            isPicked: picked.contains(garment.id)
                        ) {
                            toggle(garment)
                        }
                    }
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.vertical, WK.Spacing.m)
            }
            .scrollIndicators(.hidden)
            .background(WK.Palette.canvas.ignoresSafeArea())
            .navigationTitle(picked.isEmpty ? "Con estas prendas" : "\(picked.count) de \(Self.limit)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(WK.Palette.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onDone(picked)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .tint(WK.Palette.primaryText)
                    .adaptiveProminentButton()
                }
            }
        }
        .task { picked = initial }
    }

    /// Al llegar al tope, la más antigua deja su sitio: así seguir tocando
    /// nunca se queda sin efecto, que es lo que se siente cuando un botón
    /// deja de responder sin decir por qué.
    private func toggle(_ garment: Garment) {
        withAnimation(WKAnimation.selection) {
            if picked.contains(garment.id) {
                picked.remove(garment.id)
            } else {
                if picked.count >= Self.limit, let first = picked.first { picked.remove(first) }
                picked.insert(garment.id)
            }
        }
    }
}

/// Una prenda que se puede marcar. Sin recuadro: se marca como dentro de una
/// balda, creciendo y con el check.
private struct AnchorCell: View {
    let garment: Garment
    let store: ImageStore
    let isPicked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            StoredImage(
                key: garment.normalizedImageKey,
                variant: .thumb,
                store: store,
                alignment: .bottom,
                shadow: isPicked
                    ? .init(opacity: 0.85, radius: 12, y: 0, tint: WK.Palette.accent)
                    : .init(opacity: 0.5, radius: 6, y: 3)
            )
            .frame(height: 104)
            .scaleEffect(isPicked ? 1 : 0.88)
            .overlay(alignment: .topTrailing) {
                if isPicked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WK.Palette.onAccent)
                        .frame(width: 24, height: 24)
                        .background(WK.Palette.accent, in: .circle)
                }
            }
            .animation(WKAnimation.selection, value: isPicked)
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}
