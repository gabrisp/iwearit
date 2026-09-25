import PhotosUI
import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// **Editar un perfil que ya existe**, con la forma de la hoja de editar
/// prendas: la foto arriba, y debajo cada dato en su fila, todos a la vista.
///
/// Crear un perfil es un flujo de pasos —foto, nombre, cómo eres— porque se
/// empieza de cero y conviene ir de uno en uno. Editarlo no: se viene a
/// cambiar una cosa, y recorrer cuatro pantallas para cambiar la altura era
/// pagar el flujo de creación entero cada vez.
///
/// Se edita el perfil **en vivo**, como la prenda: cada cambio ya es el perfil.
struct ProfileEditSheet: View {
    @Bindable var profile: BodyProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var picked: PhotosPickerItem?
    @State private var isPickingPhoto = false
    @State private var isLoadingPhoto = false
    @State private var isConfirmingDelete = false
    /// Qué dato se está cambiando, en su hoja. Igual que en la ficha de una
    /// prenda: cada fila abre la suya. Ver `GarmentEditSheet`.
    @State private var editing: Field?

    private enum Field: String, Identifiable {
        // La piel ya no abre hoja: van las muestras a la vista, como antes.
        // case height, shape, presentation, skin
        case height, shape, presentation
        /// Afinar el cuerpo con fotos. Ver `BodyPhotosSheet`.
        case body
        /// La cámara, en la misma hoja: dos `.sheet` en una vista dejan mudo
        /// a uno.
        case camera
        var id: String { rawValue }
    }

