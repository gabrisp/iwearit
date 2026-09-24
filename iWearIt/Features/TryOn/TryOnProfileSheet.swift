import PhotosUI
import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence
import WKServices

/// Quién se prueba la ropa, **paso a paso**.
///
/// ## Por qué una foto de la cara y no de cuerpo entero
///
/// Porque sin foto el probador no prueba nada —dibuja a *alguien* con tu
/// complexión llevando tu ropa, y eso se mira una vez y no se vuelve—, pero
/// una foto de cuerpo entero, de frente y con buena luz, no la tiene casi
/// nadie a mano: pedirla de entrada era cerrar la puerta en el primer paso.
///
/// La cara sí la tiene todo el mundo, y es la que hace que te reconozcas. El
/// cuerpo lo ponen los datos del paso siguiente: estatura y complexión dicen
/// **cómo encuadrar la escena** y con qué proporciones cae la ropa, que es
/// exactamente lo que una foto de tu cara no puede decir.
///
/// ## Por qué por pasos y no un formulario
///
/// Un formulario con seis campos a la vez obliga a leerlo entero antes de
/// empezar, y el que se cansa a la mitad se queda sin perfil. Por pasos cada
/// pantalla hace una pregunta, el botón dice siempre qué va a pasar y el chrome
/// —salir, volver, continuar— no se mueve: solo cambia el medio. Es el mismo
/// flujo que crear una maleta. Ver `WKFlowScreen`.
///
/// Y no se cierra sola: se sale por la equis, y si hay algo escrito se
/// pregunta antes de tirarlo.
struct TryOnProfileSheet: View {
    /// El que se edita. `nil` = uno nuevo.
    var profile: BodyProfile?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var flow = WKFlowStack(Step.photo)
    @State private var name = ""
    @State private var height: Int? = 170
    @State private var shape: BodyProfile.Shape = .average
    @State private var presentation: BodyProfile.Presentation = .neutral
    @State private var skinTone: BodyProfile.SkinTone = .medium
    @State private var notes = ""
    @State private var picked: PhotosPickerItem?
    @State private var imageKey = ""
    @State private var isLoadingPhoto = false
    /// La cámara, en su propia hoja. Trae también el carrete dentro, así que
    /// quien entre por aquí sin querer no se queda sin salida.
    @State private var isTakingPhoto = false
    /// Si hay que preguntar antes de irse. Ver `hasProgress`.
    @State private var isConfirmingExit = false
    /// Cómo estaba al abrir: lo que decide si hay algo que perder.
    @State private var baseline: Snapshot?

    enum Step: Int, WKFlowStep {
        case photo, name, body, extras
        var flowDepth: Int { rawValue }
    }

    /// Lo que se compara para saber si se ha tocado algo.
    ///
    /// Una foto de lo que había al abrir, y no una bandera de "ha escrito":
    /// deshacer a mano lo que acabas de escribir vuelve a contar como que no
    /// hay nada que descartar, que es lo que espera cualquiera.
    private struct Snapshot: Equatable {
        var name: String
        var height: Int?
        var shape: BodyProfile.Shape
        var presentation: BodyProfile.Presentation
        var skinTone: BodyProfile.SkinTone
        var notes: String
        var imageKey: String
    }

    private var current: Snapshot {
        Snapshot(
            name: name,
            height: height,
            shape: shape,
            presentation: presentation,
            skinTone: skinTone,
            notes: notes,
            imageKey: imageKey
        )
    }

    private var hasProgress: Bool {
        guard let baseline else { return !imageKey.isEmpty || !name.isEmpty }
        return current != baseline
    }

    var body: some View {
        Group {
            switch flow.step {
            case .photo: photoStep
            case .name: nameStep
            case .body: bodyStep
            case .extras: extrasStep
            }
        }
        .wkDynamicSheet()
        // **No se cierra deslizando.** A medio perfil, un gesto hacia abajo
        // —el mismo que se hace para pasar cualquier otra cosa— tiraba lo
        // escrito sin preguntar. Se sale por la equis, que sí pregunta.
        .interactiveDismissDisabled()
        .confirmationDialog(
            "¿Descartar el perfil?",
            isPresented: $isConfirmingExit,
            titleVisibility: .visible
        ) {
            Button("Descartar", role: .destructive) { dismiss() }
            Button("Seguir", role: .cancel) {}
        } message: {
            Text("Lo que has puesto hasta aquí no se guarda.")
        }
        .sheet(isPresented: $isTakingPhoto) {
            CameraScreen { images in
                guard let first = images.first else { return }
                Task { await store(first) }
            }
        }
        .task { load() }
        .task(id: picked) { await storePhoto(picked) }
    }

