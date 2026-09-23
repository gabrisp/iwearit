import PhotosUI
import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Quién se prueba la ropa.
///
/// ## Por qué un perfil no es una foto
///
/// Porque una foto tuya de cuerpo entero, de frente y con buena luz no la tiene
/// casi nadie a mano, y pedirla antes de dejarte probar nada cierra la puerta
/// en el primer paso. Lo que hace falta para ver cómo cae una camisa es la
/// forma: estatura, complexión, cómo vistes. Con eso se dibuja a alguien con tu
/// forma llevando tu ropa, que es lo que se venía a ver.
///
/// La foto sigue siendo la versión buena cuando la hay —es tu cara y tu
/// cuerpo—, así que se puede añadir, y entonces manda ella. Los dos caminos
/// conviven porque resuelven dos momentos distintos: el de "a ver qué tal me
/// queda" y el de "quiero verme yo".
struct TryOnProfileSheet: View {
    /// El que se edita. `nil` = uno nuevo.
    var profile: BodyProfile?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var name = ""
    @State private var height: Int = 170
    @State private var shape: BodyProfile.Shape = .average
    @State private var presentation: BodyProfile.Presentation = .neutral
    @State private var skinTone: BodyProfile.SkinTone = .medium
    @State private var notes = ""
    @State private var picked: PhotosPickerItem?
    @State private var imageKey = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WK.Spacing.l) {
                    WKSection("Nombre") {
                        WKRow(showsSeparator: false) {
                            TextField("Yo", text: $name)
                                .font(WK.Font.rowTitle)
                                .textInputAutocapitalization(.words)
                        }
                    }

                    WKSection("Cuerpo", footer: preview) {
                        WKRow {
                            Text("Estatura").font(WK.Font.rowTitle)
                        } trailing: {
                            // Rueda y no teclado: es un número de tres cifras
                            // dentro de un rango conocido, y teclearlo obliga a
                            // abrir y cerrar el teclado por 170.
                            Picker("", selection: $height) {
                                ForEach(140...210, id: \.self) { value in
                                    Text("\(value) cm").tag(value)
                                }
                            }
                            .labelsHidden()
                            .tint(WK.Palette.primaryText)
                        }
                        chips("Complexión", BodyProfile.Shape.allCases, selection: $shape) { $0.label }
                        chips("Viste como", BodyProfile.Presentation.allCases, selection: $presentation) { $0.label }
                        chips("Piel", BodyProfile.SkinTone.allCases, selection: $skinTone, isLast: true) { $0.label }
                    }

                    WKSection("Algo más", footer: "Lo que no cabe arriba: gafas, barba, pelo largo.") {
                        WKRow(showsSeparator: false) {
                            TextField("Opcional", text: $notes, axis: .vertical)
                                .font(WK.Font.rowTitle)
                                .lineLimit(1...3)
                        }
                    }

                    photoSection
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.bottom, WK.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .background(WK.Palette.canvas.ignoresSafeArea())
            .navigationTitle(profile == nil ? "Nuevo perfil" : "Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(WK.Palette.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { save() } label: { Image(systemName: "checkmark") }
                        .tint(WK.Palette.primaryText)
                        .adaptiveProminentButton()
                }
            }
            .task { load() }
            .task(id: picked) { await storePhoto(picked) }
        }
    }

    /// Lo que se le va a decir al modelo, tal cual, mientras lo escribes.
    ///
    /// Enseñarlo no es un adorno: es lo que evita la sensación de estar
    /// rellenando una ficha que no se sabe para qué sirve.
    private var preview: String {
        "Se dibujará " + draft.described + "."
    }

    /// Un perfil de mentira con lo que hay en pantalla, solo para la frase.
    private var draft: BodyProfile {
        BodyProfile(
            label: name,
            heightCentimetres: height,
            shape: shape,
            presentation: presentation,
            skinTone: skinTone,
            notes: notes
        )
    }

    @ViewBuilder
    private var photoSection: some View {
        WKSection(
            "Tu foto",
            footer: imageKey.isEmpty
                ? "Opcional. Con una foto tuya de cuerpo entero, te dibuja a ti; sin ella, a alguien con tu forma."
                : "Se procesa fuera del teléfono al probarte. Quitarla lo revoca."
        ) {
            if imageKey.isEmpty {
                PhotosPicker(selection: $picked, matching: .images) {
                    WKRow(showsSeparator: false) {
                        Text("Añadir una foto")
                            .font(WK.Font.rowTitle)
                            .foregroundStyle(WK.Palette.primaryText)
                    } trailing: {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundStyle(WK.Palette.secondaryText)
                    }
                }
            } else {
                WKRow(showsSeparator: false) {
                    removePhoto()
                } leading: {
                    HStack(spacing: WK.Spacing.m) {
                        StoredImage(
                            key: imageKey,
                            variant: .thumb,
                            store: appEnvironment.imageStore
                        )
                        .frame(width: 34, height: 44)
                        .clipShape(.rect(cornerRadius: 6, style: .continuous))
                        Text("Quitar la foto")
                            .font(WK.Font.rowTitle)
                            .foregroundStyle(WK.Palette.primaryText)
                    }
                } trailing: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(WK.Palette.secondaryText)
                }
            }
        }
    }

    /// Una fila de píldoras para elegir de una lista corta.
    private func chips<Option: Hashable & CaseIterable>(
        _ title: String,
        _ options: [Option],
        selection: Binding<Option>,
        isLast: Bool = false,
        label: @escaping (Option) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: WK.Spacing.xs) {
            Text(title)
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
            ScrollView(.horizontal) {
                HStack(spacing: WK.Spacing.xs) {
                    ForEach(options, id: \.self) { option in
                        Button { selection.wrappedValue = option } label: {
                            Text(label(option))
                                .font(WK.Font.caption)
                                .foregroundStyle(
                                    selection.wrappedValue == option
                                        ? WK.Palette.onAccent
                                        : WK.Palette.primaryText
                                )
                                .fixedSize()
                                .padding(.horizontal, WK.Spacing.m)
                                .padding(.vertical, WK.Spacing.xs)
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
        .padding(.vertical, WK.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(WK.Palette.ink(0.06))
                    .frame(height: 1)
            }
        }
    }

    // MARK: Datos

    private func load() {
        guard let profile, name.isEmpty else { return }
        name = profile.label
        height = profile.heightCentimetres ?? 170
        shape = profile.shape ?? .average
        presentation = profile.presentation ?? .neutral
        skinTone = profile.skinTone ?? .medium
        notes = profile.notes ?? ""
        imageKey = profile.imageKey
    }

    private func save() {
        let label = name.trimmingCharacters(in: .whitespaces)
        let target = profile ?? BodyProfile(label: label.isEmpty ? "Yo" : label)
        target.label = label.isEmpty ? "Yo" : label
        target.heightCentimetres = height
        target.shapeRaw = shape.rawValue
        target.presentationRaw = presentation.rawValue
        target.skinToneRaw = skinTone.rawValue
        target.notes = notes.trimmingCharacters(in: .whitespaces)
        target.imageKey = imageKey
        // Sin foto no hay nada que consentir, y el permiso viejo no puede
        // quedarse puesto para la siguiente foto que se añada.
        if imageKey.isEmpty { target.consentAcceptedAt = nil }
        if profile == nil { modelContext.insert(target) }
        try? modelContext.save()
        dismiss()
    }

    private func storePhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)?.cgImage,
              let key = try? await appEnvironment.imageStore.store(image)
        else { return }
        imageKey = key
        picked = nil
    }

    private func removePhoto() {
        let key = imageKey
        imageKey = ""
        profile?.consentAcceptedAt = nil
        Task { try? await appEnvironment.imageStore.delete(key: key) }
    }
}