    // **La misma forma que editar una prenda**: la imagen arriba, los datos
    // en filas que abren su hoja de opciones, y la foto en su sección al
    // final. Antes eran menús y muestras sueltas, y no se parecía a nada.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WK.Spacing.m) {
                    hero
                    rows
                    // La foto se cambia con los botones de debajo del retrato,
                    // como antes. La sección de foto se queda comentada.
                    // photoSection
                    Text(String(localized: "tryon.profileeditsheet.itWillBeDrawnAs", defaultValue: "It will be drawn as ") + profile.described + ".")
                        .font(WK.Font.caption)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.top, WK.Spacing.m)
                .padding(.bottom, WK.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WK.Palette.canvas.ignoresSafeArea())
            .navigationTitle(String(localized: "common.edit", defaultValue: "Edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isConfirmingDelete = true } label: {
                        Image(systemName: "trash")
                            .font(WK.Font.headline)
                            .foregroundStyle(.red)
                            .contentShape(.rect)
                    }
                }
            }
            .sheet(item: $editing) { field in sheet(for: field) }
            .alert(String(localized: "tryon.profileeditsheet.deleteThisProfile", defaultValue: "Delete this profile?"), isPresented: $isConfirmingDelete) {
                Button(String(localized: "tryon.profileeditsheet.delete", defaultValue: "Delete"), role: .destructive) { remove() }
                Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "tryon.profileeditsheet.itsPhotoIsDeletedAnd", defaultValue: "Its photo is deleted and it can no longer be used in the fitting room. What you already tried on stays."))
            }
            .photosPicker(isPresented: $isPickingPhoto, selection: $picked, matching: .images)
            .task(id: picked) { await storePicked() }
            .onDisappear { try? modelContext.save() }
        }
        .presentationDetents([.large])
    }

    // MARK: Imagen

    // La foto del mismo alto que la prenda en su ficha, en rectángulo: se
    // queda comentada. El retrato redondo de antes era el bueno.
    // private var hero: some View {
    //     Group {
    //         if profile.hasPhoto {
    //             StoredImage(
    //                 key: profile.imageKey,
    //                 variant: .display,
    //                 store: appEnvironment.imageStore,
    //                 shadow: .init(opacity: 0.35, radius: 18, y: 11)
    //             )
    //             .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
    //         } else {
    //             ToneIcon("person.fill", tone: .at(abs(profile.id.hashValue)), size: 150)
    //         }
    //     }
    //     .frame(height: 230)
    //     .frame(maxWidth: .infinity)
    //     .wkShimmer(isActive: isLoadingPhoto)
    // }

    /// La foto en grande, redonda, y cómo cambiarla debajo.
    private var hero: some View {
        VStack(spacing: WK.Spacing.m) {
            ZStack {
                if profile.hasPhoto {
                    StoredImage(key: profile.imageKey, variant: .display, store: appEnvironment.imageStore)
                        .scaledToFill()
                } else {
                    ToneIcon("person.fill", tone: .at(abs(profile.id.hashValue)), size: 150)
                }
                if isLoadingPhoto { ProgressView() }
            }
            .frame(width: 150, height: 150)
            .clipShape(.circle)
            .wkShimmer(isActive: isLoadingPhoto)
            .shadow(color: .black.opacity(0.12), radius: 14, y: 8)

            HStack(spacing: WK.Spacing.s) {
                // La cámara va por la única hoja de la vista. Ver `Field`.
                GlassLabelButton(title: String(localized: "common.takeAPhoto", defaultValue: "Take a photo"), symbol: "camera") { editing = .camera }
                GlassLabelButton(title: String(localized: "tryon.profileeditsheet.change", defaultValue: "Change"), symbol: "photo.on.rectangle") { isPickingPhoto = true }
            }
            .disabled(isLoadingPhoto)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, WK.Spacing.s)
    }

    // MARK: Datos

    private var rows: some View {
        VStack(spacing: 0) {
            NameRow(name: $profile.label)
            // La altura, en una rueda en su hoja, como la balda de una prenda.
            // Ver `HeightPickerSheet`.
            EditRow(value: String(localized: "tryon.profileeditsheet.cm", defaultValue: "\(String(describing: height)) cm"), label: String(localized: "tryon.profileeditsheet.height", defaultValue: "Height")) { editing = .height }
            EditRow(value: shape.label, label: String(localized: "tryon.profileeditsheet.build", defaultValue: "Build")) { editing = .shape }
            EditRow(value: presentation.label, label: String(localized: "tryon.profileeditsheet.dressesAs", defaultValue: "Dresses as")) { editing = .presentation }
            // La piel no abre hoja: cuatro muestras a la vista y se toca la
            // que es, como antes.
            // EditRow(value: skinTone.label, label: String(localized: "tryon.profileeditsheet.skin2", defaultValue: "Skin")) { editing = .skin }
            SkinRow(selection: skinToneBinding)
            // Hasta cuatro fotos de cuerpo entero. Ver `BodyPhotosSheet`.
            EditRow(value: bodyValue, label: String(localized: "tryon.body.row", defaultValue: "Fine-tune body")) { editing = .body }
            NotesRow(notes: notes)
        }
    }

    /// La hoja de cada dato: las mismas hojas de opciones que la prenda.
    @ViewBuilder
    private func sheet(for field: Field) -> some View {
        switch field {
        case .height:
            // Rueda, como la de elegir balda. Las píldoras de 5 en 5 se
            // quedan comentadas.
            HeightPickerSheet(profile: profile)
        //     WKChipSheet(
        //         title: String(localized: "tryon.profileeditsheet.height", defaultValue: "Height"),
        //         subtitle: String(localized: "tryon.profileeditsheet.pickYoursOrTypeIt", defaultValue: "Pick yours or type it in centimetres"),
        //         options: stride(from: 145, through: 205, by: 5).map { .init(id: "\($0)", label: String(localized: "tryon.profileeditsheet.cm", defaultValue: "\(String(describing: $0)) cm")) },
        //         selection: Binding(
        //             get: { ["\(height)"] },
        //             set: { set in
        //                 let digits = set.first?.filter(\.isNumber) ?? ""
        //                 if let value = Int(digits), (120...230).contains(value) {
        //                     profile.heightCentimetres = value
        //                 }
        //             }
        //         ),
        //         limit: 1,
        //         allowsCustom: true
        //     )
        case .shape:
            WKChipSheet(
                title: String(localized: "tryon.profileeditsheet.build", defaultValue: "Build"),
                subtitle: String(localized: "tryon.profileeditsheet.givesTheClothesYourProportions", defaultValue: "Gives the clothes your proportions"),
                options: BodyProfile.Shape.allCases.map { .init(id: $0.rawValue, label: $0.label) },
                selection: Binding(
                    get: { [shape.rawValue] },
                    set: { if let raw = $0.first { profile.shapeRaw = raw } }
                ),
                limit: 1
            )
        case .presentation:
            WKChipSheet(
                title: String(localized: "tryon.profileeditsheet.dressesAs", defaultValue: "Dresses as"),
                subtitle: String(localized: "tryon.profileeditsheet.howTheClothesAreDrawn", defaultValue: "How the clothes are drawn on you"),
                options: BodyProfile.Presentation.allCases.map { .init(id: $0.rawValue, label: $0.label) },
                selection: Binding(
                    get: { [presentation.rawValue] },
                    set: { if let raw = $0.first { profile.presentationRaw = raw } }
                ),
                limit: 1
            )
        case .body:
            BodyPhotosSheet(profile: profile)
        case .camera:
            CameraScreen { images in
                guard let first = images.first else { return }
                Task { await store(first) }
            }
        // La piel, en muestras a la vista. Ver `SkinRow`.
        // case .skin:
        //     WKChipSheet(
        //         title: String(localized: "tryon.profileeditsheet.skin2", defaultValue: "Skin"),
        //         subtitle: String(localized: "tryon.profileeditsheet.theToneYouReDrawn", defaultValue: "The tone you're drawn with"),
        //         options: BodyProfile.SkinTone.allCases.map { .init(id: $0.rawValue, label: $0.label) },
        //         selection: Binding(
        //             get: { [skinTone.rawValue] },
        //             set: { if let raw = $0.first { profile.skinToneRaw = raw } }
        //         ),
        //         limit: 1
        //     )
        }
    }

    /// La foto, al final, como la sección de imagen de la prenda.
    private var photoSection: some View {
        WKSection(String(localized: "common.photo", defaultValue: "Photo"), footer: String(localized: "tryon.profileeditsheet.itWillBeDrawnAs", defaultValue: "It will be drawn as ") + profile.described + ".") {
            WKRow(action: { editing = .camera }) {
                Label(String(localized: "common.takeAPhoto", defaultValue: "Take a photo"), systemImage: "camera")
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.primaryText)
                Spacer()
            }
            WKRow(showsSeparator: false, action: { isPickingPhoto = true }) {
                Label(String(localized: "tryon.profileeditsheet.chooseAnotherFromTheLibrary", defaultValue: "Choose another from the library"), systemImage: "photo.on.rectangle")
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.primaryText)
                Spacer()
            }
        }
        .disabled(isLoadingPhoto)
    }

    private func storePicked() async {
        guard let picked else { return }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        guard let data = try? await picked.loadTransferable(type: Data.self),
              let image = UIImage(data: data)?.cgImage
        else { return }
        await store(image)
        self.picked = nil
    }

    /// Guarda la foto nueva y tira la vieja.
    private func store(_ image: CGImage) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        guard let key = try? await appEnvironment.imageStore.store(image) else { return }
        let old = profile.imageKey
        withAnimation(WKAnimation.content) { profile.imageKey = key }
        try? modelContext.save()
        editing = nil
        if !old.isEmpty, old != key { try? await appEnvironment.imageStore.delete(key: old) }
    }

    /// Borrar un perfil **es revocar el permiso**: se van la foto y la fecha.
    private func remove() {
        let key = profile.imageKey
        // Y las del cuerpo, que también son fotos tuyas.
        let bodyKeys = profile.bodyImageKeys
        Task { for key in bodyKeys { try? await appEnvironment.imageStore.delete(key: key) } }
        modelContext.delete(profile)
        try? modelContext.save()
        if !key.isEmpty { Task { try? await appEnvironment.imageStore.delete(key: key) } }
        dismiss()
    }

    // MARK: Valores

    private var height: Int { profile.heightCentimetres ?? 170 }

    private var bodyValue: String {
        let count = profile.bodyImageKeys.count
        return count == 0
            ? String(localized: "tryon.body.none", defaultValue: "No photos")
            : String(localized: "tryon.body.count", defaultValue: "\(String(describing: count)) of 4 photos")
    }
    private var shape: BodyProfile.Shape { profile.shape ?? .average }
    private var presentation: BodyProfile.Presentation { profile.presentation ?? .neutral }
    private var skinTone: BodyProfile.SkinTone { profile.skinTone ?? .medium }

    private var skinToneBinding: Binding<BodyProfile.SkinTone> {
        Binding(get: { profile.skinTone ?? .medium }, set: { profile.skinToneRaw = $0.rawValue })
    }

    private var notes: Binding<String> {
        Binding(get: { profile.notes ?? "" }, set: { profile.notes = $0 })
    }
}

