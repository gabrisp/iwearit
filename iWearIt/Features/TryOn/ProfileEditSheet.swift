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
        case height, shape, presentation, skin
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
                    photoSection
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

    /// La foto, del mismo alto que la prenda en su ficha.
    private var hero: some View {
        Group {
            if profile.hasPhoto {
                StoredImage(
                    key: profile.imageKey,
                    variant: .display,
                    store: appEnvironment.imageStore,
                    shadow: .init(opacity: 0.35, radius: 18, y: 11)
                )
                .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
            } else {
                ToneIcon("person.fill", tone: .at(abs(profile.id.hashValue)), size: 150)
            }
        }
        .frame(height: 230)
        .frame(maxWidth: .infinity)
        .wkShimmer(isActive: isLoadingPhoto)
    }

    // MARK: Datos

    private var rows: some View {
        VStack(spacing: 0) {
            NameRow(name: $profile.label)
            EditRow(value: String(localized: "tryon.profileeditsheet.cm", defaultValue: "\(String(describing: height)) cm"), label: String(localized: "tryon.profileeditsheet.height", defaultValue: "Height")) { editing = .height }
            EditRow(value: shape.label, label: String(localized: "tryon.profileeditsheet.build", defaultValue: "Build")) { editing = .shape }
            EditRow(value: presentation.label, label: String(localized: "tryon.profileeditsheet.dressesAs", defaultValue: "Dresses as")) { editing = .presentation }
            EditRow(value: skinTone.label, label: String(localized: "tryon.profileeditsheet.skin2", defaultValue: "Skin")) { editing = .skin }
            NotesRow(notes: notes)
        }
    }

    /// La hoja de cada dato: las mismas hojas de opciones que la prenda.
    @ViewBuilder
    private func sheet(for field: Field) -> some View {
        switch field {
        case .height:
            WKChipSheet(
                title: String(localized: "tryon.profileeditsheet.height", defaultValue: "Height"),
                subtitle: String(localized: "tryon.profileeditsheet.pickYoursOrTypeIt", defaultValue: "Pick yours or type it in centimetres"),
                options: stride(from: 145, through: 205, by: 5).map { .init(id: "\($0)", label: String(localized: "tryon.profileeditsheet.cm", defaultValue: "\(String(describing: $0)) cm")) },
                selection: Binding(
                    get: { ["\(height)"] },
                    set: { set in
                        let digits = set.first?.filter(\.isNumber) ?? ""
                        if let value = Int(digits), (120...230).contains(value) {
                            profile.heightCentimetres = value
                        }
                    }
                ),
                limit: 1,
                allowsCustom: true
            )
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
        case .camera:
            CameraScreen { images in
                guard let first = images.first else { return }
                Task { await store(first) }
            }
        case .skin:
            WKChipSheet(
                title: String(localized: "tryon.profileeditsheet.skin2", defaultValue: "Skin"),
                subtitle: String(localized: "tryon.profileeditsheet.theToneYouReDrawn", defaultValue: "The tone you're drawn with"),
                options: BodyProfile.SkinTone.allCases.map { .init(id: $0.rawValue, label: $0.label) },
                selection: Binding(
                    get: { [skinTone.rawValue] },
                    set: { if let raw = $0.first { profile.skinToneRaw = raw } }
                ),
                limit: 1
            )
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
        modelContext.delete(profile)
        try? modelContext.save()
        if !key.isEmpty { Task { try? await appEnvironment.imageStore.delete(key: key) } }
        dismiss()
    }

    // MARK: Valores

    private var height: Int { profile.heightCentimetres ?? 170 }
    private var shape: BodyProfile.Shape { profile.shape ?? .average }
    private var presentation: BodyProfile.Presentation { profile.presentation ?? .neutral }
    private var skinTone: BodyProfile.SkinTone { profile.skinTone ?? .medium }

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
