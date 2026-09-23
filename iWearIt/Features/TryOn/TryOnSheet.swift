import PhotosUI
import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Probarte un outfit.
///
/// ## El orden de la pantalla es el orden de las decisiones
///
/// Primero tu foto —sin ella no hay nada que hacer—, después el permiso para
/// que salga del teléfono, y solo entonces el botón de generar. Puesto al
/// revés, el permiso llega cuando ya has decidido y se lee como un trámite;
/// puesto aquí, es lo que es: una pregunta con su respuesta a mano.
struct TryOnSheet: View {
    let outfit: Outfit

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(sort: \BodyProfile.createdAt, order: .reverse)
    private var profiles: [BodyProfile]

    @State private var model: TryOnModel?
    @State private var picked: PhotosPickerItem?
    @State private var isAccepting = false

    private var profile: BodyProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            content
                .background(WK.Palette.canvas.ignoresSafeArea())
                .navigationTitle("Probador")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .tint(WK.Palette.primaryText)
                    }
                    if let result = model?.result {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: Image(uiImage: result), preview: .init("Probado")) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .tint(WK.Palette.primaryText)
                        }
                    }
                }
                .adaptiveSafeAreaBar(edge: .bottom) { bottom }
                .task { prepare() }
                .task(id: picked) { await store(picked) }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: WK.Spacing.l) {
                canvas
                if profile == nil { explain }
                if case let .failed(reason) = model?.state {
                    Text(reason)
                        .font(WK.Font.caption)
                        .foregroundStyle(WK.Palette.accent)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.vertical, WK.Spacing.m)
        }
        .scrollIndicators(.hidden)
    }

    /// Lo que se está mirando: el resultado si lo hay, tu foto si no, y el
    /// hueco con su invitación si todavía no hay foto.
    @ViewBuilder
    private var canvas: some View {
        ZStack {
            if let result = model?.result {
                Image(uiImage: result)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
            } else if let profile {
                StoredImage(
                    key: profile.imageKey,
                    variant: .display,
                    store: appEnvironment.imageStore
                )
                .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
                .opacity(model?.state == .working ? 0.45 : 1)
            } else {
                RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
                    .fill(WK.Palette.ink(0.04))
                    .overlay {
                        Label("Elige una foto tuya de cuerpo entero", systemImage: "person")
                            .font(WK.Font.callout)
                            .foregroundStyle(WK.Palette.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(WK.Spacing.l)
                    }
            }

            if model?.state == .working { ProgressView() }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .animation(WKAnimation.content, value: model?.state)
    }

    /// El permiso, con todas las letras y antes de que nada salga de aquí.
    private var explain: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            Text("Tu foto sale del teléfono")
                .font(WK.Font.headline)
                .foregroundStyle(WK.Palette.primaryText)
            Text(
                "Para vestirte hace falta un servidor: no hay forma de hacerlo "
                + "aquí dentro. Se manda tu foto y los recortes de la ropa, nada "
                + "más — ni tu nombre, ni tu armario — y no se guarda al otro "
                + "lado. Quitando la foto se acaba el permiso."
            )
            .font(WK.Font.caption)
            .foregroundStyle(WK.Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var bottom: some View {
        VStack(spacing: WK.Spacing.s) {
            if profile == nil {
                PhotosPicker(selection: $picked, matching: .images) {
                    Text("Elegir mi foto")
                        .font(WK.Font.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(WKPressStyle())
                .adaptiveGlassInteractive(in: .capsule)
                .tint(WK.Palette.primaryText)
            } else if profile?.canLeaveDevice != true {
                WKPrimaryButton("Aceptar y probarme") { accept() }
                Text("Solo se pregunta una vez.")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
            } else {
                WKPrimaryButton(model?.state == .working ? "Vistiéndote…" : "Probármelo") {
                    generate()
                }
                .disabled(model?.state == .working)

                Button("Cambiar mi foto") { clearProfile() }
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.xs)
        .animation(WKAnimation.content, value: profile?.canLeaveDevice)
    }

    // MARK: Lo que hace

    private func prepare() {
        guard model == nil else { return }
        model = TryOnModel(
            resolver: appEnvironment.resolver,
            imageStore: appEnvironment.imageStore
        )
    }

    /// Guarda la foto elegida como tu perfil. **Sin consentimiento todavía**:
    /// tenerla aquí no es mandarla a ningún sitio.
    private func store(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)?.cgImage
        else { return }
        guard let key = try? await appEnvironment.imageStore.store(image) else { return }
        let profile = BodyProfile(label: "Yo", imageKey: key)
        modelContext.insert(profile)
        try? modelContext.save()
        picked = nil
    }

    private func accept() {
        guard let profile else { return }
        profile.consentAcceptedAt = Date()
        try? modelContext.save()
        DiagnosticsLog.record("PROBADOR", "consentimiento aceptado")
        generate()
    }

    private func generate() {
        guard let profile, let model else { return }
        // Vale una moneda de las de probar. Ver `StoreIDs.Cost`.
        let store = appEnvironment.store
        guard store.canAfford(.generation) else {
            appEnvironment.gate.require(.tryOn) {}
            return
        }
        Task {
            let done = await model.generate(for: profile, garments: outfit.garments)
            if done { store.note(.generation, detail: outfit.name) }
        }
    }

    /// Quitar la foto **es revocar el permiso**: se va la imagen y se va la
    /// fecha con ella.
    private func clearProfile() {
        guard let profile else { return }
        let key = profile.imageKey
        modelContext.delete(profile)
        try? modelContext.save()
        Task { try? await appEnvironment.imageStore.delete(key: key) }
    }
}
