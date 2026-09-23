import PhotosUI
import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Quién se prueba la ropa.
///
/// ## Por qué la foto es obligatoria
///
/// Porque sin ella el probador no prueba nada: dibuja a **alguien** con tu
/// estatura y tu complexión llevando tu ropa, y eso se mira una vez y no se
/// vuelve. Lo que se viene a ver es cómo te queda a ti, y para eso hace falta
/// tu cara y tu cuerpo. Un perfil sin foto era una promesa a medias que además
/// competía con la buena.
///
/// Los datos de al lado no sobran por eso. La foto dice quién eres; la
/// estatura, la complexión y el resto dicen **cómo encuadrar la escena** —de
/// cuerpo entero, con las proporciones que te tocan— y son lo que evita que la
/// prenda salga a una talla que no es la tuya.
///
/// Y por eso se pide arriba y a tamaño de foto, no en una fila de lista: es lo
/// primero que hay que dar, así que es lo primero que se ve.
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
                    photoWell

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
                        // Sin foto no hay perfil que guardar. Apagado y no
                        // escondido: el botón sigue donde estará cuando se
                        // pueda tocar, y el hueco de arriba dice qué falta.
                        .disabled(imageKey.isEmpty)
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

    /// La foto, a tamaño de foto.
    ///
    /// Es el primer hueco de la hoja y ocupa lo que ocupa una persona de
    /// cuerpo entero, porque es lo que se pide. Vacío enseña la silueta y lo
    /// que hace falta —entera, de frente, con luz—; lleno enseña la foto y se
    /// aparta.
    @ViewBuilder
    private var photoWell: some View {
        if imageKey.isEmpty {
            PhotosPicker(selection: $picked, matching: .images) {
                VStack(spacing: WK.Spacing.s) {
                    Image(systemName: "figure.stand")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(WK.Palette.secondaryText)
                    Text("Tu foto de cuerpo entero")
                        .font(WK.Font.rowTitle)
                        .foregroundStyle(WK.Palette.primaryText)
                    Text("De frente, entera y con buena luz.")
                        .font(WK.Font.caption)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(WK.Palette.ink(0.04))
                        .overlay {
                            // Un trazo discontinuo: dice "aquí va algo que
                            // todavía no está" sin necesidad de un cartel.
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(
                                    WK.Palette.ink(0.14),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                                )
                        }
                }
            }
            .buttonStyle(WKPressStyle())
        } else {
            StoredImage(
                key: imageKey,
                variant: .display,
                store: appEnvironment.imageStore
            )
            .aspectRatio(3.0 / 4.0, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: WK.Spacing.xs) {
                    PhotosPicker(selection: $picked, matching: .images) {
                        // La misma pieza que los botones de los lienzos, para
                        // que un botón redondo sobre una imagen sea siempre el
                        // mismo botón redondo. En su propia `View` porque la
                        // etiqueta del selector no está en el actor principal
                        // y el cristal sí.
                        GlassCircleLabel(symbol: "arrow.trianglehead.2.clockwise")
                    }
                    .buttonStyle(WKPressStyle())
                    WKCircleButton("trash", size: .compact) { removePhoto() }
                        .tint(WK.Palette.primaryText)
                }
                .padding(WK.Spacing.m)
            }
            .overlay(alignment: .bottomLeading) {
                Text("Se procesa fuera del teléfono al probarte. Quitarla lo revoca.")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.onAccent.opacity(0.9))
                    .padding(WK.Spacing.m)
                    .frame(maxWidth: 220, alignment: .leading)
            }
        }
    }

    /// Un icono redondo de cristal, del tamaño de los de los lienzos.
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
