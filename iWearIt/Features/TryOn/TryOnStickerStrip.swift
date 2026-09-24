import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// **Probados**, en la bandeja de stickers del editor: tus pruebas, para
/// ponerlas en el lienzo —sin fondo, la persona recortada; con escena, la
/// foto entera—. Primero las de este outfit, luego el resto.
struct TryOnStickerStrip: View {
    let outfit: Outfit
    let store: ImageStore
    let onAdded: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TryOnResult.createdAt, order: .reverse)
    private var results: [TryOnResult]

    /// Las de este outfit delante.
    private var ordered: [TryOnResult] {
        results.filter { $0.outfit?.id == outfit.id } + results.filter { $0.outfit?.id != outfit.id }
    }

    var body: some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: WK.Spacing.s) {
                Text("Probados")
                    .font(WK.Font.captionMedium)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .padding(.horizontal, WK.Spacing.m)
                ScrollView(.horizontal) {
                    HStack(spacing: WK.Spacing.s) {
                        ForEach(ordered) { result in
                            Button { Task { await add(result) } } label: {
                                Color.clear
                                    .frame(width: 60, height: 80)
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
                                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(WK.Palette.ink(0.08), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(WKPressStyle())
                        }
                    }
                    .padding(.horizontal, WK.Spacing.m)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func add(_ result: TryOnResult) async {
        let size = (try? await store.image(for: result.imageKey, variant: .display))
            .map { CGSize(width: $0.width, height: $0.height) } ?? CGSize(width: 3, height: 4)
        TryOnSticker.add(key: result.imageKey, imageSize: size, to: outfit, context: modelContext)
        onAdded()
    }
}
