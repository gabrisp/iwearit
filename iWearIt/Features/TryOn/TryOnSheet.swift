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
    /// Cuál de los probados de antes se está mirando. `nil` = el último.
    @State private var showing: TryOnResult?
    /// Qué perfil se está editando, o `nil` para uno nuevo. El `Bool` de al
    /// lado es el que abre la hoja: con `item:` haría falta un identificable
    /// para el caso "nuevo", que no tiene identidad todavía.
    @State private var editing: BodyProfile?
    @State private var isEditingProfile = false
    /// Cuál de tus perfiles está puesto.
    ///
    /// Por identificador y no por el objeto: el objeto puede irse —lo borras—
    /// y una referencia colgando a un `@Model` borrado es una pantalla en
    /// blanco.
    @State private var selectedID: UUID?
    /// Dónde ponerte. Ver `TryOnScene`.
    @State private var scene: TryOnScene = .none
    /// Si la prueba que se ve ya se metió en el outfit como sticker.
    @State private var addedToOutfit = false

    /// El perfil con el que se prueba: el elegido, o el primero que haya.
    private var profile: BodyProfile? {
        profiles.first { $0.id == selectedID } ?? profiles.first
    }

    private var canAddMore: Bool { profiles.count < BodyProfile.maximumProfiles }

    var body: some View {
        NavigationStack {
            VStack(spacing: WK.Spacing.l) {
                // **La prueba y el outfit, delante.** Antes la foto iba en un
                // marco con la tira de pruebas y la de perfiles debajo, y lo
                // que se venía a ver —cómo te queda— quedaba apretado entre
                // controles. Ahora el escenario ocupa la pantalla; los
                // perfiles van en la pastilla de arriba y el historial en el
                // probador virtual.
                TryOnStage(
                    outfit: outfit,
                    profile: profile,
                    result: model?.result,
                    showing: showing,
                    isWorking: model?.state == .working,
                    isPlainScene: scene == .none,
                    store: appEnvironment.imageStore
                )
                .frame(maxHeight: .infinity)

                if case let .failed(reason) = model?.state {
                    Text(reason)
                        .font(WK.Font.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                // past
                // if !profiles.isEmpty { strip }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.top, WK.Spacing.s)
            .background(WK.Palette.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // **Mientras te viste, no se cierra**: ni la X —se esconde—
                // ni arrastrando la hoja. Cerrar a mitad tiraba la prueba ya
                // pagada.
                if model?.state != .working {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .tint(WK.Palette.primaryText)
                    }
                }
                ToolbarItem(placement: .principal) {
                    ProfileSwitcher(
                        profiles: profiles,
                        selected: profile,
                        canAddMore: canAddMore,
                        store: appEnvironment.imageStore,
                        onSelect: { selectedID = $0.id },
                        onEdit: { edit($0) },
                        onNew: { edit(nil) }
                    )
                }
                if let result = model?.result {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Con la marca, y "sin fondo" sobre el papel del
                        // outfit. Ver `SnazzyExport`.
                        let shared = SnazzyExport.tryOn(
                            result,
                            paper: scene == .none ? UIColor(PlanFeedScreen.backdrop(of: outfit)) : nil
                        )
                        ShareLink(item: Image(uiImage: shared), preview: .init("Probado", image: Image(uiImage: shared))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .tint(WK.Palette.primaryText)
                    }
                }
            }
            .adaptiveSafeAreaBar(edge: .bottom) { bottom }
            .interactiveDismissDisabled(model?.state == .working)
            .task { prepare() }
            .sheet(isPresented: $isEditingProfile) {
                // Editar uno que ya existe, con todo a la vista; crear uno
                // nuevo, con su flujo de pasos.
                if let editing {
                    ProfileEditSheet(profile: editing)
                } else {
                    TryOnProfileSheet(profile: nil)
                }
            }
        }
    }

    // El cuerpo de antes: marco con la foto, la tira de probados y la de
    // perfiles una debajo de otra.
    // var body: some View {
    //     NavigationStack {
    //         content
    //             .background(WK.Palette.canvas.ignoresSafeArea())
    //             .navigationTitle("Probador")
    //             .navigationBarTitleDisplayMode(.inline)
    //             .toolbar {
    //                 ToolbarItem(placement: .topBarLeading) {
    //                     Button { dismiss() } label: { Image(systemName: "xmark") }
    //                         .tint(WK.Palette.primaryText)
    //                 }
    //                 if let result = model?.result {
    //                     ToolbarItem(placement: .topBarTrailing) {
    //                         ShareLink(item: Image(uiImage: result), preview: .init("Probado")) {
    //                             Image(systemName: "square.and.arrow.up")
    //                         }
    //                         .tint(WK.Palette.primaryText)
    //                     }
    //                 }
    //             }
    //             .adaptiveSafeAreaBar(edge: .bottom) { bottom }
    //             .task { prepare() }
    //             .sheet(isPresented: $isEditingProfile) {
    //                 TryOnProfileSheet(profile: editing)
    //             }
    //     }
    // }

    // @ViewBuilder
    // private var content: some View {
    //     ScrollView {
    //         VStack(spacing: WK.Spacing.l) {
    //             canvas
    //             past
    //             if !profiles.isEmpty { strip }
    //             // Las píldoras de escena, fuera: el fondo se elige con el
    //             // botón de al lado de "Probármelo". Ver `sceneMenu`.
    //             // scenes
    //             if case let .failed(reason) = model?.state {
    //                 Text(reason)
    //                     .font(WK.Font.caption)
    //                     .foregroundStyle(WK.Palette.accent)
    //                     .multilineTextAlignment(.center)
    //             }
    //         }
    //         .padding(.horizontal, WK.Spacing.screenInset)
    //         .padding(.vertical, WK.Spacing.m)
    //     }
    //     .scrollIndicators(.hidden)
    // }

    /// Lo que ya te has probado de este conjunto, lo último primero.
    private var history: [TryOnResult] {
        (outfit.tryOns ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    /// La tira de lo ya probado. Solo si hay algo: un carrusel vacío es una
    /// promesa sin cumplir.
    @ViewBuilder
    private var past: some View {
        if !history.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: WK.Spacing.s) {
                    ForEach(history) { item in
                        Button { showing = item } label: {
                            StoredImage(
                                key: item.imageKey,
                                variant: .thumb,
                                store: appEnvironment.imageStore
                            )
                            .frame(width: 54, height: 72)
                            .clipShape(.rect(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        WK.Palette.accent,
                                        lineWidth: showing?.id == item.id ? 2 : 0
                                    )
                            }
                        }
                        .buttonStyle(WKPressStyle())
                    }
                }
                .padding(.horizontal, WK.Spacing.screenInset)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Lo que se está mirando: el resultado si lo hay, tu foto si no, y el
    /// hueco con su invitación si todavía no hay foto.
    @ViewBuilder
    private var canvas: some View {
        ZStack {
            // Uno guardado, si has tocado la tira; si no, el recién hecho.
            if let showing {
                StoredImage(
                    key: showing.imageKey,
                    variant: .display,
                    store: appEnvironment.imageStore
                )
                .background(WK.Palette.canvas)
                .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
            } else if let result = model?.result {
                Image(uiImage: result)
                    .resizable()
                    .scaledToFit()
                    // Sobre el papel de la app: un PNG recortado sobre nada se
                    // ve como un recorte flotando, y sobre el papel se ve como
                    // lo que es.
                    .background(scene == .none ? WK.Palette.canvas : .clear)
                    .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
            } else if let profile, profile.hasPhoto {
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
                        // Sin foto, lo que se enseña es **a quién se va a
                        // dibujar**, con las mismas palabras que se le van a
                        // decir al modelo.
                        VStack(spacing: WK.Spacing.s) {
                            Image(systemName: "person")
                                .font(.title)
                                .foregroundStyle(WK.Palette.tertiaryText)
                            Text(profile?.described ?? "Crea un perfil para probarte la ropa")
                                .font(WK.Font.callout)
                                .foregroundStyle(WK.Palette.secondaryText)
                                .multilineTextAlignment(.center)
                        }
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
            HStack(alignment: .top, spacing: WK.Spacing.l) {
                ForEach(profiles) { item in
                    Button { selectedID = item.id } label: {
                        // ProfileChip(
                        //     profile: item,
                        //     isSelected: item.id == profile?.id,
                        //     store: appEnvironment.imageStore
                        // )
                        // Avatares y no píldoras: una persona se reconoce por
                        // la cara, no por una etiqueta.
                        ProfileAvatar(
                            profile: item,
                            isSelected: item.id == profile?.id,
                            store: appEnvironment.imageStore
                        )
                    }
                    .buttonStyle(WKPressStyle())
                    .contextMenu {
                        Button { edit(item) } label: {
                            Label("Editar", systemImage: "pencil")
                        }
                        Button(role: .destructive) { remove(item) } label: {
                            Label("Quitar este perfil", systemImage: "trash")
                        }
                    }
                }

                if canAddMore {
                    Button { edit(nil) } label: {
                        // Label("Nuevo", systemImage: "plus") … en píldora
                        // discontinua, antes.
                        VStack(spacing: WK.Spacing.xs) {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(WK.Palette.primaryText)
                                .frame(width: ProfileAvatar.side, height: ProfileAvatar.side)
                                .adaptiveGlassInteractive(in: .circle)
                            Text("Nuevo")
                                .font(WK.Font.caption)
                                .foregroundStyle(WK.Palette.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, WK.Spacing.xs)
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
            // **Las píldoras, en un contenedor de cristal.** Sueltas, cada una
            // muestrea el fondo por su cuenta y la de al lado le sale un canto
            // duro: el cristal no puede muestrear otro cristal. Dentro del
            // contenedor se funden entre ellas, que es lo que hace que una
            // fila parezca una fila y no seis pegatinas.
            AdaptiveGlassContainer(spacing: WK.Spacing.s) {
                HStack(spacing: WK.Spacing.s) {
                    ForEach(TryOnScene.allCases) { option in
                        Button {
                            withAnimation(WKAnimation.selection) { scene = option }
                        } label: {
                            Label(option.label, systemImage: option.symbol)
                                .font(WK.Font.caption)
                                .foregroundStyle(
                                    scene == option ? WK.Palette.onAccent : WK.Palette.primaryText
                                )
                                .fixedSize()
                                .padding(.horizontal, WK.Spacing.m)
                                .padding(.vertical, WK.Spacing.s)
                                // El tinte **dentro** del cristal y no debajo:
                                // ver `adaptiveGlassChip`.
                                .adaptiveGlassChip(
                                    isSelected: scene == option,
                                    tint: WK.Palette.accent
                                )
                        }
                        .buttonStyle(WKPressStyle())
                    }
                }
                // Sitio para que el cristal se dibuje fuera de la píldora sin
                // que el scroll se lo coma.
                .padding(.vertical, 2)
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    /// Dónde te pones, en un menú junto al botón.
    ///
    /// Antes era una fila de seis píldoras entre la foto y el botón: ocupaba
    /// sitio, se leía como un formulario y lo que casi nadie cambia estaba a
    /// la misma altura que lo que todo el mundo toca. En el botón se ve qué
    /// fondo va a salir —su icono— y cambiarlo son dos toques.
    private var sceneMenu: some View {
        Menu {
            Picker("Fondo", selection: $scene) {
                ForEach(TryOnScene.allCases) { option in
                    Label(option.label, systemImage: option.symbol).tag(option)
                }
            }
        } label: {
            Image(systemName: scene.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(WK.Palette.primaryText)
                .frame(width: 56, height: 56)
                .contentShape(.circle)
                .contentTransition(.symbolEffect(.replace))
        }
        .adaptiveGlassInteractive(in: .circle)
        .accessibilityLabel("Fondo: \(scene.label)")
    }

    @ViewBuilder
    private var bottom: some View {
        VStack(spacing: WK.Spacing.s) {
            if profile == nil {
                WKPrimaryButton("Crear un perfil", surface: .glass) { edit(nil) }
            } else if profile?.hasPhoto == true, profile?.canLeaveDevice != true {
                WKPrimaryButton("Aceptar y probarme", surface: .glass) { accept() }
                // Lo justo y en letra pequeña: el cartel de antes ocupaba media
                // pantalla para decir esto mismo.
                Text("Tu foto se procesa fuera del teléfono. Se pregunta una vez.")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
                    .multilineTextAlignment(.center)
            } else {
                // **Al propio outfit**, como sticker: sin fondo, la persona
                // recortada; con escena, la foto entera.
                if model?.state != .working, model?.result != nil || showing != nil {
                    Button { Task { await addToOutfit() } } label: {
                        Label(
                            addedToOutfit ? "Añadida al outfit" : "Añadir al outfit",
                            systemImage: addedToOutfit ? "checkmark" : "plus.rectangle.on.rectangle"
                        )
                        .font(WK.Font.captionMedium)
                        .foregroundStyle(WK.Palette.primaryText)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(.horizontal, WK.Spacing.m)
                        .padding(.vertical, WK.Spacing.s + 2)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .adaptiveGlassInteractive(in: .capsule)
                    .disabled(addedToOutfit)
                    .sensoryFeedback(.success, trigger: addedToOutfit)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                // El fondo, en tarjetas que se ven. Ver `ScenePicker`.
                ScenePicker(selection: $scene)
                    .padding(.horizontal, -WK.Spacing.screenInset)
                    .disabled(model?.state == .working)

                // En cristal, a lo ancho. El menú de escenas de al lado se
                // queda comentado: ver `ScenePicker`.
                WKPrimaryButton(model?.state == .working ? "Vistiéndote…" : "Probármelo", surface: .glass) {
                    generate()
                }
                .disabled(model?.state == .working)
                // sceneMenu

                // Editar el perfil va en la pastilla de arriba.
                // if let profile {
                //     Button("Editar \(profile.label)") { edit(profile) }
                //         .font(WK.Font.caption)
                //         .foregroundStyle(WK.Palette.secondaryText)
                // }
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.xs)
        .animation(WKAnimation.content, value: profile?.canLeaveDevice)
    }

    // MARK: Lo que hace

    /// Mete la prueba que se ve en el outfit, como sticker.
    private func addToOutfit() async {
        if let showing {
            let size = (try? await appEnvironment.imageStore.image(for: showing.imageKey, variant: .display))
                .map { CGSize(width: $0.width, height: $0.height) } ?? CGSize(width: 3, height: 4)
            TryOnSticker.add(key: showing.imageKey, imageSize: size, to: outfit, context: modelContext)
        } else if let image = model?.result?.cgImage,
                  let key = try? await appEnvironment.imageStore.store(image) {
            TryOnSticker.add(
                key: key, imageSize: CGSize(width: image.width, height: image.height),
                to: outfit, context: modelContext
            )
        } else {
            return
        }
        withAnimation(WKAnimation.content) { addedToOutfit = true }
    }

    private func prepare() {
        guard model == nil else { return }
        model = TryOnModel(
            resolver: appEnvironment.resolver,
            imageStore: appEnvironment.imageStore
        )
    }

    private func edit(_ profile: BodyProfile?) {
        editing = profile
        isEditingProfile = true
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
            // Una prueba nueva todavía no está en el outfit.
            addedToOutfit = false
            let done = await model.generate(
                for: profile,
                garments: outfit.garments,
                scene: scene
            )
            guard done, let image = model.result?.cgImage else { return }
            store.note(.generation, detail: outfit.name)
            // Lo recién hecho manda sobre lo que estuvieras mirando de antes.
            showing = nil
            await save(image)
        }
    }

    /// **Lo probado se guarda.**
    ///
    /// Cuesta unos segundos y una moneda del bote, y hasta ahora vivía en
    /// memoria: cerrabas la hoja y se iba, así que volver a verlo era volver a
    /// pagarlo. La imagen va al disco como cualquier otra foto de la app y en
    /// la base de datos solo viaja su clave. Ver `TryOnResult`.
    private func save(_ image: CGImage) async {
        guard let key = try? await appEnvironment.imageStore.store(image) else { return }
        let saved = TryOnResult(
            imageKey: key,
            sceneRaw: scene.rawValue,
            outfit: outfit,
            profile: profile
        )
        modelContext.insert(saved)
        try? modelContext.save()
        DiagnosticsLog.record("PROBADOR", "guardado")
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


/// Un perfil en la tira: su nombre, y su foto si la hay.
private struct ProfileChip: View {
    let profile: BodyProfile
    let isSelected: Bool
    let store: ImageStore

    var body: some View {
        HStack(spacing: WK.Spacing.xs) {
            if profile.hasPhoto {
                StoredImage(key: profile.imageKey, variant: .thumb, store: store)
                    .frame(width: 22, height: 28)
                    .clipShape(.rect(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "person")
                    .font(.caption)
            }
            Text(profile.label)
                .font(WK.Font.caption.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? WK.Palette.onAccent : WK.Palette.primaryText)
        .fixedSize()
        .padding(.horizontal, WK.Spacing.m)
        .padding(.vertical, WK.Spacing.s)
        .background {
            Capsule().fill(isSelected ? WK.Palette.accent : WK.Palette.ink(0.06))
        }
    }
}


/// Un perfil como avatar: la foto en un círculo, o una silueta si es descrito,
/// con el nombre debajo. El elegido lleva un anillo **por fuera**, separado
/// del círculo, como las historias: se ve cuál es sin tapar la cara.
private struct ProfileAvatar: View {
    let profile: BodyProfile
    let isSelected: Bool
    let store: ImageStore

    static let side: CGFloat = 60

    var body: some View {
        VStack(spacing: WK.Spacing.xs) {
            Group {
                if profile.hasPhoto {
                    StoredImage(key: profile.imageKey, variant: .thumb, store: store)
                        .scaledToFill()
                } else {
                    ToneIcon("person.fill", tone: .at(abs(profile.id.hashValue)), size: Self.side)
                }
            }
            .frame(width: Self.side, height: Self.side)
            .clipShape(.circle)
            .padding(4)
            .overlay {
                Circle().stroke(isSelected ? WK.Palette.accent : .clear, lineWidth: 2.5)
            }
            .animation(WKAnimation.selection, value: isSelected)

            Text(profile.label)
                .font(isSelected ? WK.Font.captionMedium : WK.Font.caption)
                .foregroundStyle(isSelected ? WK.Palette.primaryText : WK.Palette.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: Self.side + 12)
        }
    }
}
