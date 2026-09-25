import PhotosUI
import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// **Afinar el cuerpo**: hasta cuatro fotos tuyas de cuerpo entero.
///
/// Con la estatura y la complexión la prueba adivina; con fotos, copia. Cuatro
/// huecos a la vista —se llenan de uno en uno o de golpe desde la galería—, y
/// cada foto se quita con su X. La cara sigue siendo la del retrato.
struct BodyPhotosSheet: View {
    @Bindable var profile: BodyProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var picked: [PhotosPickerItem] = []
    @State private var isTakingPhoto = false
    @State private var isLoading = false

    private var remaining: Int { BodyProfile.maximumBodyPhotos - profile.bodyImageKeys.count }

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.l) {
            VStack(alignment: .leading, spacing: WK.Spacing.xs) {
                Text(String(localized: "tryon.body.title", defaultValue: "Fine-tune your body"))
                    .font(WK.Font.title)
                    .foregroundStyle(WK.Palette.primaryText)
                Text(String(localized: "tryon.body.subtitle", defaultValue: "Up to 4 full-body photos, head to toe. The more angles, the closer it gets to how you really are."))
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.secondaryText)
            }

            // Los cuatro huecos, en fila: los llenos con su foto y su X, los
            // vacíos con un "+".
            HStack(spacing: WK.Spacing.s) {
                ForEach(0..<BodyProfile.maximumBodyPhotos, id: \.self) { index in
                    slot(at: index)
                }
            }
            .animation(WKAnimation.content, value: profile.bodyImageKeys)

            HStack(spacing: WK.Spacing.s) {
                WKPrimaryButton(
                    String(localized: "common.takeAPhoto", defaultValue: "Take a photo"),
                    systemImage: "camera",
                    surface: .glass
                ) { isTakingPhoto = true }
                PhotosPicker(
                    selection: $picked,
                    maxSelectionCount: max(remaining, 1),
                    matching: .images
                ) {
                    Label(String(localized: "tryon.body.choose", defaultValue: "Choose"), systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .foregroundStyle(WK.Palette.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WK.Spacing.m)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .adaptiveGlassInteractive(in: .capsule)
            }
            .disabled(remaining == 0 || isLoading)
            .opacity(remaining == 0 ? 0.5 : 1)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.top, WK.Spacing.l)
        .task(id: picked) { await storePicked() }
        .sheet(isPresented: $isTakingPhoto) {
            CameraScreen { images in
                Task { await store(Array(images.prefix(remaining))) }
                isTakingPhoto = false
            }
        }
        .wkDynamicSheet()
    }

    @ViewBuilder
    private func slot(at index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
        Group {
            if index < profile.bodyImageKeys.count {
                let key = profile.bodyImageKeys[index]
                // El hueco manda —3:4, igual para todas— y la foto lo llena:
                // una apaisada deformaba la fila.
                Color.clear
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        StoredImage(key: key, variant: .thumb, store: appEnvironment.imageStore)
                            .scaledToFill()
                    }
                    .clipShape(shape)
                    .overlay(alignment: .topTrailing) {
                        Button { remove(key) } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(WK.Palette.primaryText)
                                .frame(width: 24, height: 24)
                                .adaptiveGlassInteractive(in: .circle)
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                shape
                    .strokeBorder(WK.Palette.ink(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        if isLoading, index == profile.bodyImageKeys.count {
                            ProgressView()
                        } else {
                            Image(systemName: "figure.stand")
                                .font(.title3)
                                .foregroundStyle(WK.Palette.tertiaryText)
                        }
                    }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Lo que hace

    private func storePicked() async {
        guard !picked.isEmpty else { return }
        var images: [CGImage] = []
        for item in picked.prefix(remaining) {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data)?.cgImage {
                images.append(image)
            }
        }
        picked = []
        await store(images)
    }

    private func store(_ images: [CGImage]) async {
        guard !images.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        for image in images where profile.bodyImageKeys.count < BodyProfile.maximumBodyPhotos {
            guard let key = try? await appEnvironment.imageStore.store(image) else { continue }
            withAnimation(WKAnimation.content) { profile.bodyImageKeys.append(key) }
        }
        try? modelContext.save()
    }

    private func remove(_ key: String) {
        withAnimation(WKAnimation.content) { profile.bodyImageKeys.removeAll { $0 == key } }
        try? modelContext.save()
        Task { try? await appEnvironment.imageStore.delete(key: key) }
    }
}