    // MARK: Pasos

    private var photoStep: some View {
        WKFlowScreen(
            title: profile == nil ? "¿Quién se prueba la ropa?" : "Tu foto",
            subtitle: "Tu cara, de frente y con luz. El cuerpo lo ponen las medidas del paso siguiente.",
            stepID: Step.photo,
            transition: flow.transition,
            primaryTitle: "Siguiente",
            isPrimaryEnabled: !imageKey.isEmpty,
            isAtRoot: flow.isAtRoot,
            onLeading: { leave() },
            onPrimary: { flow.move(to: .name) }
        ) {
            photoWell
        }
    }

    private var nameStep: some View {
        WKFlowScreen(
            title: "¿Cómo lo llamas?",
            subtitle: "Para distinguirlo de los otros perfiles.",
            stepID: Step.name,
            transition: flow.transition,
            primaryTitle: "Siguiente",
            isAtRoot: false,
            onLeading: { flow.move(to: .photo) },
            onPrimary: { flow.move(to: .body) }
        ) {
            TextField("Yo", text: $name)
                .font(WK.Font.title)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.words)
                .padding(WK.Spacing.m)
                .background(
                    WK.Palette.shelf,
                    in: .rect(cornerRadius: WK.Radius.medium, style: .continuous)
                )
        }
    }

    private var bodyStep: some View {
        WKFlowScreen(
            title: "¿Cómo eres?",
            subtitle: "Es lo que encuadra la escena y da a la ropa tus proporciones.",
            stepID: Step.body,
            transition: flow.transition,
            primaryTitle: "Siguiente",
            isAtRoot: false,
            onLeading: { flow.move(to: .name) },
            onPrimary: { flow.move(to: .extras) }
        ) {
            VStack(spacing: WK.Spacing.l) {
                // Rueda y no teclado: es un número de tres cifras dentro de un
                // rango conocido, y teclearlo obliga a abrir y cerrar el
                // teclado por 170.
                WKWheelPicker(items: Array(140...210), selection: $height, rowHeight: 44) { value in
                    Text("\(value) cm")
                        .font(WK.Font.rowTitle)
                        .monospacedDigit()
                        .foregroundStyle(
                            value == height ? WK.Palette.primaryText : WK.Palette.secondaryText
                        )
                }
                .frame(height: 132)

                // Filas de píldoras, antes: parecían un formulario, y la de
                // complexión se salía por la derecha.
                // chips("Complexión", BodyProfile.Shape.allCases, selection: $shape) { $0.label }
                // chips("Viste como", BodyProfile.Presentation.allCases, selection: $presentation) { $0.label }
                // chips("Piel", BodyProfile.SkinTone.allCases, selection: $skinTone) { $0.label }

                // Lo que se elige de una lista, en menús dentro de una tarjeta
                // de cristal: se ve el valor elegido y cambiarlo son dos
                // toques.
                VStack(spacing: 0) {
                    menuRow("Complexión", BodyProfile.Shape.allCases, selection: $shape) { $0.label }
                    Divider().padding(.leading, WK.Spacing.m)
                    menuRow("Viste como", BodyProfile.Presentation.allCases, selection: $presentation) { $0.label }
                }
                .adaptiveGlass(in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))

                skinSwatches
            }
        }
    }

    private var extrasStep: some View {
        WKFlowScreen(
            title: "¿Algo más?",
            subtitle: "Lo que no cabe arriba: gafas, barba, pelo largo.",
            stepID: Step.extras,
            transition: flow.transition,
            primaryTitle: "Guardar",
            isAtRoot: false,
            onLeading: { flow.move(to: .body) },
            onPrimary: { save() }
        ) {
            VStack(spacing: WK.Spacing.m) {
                TextField("Opcional", text: $notes, axis: .vertical)
                    .font(WK.Font.rowTitle)
                    .lineLimit(2...4)
                    .padding(WK.Spacing.m)
                    .background(
                        WK.Palette.shelf,
                        in: .rect(cornerRadius: WK.Radius.medium, style: .continuous)
                    )

                // Lo que se le va a decir al modelo, tal cual. Enseñarlo no es
                // un adorno: es lo que evita la sensación de haber rellenado
                // una ficha sin saber para qué.
                Text("Se dibujará " + draft.described + ".")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Piezas

    /// La foto, **redonda y de frente**.
    ///
    /// Redonda porque es un retrato: un rectángulo 3:4 pedía un cuerpo entero
    /// sin decirlo, y lo que se pide es una cara. Vacío enseña la silueta y
    /// las dos formas de traerla —hacerla o buscarla—, que es una decisión que
    /// no se puede dar por hecha: media gente tiene ya la foto y la otra media
    /// la hace en el momento.
    @ViewBuilder
    private var photoWell: some View {
        VStack(spacing: WK.Spacing.l) {
            portrait
            HStack(spacing: WK.Spacing.s) {
                // Cristal interactivo, no cápsulas grises.
                Button { isTakingPhoto = true } label: {
                    Label("Hacer una foto", systemImage: "camera")
                        .font(WK.Font.captionMedium)
                        .foregroundStyle(WK.Palette.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WK.Spacing.m)
                        // .background(WK.Palette.ink(0.06), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .adaptiveGlassInteractive(in: .capsule)

                PhotosPicker(selection: $picked, matching: .images) {
                    GlassCapsuleLabel(title: "Elegir una", symbol: "photo.on.rectangle")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var portrait: some View {
        ZStack {
            if imageKey.isEmpty {
                Circle()
                    .fill(WK.Palette.ink(0.04))
                    .overlay {
                        Circle().strokeBorder(
                            WK.Palette.ink(0.14),
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                        )
                    }
                    .overlay {
                        Group {
                            if isLoadingPhoto {
                                ProgressView()
                            } else {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 52, weight: .light))
                                    .foregroundStyle(WK.Palette.secondaryText)
                            }
                        }
                    }
            } else {
                StoredImage(
                    key: imageKey,
                    variant: .display,
                    store: appEnvironment.imageStore
                )
                .aspectRatio(contentMode: .fill)
                .clipShape(.circle)
                .overlay(alignment: .bottomTrailing) {
                    WKCircleButton("trash", size: .compact) { removePhoto() }
                        .tint(WK.Palette.primaryText)
                }
            }
        }
        // Un retrato mide lo que mide una cara en una hoja: grande para que se
        // vea quién es, sin comerse el paso entero.
        .frame(width: 180, height: 180)
    }

    /// Un icono redondo de cristal. En su propia `View` porque la etiqueta de
    /// un selector de fotos no está en el actor principal y el cristal sí.
    private struct GlassCircleLabel: View {
        let symbol: String

        var body: some View {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(WK.Palette.primaryText)
                .frame(width: 34, height: 34)
                .contentShape(.circle)
                .adaptiveGlassInteractive(in: .circle)
        }
    }

    /// Una etiqueta de cápsula de cristal. En su propia `View` por lo mismo
    /// que `GlassCircleLabel`: la etiqueta del selector de fotos no está en el
    /// actor principal.
    private struct GlassCapsuleLabel: View {
        let title: String
        let symbol: String

        var body: some View {
            Label(title, systemImage: symbol)
                .font(WK.Font.captionMedium)
                .foregroundStyle(WK.Palette.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, WK.Spacing.m)
                .contentShape(.capsule)
                .adaptiveGlassInteractive(in: .capsule)
        }
    }

    /// Una fila con su valor y un menú para cambiarlo.
    private func menuRow<Option: Hashable & CaseIterable>(
        _ title: String,
        _ options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String
    ) -> some View {
        Menu {
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
        } label: {
            HStack {
                Text(title)
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.primaryText)
                Spacer()
                Text(label(selection.wrappedValue))
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .contentTransition(.opacity)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WK.Palette.tertiaryText)
            }
            .padding(.horizontal, WK.Spacing.m)
            .padding(.vertical, WK.Spacing.m - 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// El tono de piel, **en muestras del tono** y no en palabras: "morena"
    /// se entiende distinto en cada casa, un círculo de color no.
    private var skinSwatches: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            Text("Piel")
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
            // Las mismas muestras que en la edición. Ver `SkinToneSwatches`.
            SkinToneSwatches(selection: $skinTone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func swatch(_ tone: BodyProfile.SkinTone) -> Color {
        switch tone {
        case .light: Color(red: 0.96, green: 0.84, blue: 0.74)
        case .medium: Color(red: 0.87, green: 0.68, blue: 0.53)
        case .tan: Color(red: 0.68, green: 0.48, blue: 0.33)
        case .dark: Color(red: 0.40, green: 0.26, blue: 0.18)
        }
    }

    /// Una fila de píldoras para elegir de una lista corta.
    private func chips<Option: Hashable & CaseIterable>(
        _ title: String,
        _ options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: WK.Spacing.xs) {
            Text(title)
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
            ScrollView(.horizontal) {
                HStack(spacing: WK.Spacing.xs) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            withAnimation(WKAnimation.selection) {
                                selection.wrappedValue = option
                            }
                        } label: {
                            Text(label(option))
                                .font(WK.Font.caption)
                                .foregroundStyle(
                                    selection.wrappedValue == option
                                        ? WK.Palette.onAccent
                                        : WK.Palette.primaryText
                                )
                                .fixedSize()
                                .padding(.horizontal, WK.Spacing.m)
                                .padding(.vertical, WK.Spacing.s)
                                .background {
                                    Capsule().fill(
                                        selection.wrappedValue == option
                                            ? WK.Palette.accent
                                            : WK.Palette.ink(0.06)
                                    )
                                }
                        }
                        .buttonStyle(WKPressStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Un perfil de mentira con lo que hay en pantalla, solo para la frase.
    private var draft: BodyProfile {
        BodyProfile(
            label: name,
            heightCentimetres: height ?? 170,
            shape: shape,
            presentation: presentation,
            skinTone: skinTone,
            notes: notes
        )
    }

    // MARK: Datos

    private func load() {
        guard baseline == nil else { return }
        if let profile {
            name = profile.label
            height = profile.heightCentimetres ?? 170
            shape = profile.shape ?? .average
            presentation = profile.presentation ?? .neutral
            skinTone = profile.skinTone ?? .medium
            notes = profile.notes ?? ""
            imageKey = profile.imageKey
        }
        baseline = current
    }

    /// Salir. Si hay algo que perder, se pregunta; si no, se sale sin ruido —
    /// preguntar por un perfil que nadie ha tocado es un paso de más.
    private func leave() {
        if hasProgress {
            isConfirmingExit = true
        } else {
            dismiss()
        }
    }

    private func save() {
        let label = name.trimmingCharacters(in: .whitespaces)
        let target = profile ?? BodyProfile(label: label.isEmpty ? "Yo" : label)
        target.label = label.isEmpty ? "Yo" : label
        target.heightCentimetres = height ?? 170
        target.shapeRaw = shape.rawValue
        target.presentationRaw = presentation.rawValue
        target.skinToneRaw = skinTone.rawValue
        target.notes = notes.trimmingCharacters(in: .whitespaces)
        target.imageKey = imageKey
        if profile == nil { modelContext.insert(target) }
        try? modelContext.save()
        dismiss()
    }

    private func storePhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)?.cgImage
        else { return }
        await store(image)
        picked = nil
    }

    /// Guardar la imagen venga de donde venga: del carrete o de la cámara.
    private func store(_ image: CGImage) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        guard let key = try? await appEnvironment.imageStore.store(image) else { return }
        withAnimation(WKAnimation.content) { imageKey = key }
        isTakingPhoto = false
    }

    /// Quitar la foto **es revocar el permiso**: se va la imagen y se va lo
    /// que se aceptó sobre ella.
    private func removePhoto() {
        let key = imageKey
        withAnimation(WKAnimation.content) { imageKey = "" }
        profile?.consentAcceptedAt = nil
        Task { try? await appEnvironment.imageStore.delete(key: key) }
    }
}
