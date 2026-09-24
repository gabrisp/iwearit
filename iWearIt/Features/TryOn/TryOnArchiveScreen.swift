import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// **El archivo de probados**: todo lo que te has probado, de todos los
/// conjuntos, lo último primero.
///
/// Cada prueba ya se guardaba dentro de su outfit, pero para volver a verla
/// había que acordarse de qué outfit era y abrir su probador. Aquí están
/// todas juntas: se miran, se comparten y se borran.
struct TryOnArchiveScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(sort: \TryOnResult.createdAt, order: .reverse)
    private var results: [TryOnResult]

    /// La que está abierta en grande.
    @State private var open: TryOnResult?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: WK.Spacing.m)]

    var body: some View {
        ScrollView {
            if results.isEmpty {
                ContentUnavailableView(
                    "Aún no te has probado nada",
                    systemImage: "person.crop.rectangle.stack",
                    description: Text("Abre un outfit y toca el probador: lo que te pruebes se queda aquí.")
                )
                .padding(.top, WK.Spacing.xxl)
            } else {
                LazyVGrid(columns: columns, spacing: WK.Spacing.m) {
                    ForEach(results) { result in
                        Button { open = result } label: {
                            TryOnTile(result: result, store: appEnvironment.imageStore)
                        }
                        .buttonStyle(WKPressStyle())
                        .contextMenu {
                            Button(role: .destructive) { remove(result) } label: {
                                Label("Borrar", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.vertical, WK.Spacing.m)
            }
        }
        .background(WK.Palette.canvas.ignoresSafeArea())
        .navigationTitle("Probados")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $open) { result in
            TryOnViewer(result: result, store: appEnvironment.imageStore) {
                open = nil
                remove(result)
            }
        }
        .animation(WKAnimation.content, value: results.count)
    }

    /// Borra la prueba y su imagen.
    private func remove(_ result: TryOnResult) {
        let key = result.imageKey
        modelContext.delete(result)
        try? modelContext.save()
        Task { try? await appEnvironment.imageStore.delete(key: key) }
    }
}

/// Una prueba en la rejilla, con de qué outfit es y cuándo.
private struct TryOnTile: View {
    let result: TryOnResult
    let store: ImageStore

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.xs) {
            // El hueco 3:4 lo pone un `Color.clear` y la foto lo **rellena**:
            // las pruebas no miden todas lo mismo, y encajadas dejaban franjas.
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    StoredImage(key: result.imageKey, variant: .thumb, store: store)
                        .scaledToFill()
                }
                .frame(maxWidth: .infinity)
                .background(WK.Palette.shelf)
                .clipShape(.rect(cornerRadius: WK.Radius.medium, style: .continuous))
            Text(result.outfit?.name ?? "Outfit")
                .font(WK.Font.captionMedium)
                .foregroundStyle(WK.Palette.primaryText)
                .lineLimit(1)
            Text(result.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
        }
    }
}

/// Una prueba en grande, para compartirla o borrarla.
private struct TryOnViewer: View {
    let result: TryOnResult
    let store: ImageStore
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            StoredImage(key: result.imageKey, variant: .display, store: store)
                .aspectRatio(contentMode: .fit)
                .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
                .padding(WK.Spacing.screenInset)
                .frame(maxHeight: .infinity)
                .background(WK.Palette.canvas.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { isConfirmingDelete = true } label: { Image(systemName: "trash") }
                            .tint(.red)
                    }
                    if let image {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: Image(uiImage: image), preview: .init("Probado")) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .tint(WK.Palette.primaryText)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .tint(WK.Palette.primaryText)
                    }
                }
                .alert("¿Borrar esta prueba?", isPresented: $isConfirmingDelete) {
                    Button("Borrar", role: .destructive, action: onDelete)
                    Button("Cancelar", role: .cancel) {}
                }
        }
        .task {
            if let cgImage = try? await store.image(for: result.imageKey, variant: .display) {
                image = UIImage(cgImage: cgImage)
            }
        }
    }
}
