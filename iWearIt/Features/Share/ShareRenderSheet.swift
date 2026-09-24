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

    /// La vista previa, en el 3:4 de todo lo exportado.
    private static let previewSize = CGSize(width: 330, height: 440)

    private enum SaveState: Equatable { case idle, saving, saved, denied, failed }

    var body: some View {
        VStack(spacing: WK.Spacing.l) {
            // Tamaño fijo en 3:4 y el recorte sobre la imagen misma: con el
            // recorte fuera, en un marco más ancho que la foto, las esquinas
            // quedaban en el aire y la imagen salía con picos.
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.blurReplace)
                } else {
                    WK.Palette.shelf
                        .wkShimmer(isActive: true)
                }
            }
            .frame(width: Self.previewSize.width, height: Self.previewSize.height)
            .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
                    .strokeBorder(.black.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
            .padding(.top, WK.Spacing.m)

            WKPrimaryButton(title, systemImage: symbol, surface: .glass) {
                Task { await save() }
            }
            // Sin toques mientras guarda o ya guardado, pero **sin atenuar**:
            // "Guardado en Fotos" es la confirmación y tiene que leerse.
            .allowsHitTesting(image != nil && state != .saving && state != .saved)
            .opacity(image == nil ? 0.5 : 1)
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
        .animation(.smooth(duration: 0.45), value: state)
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

    /// La misma bandeja en los tres: al guardar solo cambia su distintivo, y
    /// el botón lo transforma con `magic`. Ver `WKPrimaryButton`.
    private var symbol: String {
        switch state {
        case .saving: "square.and.arrow.down.badge.clock"
        case .saved: "square.and.arrow.down.badge.checkmark"
        default: "square.and.arrow.down"
        }
    }

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
            // Un mínimo de "Guardando…": guardar tarda un instante y, sin
            // esto, el paso intermedio del botón no llegaba ni a verse.
            async let pause: Void? = try? Task.sleep(for: .milliseconds(600))
            try await Self.addToLibrary(image)
            _ = await pause
            state = .saved
            // Y vuelve a "Guardar en Fotos": la confirmación se lee y se va,
            // y se puede guardar otra vez.
            try? await Task.sleep(for: .seconds(1.8))
            if state == .saved { state = .idle }
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
