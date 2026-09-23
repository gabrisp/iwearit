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
    /// Cuál de tus perfiles está puesto.
    ///
    /// Por identificador y no por el objeto: el objeto puede irse —lo borras—
    /// y una referencia colgando a un `@Model` borrado es una pantalla en
    /// blanco.
    @State private var selectedID: UUID?
    /// Dónde ponerte. Ver `TryOnScene`.
    @State private var scene: TryOnScene = .none

    /// El perfil con el que se prueba: el elegido, o el primero que haya.
    private var profile: BodyProfile? {
        profiles.first { $0.id == selectedID } ?? profiles.first
    }

    private var canAddMore: Bool { profiles.count < BodyProfile.maximumProfiles }

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
                if !profiles.isEmpty { strip }
                scenes
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
                    // Sobre el papel de la app: un PNG recortado sobre nada se
                    // ve como un recorte flotando, y sobre el papel se ve como
                    // lo que es.
                    .background(scene == .none ? WK.Palette.canvas : .clear)
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

    /// **Tus perfiles.**
    ///
    /// Hasta tres, porque probarse ropa no siempre es para uno: la foto de
    /// cuerpo entero con buena luz, la del espejo del gimnasio y la de tu
    /// pareja son tres perfiles distintos y elegir entre ellos es un toque.
    /// Sin esto había que borrar la foto y subir otra cada vez, que es la
    /// forma más rápida de que nadie use esto dos veces.
    private var strip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.m) {
                ForEach(profiles) { item in
                    Button { selectedID = item.id } label: {
                        StoredImage(
                            key: item.imageKey,
                            variant: .thumb,
                            store: appEnvironment.imageStore
                        )
                        .frame(width: 56, height: 72)
                        .clipShape(.rect(cornerRadius: WK.Radius.medium, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                                .stroke(
                                    item.id == profile?.id ? WK.Palette.accent : WK.Palette.ink(0.1),
                                    lineWidth: item.id == profile?.id ? 2 : 1
                                )
                        }
                        .opacity(item.id == profile?.id ? 1 : 0.6)
                    }
                    .buttonStyle(WKPressStyle())
                    .contextMenu {
                        Button(role: .destructive) { remove(item) } label: {
                            Label("Quitar esta foto", systemImage: "trash")
                        }
                    }
                }

                if canAddMore {
                    PhotosPicker(selection: $picked, matching: .images) {
                        RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                            .stroke(
                                WK.Palette.ink(0.18),
                                style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                            )
                            .frame(width: 56, height: 72)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.body)
                                    .foregroundStyle(WK.Palette.secondaryText)
                            }
                    }
                    .buttonStyle(WKPressStyle())
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .animation(WKAnimation.content, value: profiles.count)
    }

    /// Dónde te pones.
    ///
    /// El escenario va **antes** de generar y no después: pedir la ropa y
    /// luego cambiar el fondo deja la luz de un sitio sobre una persona
    /// iluminada de otro. "Sin fondo" devuelve un PNG recortado.
    private var scenes: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.s) {
                ForEach(TryOnScene.allCases) { option in
                    Button { scene = option } label: {
                        Label(option.label, systemImage: option.symbol)
                            .font(WK.Font.caption)
                            .foregroundStyle(
                                scene == option ? WK.Palette.onAccent : WK.Palette.primaryText
                            )
                            .fixedSize()
                            .padding(.horizontal, WK.Spacing.m)
                            .padding(.vertical, WK.Spacing.s)
                            .background {
                                if scene == option {
                                    Capsule().fill(WK.Palette.accent)
                                }
                            }
                            .adaptiveGlass(in: .capsule)
                    }
                    .buttonStyle(WKPressStyle())
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .animation(WKAnimation.selection, value: scene)
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
                // Lo justo y en letra pequeña: el cartel de antes ocupaba media
                // pantalla para decir esto mismo.
                Text("Tu foto se procesa fuera del teléfono. Se pregunta una vez.")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
                    .multilineTextAlignment(.center)
            } else {
                WKPrimaryButton(model?.state == .working ? "Vistiéndote…" : "Probármelo") {
                    generate()
                }
                .disabled(model?.state == .working)

                if canAddMore {
                    PhotosPicker(selection: $picked, matching: .images) {
                        Text("Añadir otra foto")
                            .font(WK.Font.caption)
                            .foregroundStyle(WK.Palette.secondaryText)
                    }
                }
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
        // Tres y no más: son fotos de personas, y guardar sin tope una carpeta
        // de fotos de cuerpo entero no es un favor que le hagamos a nadie.
        guard profiles.count < BodyProfile.maximumProfiles else { picked = nil; return }
        let profile = BodyProfile(label: Self.name(for: profiles.count), imageKey: key)
        modelContext.insert(profile)
        try? modelContext.save()
        selectedID = profile.id
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
            let done = await model.generate(
                for: profile,
                garments: outfit.garments,
                scene: scene
            )
            if done { store.note(.generation, detail: outfit.name) }
        }
    }

    private static func name(for index: Int) -> String {
        index == 0 ? "Yo" : "Perfil \(index + 1)"
    }

    /// Quitar la foto **es revocar el permiso**: se va la imagen y se va la
    /// fecha con ella.
    private func remove(_ profile: BodyProfile) {
        let key = profile.imageKey
        if selectedID == profile.id { selectedID = nil }
        modelContext.delete(profile)
        try? modelContext.save()
        Task { try? await appEnvironment.imageStore.delete(key: key) }
        DiagnosticsLog.record("PROBADOR", "perfil quitado: se revoca el permiso")
    }
}
