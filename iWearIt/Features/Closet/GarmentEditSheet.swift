import PhotosUI
import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence
import WKVision

/// Editar una prenda.
///
/// La prenda ocupa la pantalla y debajo van sus datos, cada uno con su valor
/// grande y la etiqueta pequeña debajo. Cambiar uno abre una hoja de chips: no
/// hay campos de texto libre salvo el nombre, porque escribir "pantaón" a mano
/// rompe la clasificación y nadie se entera.
struct GarmentEditSheet: View {
    @Bindable var garment: Garment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var editing: Field?
    @State private var isEnhancing = false
    @State private var isConfirmingDelete = false
    /// Trabajo de la sección de imagen: cambiar la foto o regenerar la de
    /// catálogo. Uno solo para las dos porque nunca van a la vez.
    @State private var isWorkingOnImage = false
    @State private var isPickingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var hasCatalog = false
    @State private var isCroppingByHand = false
    /// La imagen sobre la que se recorta a mano. Se carga al abrir la hoja: si
    /// se pidiera al tocar el botón, habría un parpadeo entre el toque y la
    /// pantalla de recorte.
    @State private var cropSource: CGImage?

    private enum Field: String, Identifiable {
        case shelf, type, cut, tags, warmth, material
        var id: String { rawValue }
    }

