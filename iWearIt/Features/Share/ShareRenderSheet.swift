import Photos
import SwiftUI
import UIKit
import WKDesign

/// **Compartir**: una hoja dinámica con la imagen ya renderizada —con la marca
/// Snazzy— y un botón para guardarla en Fotos. Sin título ni X: lo que se ve
/// es lo que se va a guardar, y la hoja se cierra arrastrando.
struct ShareRenderSheet: View {
    /// Cómo se dibuja la imagen. Se llama al abrir la hoja: renderizar un
    /// lienzo carga sus prendas de disco y no tiene que bloquear el toque.
    let render: () async -> UIImage?

    @State private var image: UIImage?
    @State private var state: SaveState = .idle

    private enum SaveState: Equatable { case idle, saving, saved, denied, failed }

    var body: some View {
        VStack(spacing: WK.Spacing.l) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .transition(.blurReplace)
                } else {
                    RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
                        .fill(WK.Palette.shelf)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .wkShimmer(isActive: true)
                }
            }
            .frame(maxHeight: 440)
            .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 16, y: 8)

            WKPrimaryButton(title, systemImage: symbol, surface: .glass) {
                Task { await save() }
            }
            .disabled(image == nil || state == .saving || state == .saved)
            .sensoryFeedback(.success, trigger: state == .saved)

            if state == .denied || state == .failed {
                Text(state == .denied
                     ? String(localized: "share.denied", defaultValue: "Allow Snazzy to add photos in Settings.")
                     : String(localized: "share.failed", defaultValue: "Couldn't save it. Try again."))
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .animation(WKAnimation.content, value: image != nil)
        .animation(WKAnimation.content, value: state)
        .task {
            guard image == nil else { return }
            image = await render()
        }
        .wkDynamicSheet()
    }

    private var title: String {
        switch state {
        case .saving: String(localized: "share.saving", defaultValue: "Saving…")
        case .saved: String(localized: "share.saved", defaultValue: "Saved to Photos")
        default: String(localized: "share.save", defaultValue: "Save to Photos")
        }
    }

    private var symbol: String { state == .saved ? "checkmark" : "square.and.arrow.down" }

    /// A Fotos directamente, pidiendo solo permiso para **añadir**: no hace
    /// falta ver la fototeca para guardar una imagen en ella.
    private func save() async {
        guard let image else { return }
        state = .saving
        guard await Self.requestAddAccess() else {
            state = .denied
            return
        }
        do {
            try await Self.addToLibrary(image)
            state = .saved
        } catch {
            state = .failed
        }
    }

    // Fuera del actor principal: Fotos llama a estos cierres en su propia
    // cola, y un cierre heredado de la vista —aislado al hilo principal—
    // hacía saltar la comprobación de cola de Swift 6 y cerraba la app.
    private nonisolated static func requestAddAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    private nonisolated static func addToLibrary(_ image: UIImage) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}
