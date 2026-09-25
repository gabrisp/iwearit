import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// **Probados**, como sticker: tus pruebas para ponerlas en el lienzo. Dos
/// secciones —las de este outfit y las demás—; tocar una la mete en el
/// lienzo, sin fondo o con su escena.
struct TryOnStickerSheet: View {
    let outfit: Outfit
    let store: ImageStore
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TryOnResult.createdAt, order: .reverse)
    private var results: [TryOnResult]

    private var mine: [TryOnResult] { results.filter { $0.outfit?.id == outfit.id } }
    private var others: [TryOnResult] { results.filter { $0.outfit?.id != outfit.id } }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: WK.Spacing.m)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if results.isEmpty {
                    Text(String(localized: "tryon.stickers.empty", defaultValue: "You haven't tried anything on yet. Open the fitting room from an outfit."))
                        .font(WK.Font.callout)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(WK.Spacing.xl)
                } else {
                    VStack(alignment: .leading, spacing: WK.Spacing.l) {
                        section(
                            String(localized: "tryon.stickers.thisOutfit", defaultValue: "From this outfit"),
                            items: mine,
                            empty: String(localized: "tryon.stickers.noneForOutfit", defaultValue: "Nothing tried on with this outfit yet.")
                        )
                        if !others.isEmpty {
                            section(String(localized: "tryon.stickers.others", defaultValue: "Others"), items: others, empty: nil)
                        }
                    }
                    .padding(WK.Spacing.screenInset)
                }
            }
            // Sin fondo propio —el cristal de la hoja, como las demás hojas
            // del lienzo— y sin indicadores de scroll.
            // .background(WK.Palette.canvas.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle(String(localized: "tryon.stickers.title", defaultValue: "Tried on"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(WK.Palette.primaryText)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func section(_ title: String, items: [TryOnResult], empty: String?) -> some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            Text(title)
                .font(WK.Font.headline)
                .foregroundStyle(WK.Palette.primaryText)
            if items.isEmpty, let empty {
                Text(empty)
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
            } else {
                LazyVGrid(columns: columns, spacing: WK.Spacing.m) {
                    ForEach(items) { result in
                        Button { Task { await add(result) } } label: {
                            Color.clear
                                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                                .overlay {
                                    StoredImage(key: result.imageKey, variant: .thumb, store: store)
                                        .scaledToFit()
                                }
                                .background {
                                    // Sin fondo, sobre el papel: se ve que entra recortada.
                                    if result.sceneRaw == TryOnScene.none.rawValue {
                                        TryOnPaper(outfit: result.outfit)
                                    } else {
                                        WK.Palette.shelf
                                    }
                                }
                                .clipShape(.rect(cornerRadius: WK.Radius.medium, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                                        .stroke(WK.Palette.ink(0.08), lineWidth: 1)
                                }
                        }
                        .buttonStyle(WKPressStyle())
                    }
                }
            }
        }
    }

    private func add(_ result: TryOnResult) async {
        let size = (try? await store.image(for: result.imageKey, variant: .display))
            .map { CGSize(width: $0.width, height: $0.height) } ?? CGSize(width: 3, height: 4)
        TryOnSticker.add(key: result.imageKey, imageSize: size, to: outfit, context: modelContext)
        onAdded()
        dismiss()
    }
}
