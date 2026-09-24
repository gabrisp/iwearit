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
    @State private var isTakingPhoto = false
    @State private var isLoadingPhoto = false
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WK.Spacing.l) {
                    hero
                    WKSection("Datos") {
                        NameRow(name: $profile.label)
                        MenuRow(
                            label: "Altura",
                            value: "\(height.wrappedValue) cm",
                            options: Array(140...210),
                            selection: height
                        ) { "\($0) cm" }
                        MenuRow(
                            label: "Complexión",
                            value: shape.wrappedValue.label,
                            options: BodyProfile.Shape.allCases,
                            selection: shape
                        ) { $0.label }
                        MenuRow(
                            label: "Viste como",
                            value: presentation.wrappedValue.label,
                            options: BodyProfile.Presentation.allCases,
                            selection: presentation,
                            showsSeparator: false
                        ) { $0.label }
                    }
                    WKSection("Piel") {
                        SkinToneSwatches(selection: skinTone)
                            .padding(.vertical, WK.Spacing.m)
                    }
                    WKSection("Algo más", footer: "Se dibujará " + profile.described + ".") {
                        NotesRow(notes: notes)
                    }
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.top, WK.Spacing.m)
                .padding(.bottom, WK.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .background(WK.Palette.canvas.ignoresSafeArea())
            .navigationTitle("Editar perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isConfirmingDelete = true } label: {
                        Image(systemName: "trash")
                            .font(WK.Font.headline)
                            .foregroundStyle(.red)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(WK.Font.headline)
                    }
                    .tint(WK.Palette.primaryText)
                }
            }
            .alert("¿Borrar este perfil?", isPresented: $isConfirmingDelete) {
                Button("Borrar", role: .destructive) { remove() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se borra su foto y deja de poder usarse en el probador. Lo que ya te probaste se queda.")
            }
            .photosPicker(isPresented: $isPickingPhoto, selection: $picked, matching: .images)
            .task(id: picked) { await storePicked() }
            .sheet(isPresented: $isTakingPhoto) {
                CameraScreen { images in
                    guard let first = images.first else { return }
                    Task { await store(first) }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Foto

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
                GlassLabelButton(title: "Hacer una foto", symbol: "camera") { isTakingPhoto = true }
                GlassLabelButton(title: "Cambiar", symbol: "photo.on.rectangle") { isPickingPhoto = true }
            }
        }
        .frame(maxWidth: .infinity)
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
        isTakingPhoto = false
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

    // MARK: Datos

    private var height: Binding<Int> {
        Binding(get: { profile.heightCentimetres ?? 170 }, set: { profile.heightCentimetres = $0 })
    }

    private var shape: Binding<BodyProfile.Shape> {
        Binding(get: { profile.shape ?? .average }, set: { profile.shapeRaw = $0.rawValue })
    }

    private var presentation: Binding<BodyProfile.Presentation> {
        Binding(get: { profile.presentation ?? .neutral }, set: { profile.presentationRaw = $0.rawValue })
    }

    private var skinTone: Binding<BodyProfile.SkinTone> {
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
                .accessibilityLabel("Piel \(tone.label)")
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