/// Una fila con su valor y un menú para cambiarlo, con la forma de `EditRow`.
private struct MenuRow<Option: Hashable>: View {
    let label: String
    let value: String
    let options: [Option]
    @Binding var selection: Option
    var showsSeparator = true
    let title: (Option) -> String

    init(
        label: String,
        value: String,
        options: [Option],
        selection: Binding<Option>,
        showsSeparator: Bool = true,
        title: @escaping (Option) -> String
    ) {
        self.label = label
        self.value = value
        self.options = options
        _selection = selection
        self.showsSeparator = showsSeparator
        self.title = title
    }

    var body: some View {
        VStack(spacing: 0) {
            Menu {
                Picker(label, selection: $selection) {
                    ForEach(options, id: \.self) { Text(title($0)).tag($0) }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(value)
                            .font(WK.Font.rowTitle)
                            .foregroundStyle(WK.Palette.primaryText)
                            .contentTransition(.opacity)
                        Text(label)
                            .font(WK.Font.caption)
                            .foregroundStyle(WK.Palette.tertiaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(WK.Palette.tertiaryText)
                }
                .padding(.vertical, WK.Spacing.m - 2)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if showsSeparator {
                Rectangle().fill(WK.Palette.ink(0.07)).frame(height: 1)
            }
        }
    }
}

/// La piel, en su fila: la etiqueta pequeña arriba y las muestras debajo,
/// con la forma de `CutChipsRow`.
private struct SkinRow: View {
    @Binding var selection: BodyProfile.SkinTone

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: WK.Spacing.s) {
                Text(String(localized: "tryon.profileeditsheet.skin2", defaultValue: "Skin"))
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
                SkinToneSwatches(selection: $selection)
            }
            .padding(.vertical, WK.Spacing.m - 2)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(WK.Palette.ink(0.07)).frame(height: 1)
        }
    }
}

