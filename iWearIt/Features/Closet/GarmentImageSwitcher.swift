import SwiftUI
import WKCore
import WKDesign
import WKPersistence
import WKVision

/// La imagen de una prenda guardada: **la de catálogo**.
///
/// Antes esto era un conmutador de dos posiciones, "Foto" y "Catálogo", y
/// abría en la foto. Estaba mal por los dos lados: abrir en el recorte es
/// enseñar la versión fea de la prenda cada vez que la abres, y el segmentado
/// convertía una ficha en un sitio donde hay que elegir algo antes de mirar.
///
/// La de catálogo es la buena y es la que se ve en las baldas: la ficha enseña
/// lo mismo. Comparar las dos versiones sigue siendo posible, pero donde toca
/// —en la hoja de editar, con las tres imágenes en fila— y no cada vez que se
/// toca una prenda.
struct GarmentImageSwitcher: View {
    let garment: Garment

    @Environment(AppEnvironment.self) private var appEnvironment

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
                prefersCatalog: true
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

    /// Nada si ya está hecha; un botón para hacerla si falta.
    ///
    /// **Sin conmutador.** El de antes —"Foto | Catálogo"— se queda comentado
    /// ahí abajo: enseñaba la versión fea por defecto y obligaba a tocar para
    /// ver la buena.
    @ViewBuilder
    private var control: some View {
        if !hasCatalog, appEnvironment.resolver != nil {
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

    // El conmutador de antes, comentado y no borrado:
    //
    //     Picker("Imagen", selection: $showsCatalog) {
    //         Text("Foto").tag(false)
    //         Text("Catálogo").tag(true)
    //     }
    //     .pickerStyle(.segmented)
    //     .frame(maxWidth: 220)

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
    }
}
