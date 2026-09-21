import SwiftUI
import WKCore
import WKDesign
import WKPersistence
import WKVision

/// La imagen de una prenda guardada, con las dos versiones a un toque.
///
/// ## Por qué las dos
///
/// El recorte es **lo que estuvo delante de la cámara**. La reconstrucción es
/// una interpretación: queda mucho mejor —plana, recta, sin percha ni arrugas—
/// pero el mismo mecanismo que le quita el fondo dentado le **rellena los
/// agujeros**, así que si el recorte perdió media manga te devuelve la manga
/// entera. Comprobado, no supuesto.
///
/// Por eso no sustituye a nada: se guarda al lado y se puede comparar. Y por
/// eso el conmutador dice "Foto" y "Catálogo" y no "antes" y "después".
struct GarmentImageSwitcher: View {
    let garment: Garment

    @Environment(AppEnvironment.self) private var appEnvironment

    /// Si se está mirando la reconstruida.
    @State private var showsCatalog = false
    /// Si esta prenda ya tiene una. Se pregunta al disco, no se supone.
    @State private var hasCatalog = false
    @State private var isGenerating = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: WK.Spacing.s) {
            StoredImage(
                key: garment.normalizedImageKey,
                variant: .display,
                store: appEnvironment.imageStore,
                shadow: .init(opacity: 0.5, radius: 18, y: 11),
                prefersCatalog: showsCatalog
            )
            .frame(maxWidth: .infinity)
            .frame(height: 300)

            control
        }
        .task(id: garment.normalizedImageKey) {
            hasCatalog = await appEnvironment.imageStore.hasCatalog(
                for: garment.normalizedImageKey
            )
        }
    }

    /// Un conmutador si ya está hecha; un botón para hacerla si no.
    ///
    /// Vista propia y no un `if` dentro del `VStack`: son dos controles
    /// distintos con estados distintos, y mezclarlos en el mismo builder
    /// significa que tocar uno reevalúa la imagen de arriba.
    @ViewBuilder
    private var control: some View {
        if hasCatalog {
            Picker("Imagen", selection: $showsCatalog) {
                Text("Foto").tag(false)
                Text("Catálogo").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
        } else if appEnvironment.resolver != nil {
            Button {
                Task { await generate() }
            } label: {
                Label(
                    isGenerating ? "Redibujando…" : "Versión de catálogo",
                    systemImage: "wand.and.sparkles"
                )
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.accent)
            }
            .disabled(isGenerating)
            .buttonStyle(WKPressStyle())
        }

        if failed {
            Text("No se pudo redibujar. Inténtalo de nuevo.")
                .font(WK.Font.caption)
                .foregroundStyle(.red)
        }
    }

    /// La pide y la guarda **bajo la misma clave** que el recorte.
    ///
    /// Compartir clave es lo que hace que borrar la prenda se lleve las dos y
    /// que no pueda quedarse una huérfana ocupando disco.
    private func generate() async {
        guard let resolver = appEnvironment.resolver, !isGenerating else { return }
        isGenerating = true
        failed = false
        defer { isGenerating = false }

        let key = garment.normalizedImageKey
        guard
            let source = try? await appEnvironment.imageStore.image(for: key, variant: .display),
            let jpeg = NormalizedJPEG.encode(source),
            let data = try? await resolver.restyle(jpeg),
            let decoded = UIImage(data: data)?.cgImage
        else {
            DiagnosticsLog.record("CATÁLOGO", "no se pudo generar para \(key.prefix(8))", isProblem: true)
            failed = true
            return
        }

        try? await appEnvironment.imageStore.storeCatalog(decoded, for: key)
        hasCatalog = true
        // Se enseña al momento: acabas de pedirla, no tiene sentido tener que
        // tocar otra vez para verla.
        showsCatalog = true
    }
}