/// Elegir la altura con una rueda, igual que la balda de una prenda. Ver
/// `ShelfPickerSheet`.
///
/// Rueda y no teclado: es un número de tres cifras dentro de un rango
/// conocido, y recorrerlo es un solo gesto.
private struct HeightPickerSheet: View {
    @Bindable var profile: BodyProfile

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int?

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            Text(String(localized: "tryon.profileeditsheet.height", defaultValue: "Height"))
                .font(WK.Font.title)
                .foregroundStyle(WK.Palette.primaryText)

            WKWheelPicker(
                items: Array(120...230),
                selection: $selection
            ) { value in
                Text(String(localized: "tryon.profileeditsheet.cm", defaultValue: "\(String(describing: value)) cm"))
                    .font(WK.Font.title)
                    .monospacedDigit()
            }
            .frame(height: 220)

            WKPrimaryButton(String(localized: "tryon.profileeditsheet.useThisHeight", defaultValue: "Use this height")) { apply() }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .wkDynamicSheet()
        .onAppear { selection = profile.heightCentimetres ?? 170 }
    }

    private func apply() {
        if let selection { profile.heightCentimetres = selection }
        dismiss()
    }
}

/// Un botón de cápsula de cristal con icono y texto.
private struct GlassLabelButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(WK.Font.captionMedium)
                .foregroundStyle(WK.Palette.primaryText)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s + 2)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .adaptiveGlassInteractive(in: .capsule)
    }
}

/// El tono de piel en muestras del tono, con anillo por fuera en la elegida.
/// Lo usan la creación y la edición de perfiles.
struct SkinToneSwatches: View {
    @Binding var selection: BodyProfile.SkinTone

    var body: some View {
        HStack(spacing: WK.Spacing.l) {
            ForEach(BodyProfile.SkinTone.allCases, id: \.self) { tone in
                Button {
                    withAnimation(WKAnimation.selection) { selection = tone }
                } label: {
                    VStack(spacing: WK.Spacing.xs) {
                        Circle()
                            .fill(Self.color(tone))
                            .frame(width: 44, height: 44)
                            .padding(4)
                            .overlay {
                                Circle().stroke(selection == tone ? WK.Palette.accent : .clear, lineWidth: 2)
                            }
                        Text(tone.label)
                            .font(selection == tone ? WK.Font.captionMedium : WK.Font.caption)
                            .foregroundStyle(selection == tone ? WK.Palette.primaryText : WK.Palette.secondaryText)
                    }
                }
                .buttonStyle(WKPressStyle())
                .accessibilityLabel(String(localized: "tryon.profileeditsheet.skin", defaultValue: "Skin \(String(describing: tone.label))"))
                .accessibilityAddTraits(selection == tone ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    static func color(_ tone: BodyProfile.SkinTone) -> Color {
        switch tone {
        case .light: Color(red: 0.96, green: 0.84, blue: 0.74)
        case .medium: Color(red: 0.87, green: 0.68, blue: 0.53)
        case .tan: Color(red: 0.68, green: 0.48, blue: 0.33)
        case .dark: Color(red: 0.40, green: 0.26, blue: 0.18)
        }
    }
}