    // **En la barra de verdad**, como la hoja de crear outfit y la de baldas.
    //
    // La cabecera puesta a mano tenía que imitar a ojo lo que el sistema hace
    // solo: colocar el título, dar cristal a los botones en iOS 26 y difuminar
    // el contenido que pasa por debajo. Y quedaba distinta de las otras hojas,
    // que es lo que se nota.
    var body: some View {
        NavigationStack { content }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // **Con scroll.** La hoja cabía justo hasta que se le añadió la
            // sección de imagen; con ella, en un iPhone pequeño el último
            // control quedaba por debajo del borde y no había forma de llegar.
            ScrollView {
                VStack(spacing: WK.Spacing.m) {
                    hero
                    enhanceButton
                    rows
                    imageSection
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.top, WK.Spacing.m)
                .padding(.bottom, WK.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            // Sin recortar: la fila de imágenes tiene un aro que se sale.
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WK.Palette.canvas.ignoresSafeArea())
        .navigationTitle("Editar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { chrome }
        // **La única a pantalla completa.** Mirar una prenda es un vistazo y
        // por eso su hoja es del tamaño de su contenido; editarla es sentarse a
        // cambiar cinco campos, y ahí una hoja a media altura deja la imagen
        // recortada y las filas apretadas contra el teclado.
        .presentationDetents([.large])
        .sheet(item: $editing) { field in
            sheet(for: field)
        }
        .photosPicker(isPresented: $isPickingPhoto, selection: $photoItem, matching: .images)
        .task(id: photoItem) { await replacePhoto() }
        .task(id: garment.normalizedImageKey) {
            hasCatalog = await appEnvironment.imageStore.hasCatalog(
                for: garment.normalizedImageKey
            )
            // El recorte crudo si lo hay, y si no el normalizado: rodear a mano
            // sobre el recorte ya ajustado no puede devolver lo que se quedó
            // fuera, pero es mejor que nada.
            let key = garment.rawCropImageKey ?? garment.normalizedImageKey
            cropSource = try? await appEnvironment.imageStore.image(for: key, variant: .display)
        }
        .fullScreenCover(isPresented: $isCroppingByHand) {
            if let cropSource {
                ManualCropScreen(image: cropSource) { cropped in
                    Task { await applyManualCrop(cropped) }
                }
            }
        }
        .confirmationDialog(
            "¿Eliminar esta prenda?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                garment.markDeleted()
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    // MARK: Chrome

    @ToolbarContentBuilder
    private var chrome: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                garment.isFavorite.toggle()
            } label: {
                Image(systemName: garment.isFavorite ? "heart.fill" : "heart")
                    .font(WK.Font.headline)
                    .foregroundStyle(garment.isFavorite ? .red : WK.Palette.secondaryText)
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .scaleEffect(garment.isFavorite ? 1.08 : 1)
                    .contentShape(.rect)
            }
            .animation(.spring(duration: 0.32, bounce: 0.45), value: garment.isFavorite)
            .sensoryFeedback(.impact(weight: .medium), trigger: garment.isFavorite)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button { isConfirmingDelete = true } label: {
                Image(systemName: "trash")
                    .font(WK.Font.headline)
                    .foregroundStyle(.red)
                    .contentShape(.rect)
            }
        }
    }

    private var hero: some View {
        StoredImage(
            key: garment.normalizedImageKey,
            variant: .display,
            store: appEnvironment.imageStore,
            shadow: .init(opacity: 0.5, radius: 18, y: 11)
        )
        .frame(height: 230)
        .frame(maxWidth: .infinity)
        // El brillo recorre la silueta, no un rectángulo encima.
        .wkShimmer(isActive: isEnhancing)
    }

    /// Reprocesa el recorte y vuelve a deducir los atributos.
    ///
    /// Es útil porque la prenda se guardó con lo que el pipeline supo en ese
    /// momento: si desde entonces se ha descargado el modelo, o ha cambiado de
    /// versión, este botón aprovecha lo nuevo sin tener que volver a importar
    /// la foto.
    private var enhanceButton: some View {
        Button {
            Task { await enhance() }
        } label: {
            Label(isEnhancing ? "Mejorando…" : "mejorar", systemImage: "wand.and.sparkles")
                .font(WK.Font.callout)
                .foregroundStyle(WK.Palette.primaryText)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .background(WK.Palette.ink(0.07), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
        .disabled(isEnhancing)
    }

    // MARK: Datos

    private var rows: some View {
        VStack(spacing: 0) {
            NameRow(name: $garment.name)
            ColorRow(color: garment.dominantColor)
            // "Balda" y no "Parte": la balda es camisetas, pantalones… La parte
            // del cuerpo es un filtro para buscar, no un sitio.
            EditRow(
                value: garment.category?.name ?? "Sin balda",
                label: "Balda"
            ) { editing = .shelf }
            EditRow(
                value: garment.subcategory?.capitalized ?? "Sin definir",
                label: "Tipo"
            ) { editing = .type }
            if let cutTitle = GarmentVocabulary.cutTitle(for: garment.kind) {
                EditRow(
                    value: garment.cut ?? "Sin definir",
                    label: cutTitle
                ) { editing = .cut }
            }
            EditRow(
                value: garment.tags.isEmpty ? "Sin etiquetas" : garment.tags.joined(separator: " · "),
                label: "Etiquetas"
            ) { editing = .tags }
            EditRow(
                value: GarmentVocabulary.Warmth.from(garment.seasons).label,
                label: "Calidez"
            ) { editing = .warmth }

            // **Material, editable.** Lo propone el modelo y acierta a medias:
            // distingue un vaquero de un punto, y confunde lino con algodón
            // casi siempre. Enseñarlo sin poder tocarlo obliga a guardar algo
            // que ya sabes que está mal.
            EditRow(
                value: garment.material?.capitalized ?? "Sin definir",
                label: "Material"
            ) { editing = .material }

            // **Notas.** Un enlace a la ficha de la tienda, la talla que
            // compraste, con qué la sueles llevar. Es el campo donde cabe lo
            // que no cabe en ningún otro, y por eso no tiene formato.
            NotesRow(notes: notesBinding)
        }
    }

    /// Las notas, con vacío tratado como ausencia.
    ///
    /// `nil` y `""` son lo mismo para quien escribe y distintos para la base
    /// de datos: guardar cadenas vacías llena el modelo de campos que parecen
    /// puestos y no dicen nada.
    private var notesBinding: Binding<String> {
        Binding(
            get: { garment.notes ?? "" },
            set: { garment.notes = $0.isEmpty ? nil : $0 }
        )
    }

    @ViewBuilder
    private func sheet(for field: Field) -> some View {
        switch field {
        case .shelf:
            ShelfPickerSheet(garment: garment)
        case .type:
            WKChipSheet(
                title: "Cambiar tipo",
                subtitle: "Selecciona el tipo que mejor describe esta prenda",
                options: GarmentVocabulary.types(for: garment.kind).map {
                    .init(id: $0, label: $0)
                } + [.init(id: "", label: "Sin definir")],
                selection: Binding(
                    get: { Set([garment.subcategory?.capitalized].compactMap { $0 }) },
                    set: { garment.subcategory = $0.first?.isEmpty == false ? $0.first : nil }
                ),
                limit: 1
            )
        case .tags:
            WKChipSheet(
                title: "Seleccionar etiquetas",
                subtitle: "Selecciona hasta \(GarmentVocabulary.maximumTags) etiquetas",
                options: GarmentVocabulary.tags.map { .init(id: $0, label: $0) },
                selection: Binding(
                    get: { Set(garment.tags) },
                    set: { garment.tags = Array($0) }
                ),
                limit: GarmentVocabulary.maximumTags
            )
        case .cut:
            WKChipSheet(
                title: GarmentVocabulary.cutTitle(for: garment.kind) ?? "Corte",
                subtitle: "Elige uno o escribe el tuyo",
                options: GarmentVocabulary.cuts(for: garment.kind).map { .init(id: $0, label: $0) },
                selection: Binding(
                    get: { Set([garment.cut].compactMap { $0 }) },
                    set: { garment.cut = $0.first }
                ),
                limit: 1,
                allowsCustom: true
            )
        case .material:
            WKChipSheet(
                title: "Material",
                subtitle: "De qué está hecha, tal y como la llevas",
                options: GarmentVocabulary.materials.map { .init(id: $0, label: $0) }
                    + [.init(id: "", label: "Sin definir")],
                selection: Binding(
                    get: { Set([garment.material?.capitalized].compactMap { $0 }) },
                    set: { garment.material = $0.first?.isEmpty == false ? $0.first : nil }
                ),
                limit: 1
            )
        case .warmth:
            WKChipSheet(
                title: "Cambiar calidez",
                subtitle: "Selecciona qué tan abrigada es la prenda",
                options: GarmentVocabulary.Warmth.allCases.map {
                    .init(id: $0.rawValue, label: $0.label)
                },
                selection: Binding(
                    get: { [GarmentVocabulary.Warmth.from(garment.seasons).rawValue] },
                    set: { set in
                        guard
                            let raw = set.first,
                            let warmth = GarmentVocabulary.Warmth(rawValue: raw)
                        else { return }
                        garment.seasons = warmth.seasons
                    }
                ),
                limit: 1
            )
        }
    }

    /// La imagen, al final del todo.
    ///
    /// Abajo y no arriba a propósito: cambiar la foto de una prenda que ya está
    /// en el armario es lo que menos se hace de todo lo que hay en esta hoja.
    /// Pero cuando hace falta, hace mucha falta — la reconstrucción puede salir
    /// mal, y hasta ahora la única salida era borrar la prenda y volver a
    /// importarla, perdiendo el nombre, la balda y todo lo demás.
    @ViewBuilder
    private var imageSection: some View {
        WKSection("Imagen") {
            // Todas las que tiene esta prenda, para elegir cuál se ve.
            WKRow {
                GarmentImageStrip(
                    garment: garment,
                    hasCatalog: hasCatalog,
                    store: appEnvironment.imageStore,
                    onUseCrop: { Task { await dropCatalog() } },
                    onUseRaw: { Task { await promoteRawCrop() } }
                )
            }

            if cropSource != nil {
                WKRow(action: { isCroppingByHand = true }) {
                    ImageActionRow(
                        title: "Recortar a mano",
                        detail: "Rodea la prenda con el dedo y manda sobre lo detectado",
                        symbol: "lasso",
                        isWorking: false
                    )
                }
            }

            WKRow(action: { isPickingPhoto = true }) {
                ImageActionRow(
                    title: "Cambiar la foto",
                    detail: "Se vuelve a recortar y a medir el color",
                    symbol: "photo.on.rectangle",
                    isWorking: isWorkingOnImage
                )
            }

            if appEnvironment.resolver != nil {
                WKRow(
                    showsSeparator: hasCatalog,
                    action: { Task { await regenerateCatalog() } }
                ) {
                    ImageActionRow(
                        title: "Volver a generar el catálogo",
                        detail: "Otra reconstrucción de la misma foto",
                        symbol: "wand.and.sparkles",
                        isWorking: isWorkingOnImage
                    )
                }
            }

            // Solo si hay catálogo: ofrecer "usa el recorte" cuando el recorte
            // ya es lo que se está viendo no dice nada.
            if hasCatalog {
                WKRow(showsSeparator: false, action: { Task { await dropCatalog() } }) {
                    ImageActionRow(
                        title: "Usar el recorte real",
                        detail: "Tira la reconstrucción y deja la foto recortada",
                        symbol: "arrow.uturn.backward",
                        isWorking: false
                    )
                }
            }
        }
        .disabled(isWorkingOnImage)
    }

    /// Cambia la foto de base **conservando la prenda**.
    ///
    /// La prenda no se recrea: mantiene su id, su nombre, su balda, sus
    /// etiquetas y su sitio en los outfits donde ya esté puesta. Lo único que
    /// cambia es de dónde sale su imagen — y con ella el color, que se vuelve a
    /// medir porque medirlo sobre la foto vieja sería quedarse con el dato de
    /// una imagen que ya no existe.
    private func replacePhoto() async {
        guard let photoItem else { return }
        defer { self.photoItem = nil }
        isWorkingOnImage = true
        defer { isWorkingOnImage = false }

        guard
            let data = try? await photoItem.loadTransferable(type: Data.self),
            let image = UprightImage.cgImage(from: data)
        else { return }

        let pipeline = GarmentPipeline(
            segmenter: appEnvironment.segmenter,
            embedder: appEnvironment.embedder,
            promptBank: appEnvironment.promptBank,
            resolver: appEnvironment.resolver,
            // Una foto, una prenda: aquí se está cambiando **esta**, no
            // buscando cuántas hay.
            splitsInstances: false
        )
        guard
            let detected = try? await pipeline.extractGarments(from: image),
            let best = detected.max(by: { $0.confidence < $1.confidence }),
            let key = try? await appEnvironment.imageStore.store(best.normalized.cgImage)
        else {
            DiagnosticsLog.record("PRENDA", "la foto nueva no dio ningún recorte", isProblem: true)
            return
        }

        garment.normalizedImageKey = key
        garment.rawCropImageKey = try? await appEnvironment.imageStore.store(best.rawCrop.cgImage)
        if !best.colors.isEmpty { garment.colors = best.colors }

        // Y su versión de catálogo, porque la anterior era de la foto vieja.
        hasCatalog = await GarmentCatalog.regenerate(
            for: key,
            store: appEnvironment.imageStore,
            resolver: appEnvironment.resolver
        )
    }

    private func regenerateCatalog() async {
        isWorkingOnImage = true
        defer { isWorkingOnImage = false }
        let done = await GarmentCatalog.regenerate(
            for: garment.normalizedImageKey,
            store: appEnvironment.imageStore,
            resolver: appEnvironment.resolver
        )
        if done { hasCatalog = true }
    }

    /// El recorte a mano pasa a ser la imagen de la prenda.
    ///
    /// Y se tira la de catálogo: la que hubiera venía del recorte viejo, que es
    /// justo el que no valía. Se puede volver a generar desde aquí mismo.
    private func applyManualCrop(_ image: CGImage) async {
        isWorkingOnImage = true
        defer { isWorkingOnImage = false }
        guard let key = try? await appEnvironment.imageStore.store(image) else { return }
        try? await appEnvironment.imageStore.deleteCatalog(for: garment.normalizedImageKey)
        garment.normalizedImageKey = key
        hasCatalog = false
    }

    /// Asciende el recorte crudo a imagen principal.
    private func promoteRawCrop() async {
        guard let raw = garment.rawCropImageKey, raw != garment.normalizedImageKey else { return }
        garment.normalizedImageKey = raw
        hasCatalog = await appEnvironment.imageStore.hasCatalog(for: raw)
    }

    private func dropCatalog() async {
        try? await appEnvironment.imageStore.deleteCatalog(for: garment.normalizedImageKey)
        hasCatalog = false
    }

    private func enhance() async {
        isEnhancing = true
        defer { isEnhancing = false }

        // Se reprocesa el recorte guardado, no la foto original: la foto puede
        // haberse borrado de la galería, y el recorte siempre está.
        guard
            let key = garment.rawCropImageKey ?? Optional(garment.normalizedImageKey),
            let image = try? await appEnvironment.imageStore.image(for: key, variant: .display)
        else { return }

        let pipeline = GarmentPipeline(
            segmenter: appEnvironment.segmenter,
            embedder: appEnvironment.embedder,
            promptBank: appEnvironment.promptBank
        )
        guard
            let detected = try? await pipeline.extractGarments(from: image),
            let best = detected.max(by: { $0.confidence < $1.confidence })
        else { return }

        // Lo que el usuario haya puesto a mano no se pisa: mejorar rellena
        // huecos, no sobrescribe decisiones.
        if garment.subcategory == nil { garment.subcategory = best.subcategory }
        if garment.material == nil { garment.material = best.material }
        if garment.tags.isEmpty { garment.tags = best.tags }
        if garment.colors.isEmpty { garment.colors = best.colors }
        if let embedding = best.featurePrint { garment.embedding = embedding }

        if let key = try? await appEnvironment.imageStore.store(best.normalized.cgImage) {
            garment.normalizedImageKey = key
        }
        garment.needsReview = false
    }
}

/// Todas las imágenes que tiene esta prenda, en fila.
///
/// ## Por qué enseñarlas todas
///
/// Una prenda acumula hasta tres: el recorte tal cual salió de la máscara, el
/// recorte ya encajado, y la reconstrucción de catálogo. Normalmente se ve la
/// última y las otras dos son invisibles — hasta que la reconstrucción sale
/// mal, y entonces no hay forma de saber que las otras existen ni de volver a
/// ellas. Aquí están las tres, y tocar una la pone como la que se ve.
private struct GarmentImageStrip: View {
    let garment: Garment
    let hasCatalog: Bool
    let store: ImageStore
    let onUseCrop: () -> Void
    let onUseRaw: () -> Void

    private var hasRaw: Bool {
        guard let raw = garment.rawCropImageKey else { return false }
        return raw != garment.normalizedImageKey
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.m) {
                if hasCatalog {
                    ImageChoice(
                        title: "Catálogo",
                        isCurrent: true,
                        key: garment.normalizedImageKey,
                        prefersCatalog: true,
                        store: store,
                        action: {}
                    )
                }

                ImageChoice(
                    title: "Recorte",
                    isCurrent: !hasCatalog,
                    key: garment.normalizedImageKey,
                    prefersCatalog: false,
                    store: store,
                    action: onUseCrop
                )

                if hasRaw, let raw = garment.rawCropImageKey {
                    ImageChoice(
                        title: "Sin encajar",
                        isCurrent: false,
                        key: raw,
                        prefersCatalog: false,
                        store: store,
                        action: onUseRaw
                    )
                }
            }
            .padding(.horizontal, WK.Spacing.cardInset)
            // Aire por dentro: el aro de la elegida se sale del cuadrado, y sin
            // esto el scroll se lo come por el canto.
            .padding(.vertical, WK.Spacing.xs)
        }
        .scrollIndicators(.hidden)
        .wkBleedingStrip(WK.Spacing.cardInset)
        .padding(.vertical, WK.Spacing.s)
    }
}

/// Una de las imágenes de la prenda.
private struct ImageChoice: View {
    let title: String
    let isCurrent: Bool
    let key: String
    let prefersCatalog: Bool
    let store: ImageStore
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: WK.Spacing.xs) {
                StoredImage(
                    key: key,
                    variant: .thumb,
                    store: store,
                    prefersCatalog: prefersCatalog
                )
                .frame(width: 66, height: 76)
                .padding(WK.Spacing.xs)
                .background {
                    RoundedRectangle(cornerRadius: WK.Radius.small, style: .continuous)
                        .fill(WK.Palette.ink(0.04))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: WK.Radius.small, style: .continuous)
                        .stroke(WK.Palette.accent, lineWidth: isCurrent ? 2 : 0)
                }

                Text(title)
                    .font(WK.Font.caption)
                    .foregroundStyle(isCurrent ? WK.Palette.primaryText : WK.Palette.secondaryText)
            }
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
        .animation(WKAnimation.selection, value: isCurrent)
    }
}

/// Fila de la sección de imagen: qué hace y qué va a pasar.
///
/// Con explicación debajo y no solo el título: "Cambiar la foto" no dice si se
/// pierde el nombre ni si hay que volver a clasificar la prenda, y sin saberlo
/// nadie toca ninguno de los tres.
private struct ImageActionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let isWorking: Bool

    var body: some View {
        HStack(spacing: WK.Spacing.m) {
            Image(systemName: symbol)
                .font(WK.Font.headline)
                .foregroundStyle(WK.Palette.secondaryText)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.primaryText)
                Text(detail)
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if isWorking {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WK.Palette.tertiaryText)
            }
        }
        .padding(.vertical, WK.Spacing.s)
    }
}
