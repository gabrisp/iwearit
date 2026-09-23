import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Elegir con qué prendas se empieza el outfit.
///
/// Es una hoja y no una pantalla: se abre, se marcan cuatro cosas y se cierra.
/// El armario entero, por baldas y en horizontal, que es como está organizado
/// en el resto de la app — obligar a buscar en una rejilla plana lo que fuera
/// está por baldas hace que parezcan dos armarios distintos.
struct OutfitPickerSheet: View {
    /// Cuántas prendas caben por balda.
    enum Mode {
        /// Una por balda. Un outfit no lleva dos pantalones, y marcar otro
        /// sustituye al anterior: obligar a desmarcar antes es un toque de más
        /// en el caso habitual, que es cambiar de idea.
        case outfit
        /// Las que hagan falta. Para hacer la maleta sí se meten tres
        /// camisetas.
        case many
    }

    var mode: Mode = .outfit
    var title = "Crear outfit"
    var subtitle = "Elige las prendas con las que quieres empezar"
    let store: ImageStore
    /// Ya marcada al abrir. Viene de "crear outfit" desde una prenda concreta.
    var preselected: Garment?
    let onConfirm: ([Garment]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: [PersistentIdentifier] = []
    /// Una sola hoja: apilar `.sheet` en la misma vista deja mudos a todos
    /// menos a uno, y además la cámara seguía viva bajo el recorte.
    @State private var capture: CaptureStep?

    private enum CaptureStep: Identifiable {
        case camera
        case review(ImportableBatch)

        var id: String {
            switch self {
            case .camera: "camera"
            case let .review(image): image.id.uuidString
            }
        }
    }
    @State private var onlyMine = true

    /// La prenda que está **volando** de la balda a la píldora.
    ///
    /// Mientras vale su id, la miniatura de abajo cede su geometría a la celda
    /// de la balda: nace exactamente donde estaba la prenda. Al soltarlo, la
    /// miniatura recupera su sitio y el trayecto se anima solo. Es la única
    /// forma de que `matchedGeometryEffect` haga un vuelo sin que la celda de
    /// origen se mueva — las fuentes nunca se mueven.
    @State private var flying: PersistentIdentifier?
    @Namespace private var picking

    @Query(
        filter: #Predicate<GarmentCategory> { !$0.isHidden && $0.deletedAt == nil },
        sort: [SortDescriptor(\GarmentCategory.sortOrder)]
    )
    private var categories: [GarmentCategory]

    var body: some View {
        // **Con pila de navegación.** La cabecera de cada balda tenía chevron
        // —o sea, prometía abrirse— y no hacía nada. Ahora se abre aquí dentro,
        // que es donde estás eligiendo: salir de la hoja para ver una balda
        // entera y volver perdería lo que llevaras marcado.
        NavigationStack {
            picker
                .navigationDestination(for: PersistentIdentifier.self) { id in
                    PickerShelfScreen(
                        categoryID: id,
                        store: store,
                        mode: mode,
                        picking: picking,
                        picked: $picked,
                        flying: $flying
                    )
                }
        }
        // **La barra de abajo, por fuera de la pila.**
        //
        // Estaba puesta sobre la primera pantalla, así que al abrir una balda
        // entera se iba con ella: justo cuando más falta hace —estás mirando
        // cuarenta camisetas— desaparecían lo que llevabas elegido y el botón
        // de confirmar, y había que volver atrás para poder seguir.
        //
        // Por fuera de la `NavigationStack` pertenece a la hoja y no a una
        // pantalla suya, así que se queda puesta entres donde entres. Y sigue
        // reservando su hueco, de modo que ninguna balda queda cortada por
        // debajo.
        .adaptiveSafeAreaBar(edge: .bottom) { bottom }
    }

    private var picker: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    PickerShelf(
                        category: category,
                        store: store,
                        isEven: index.isMultiple(of: 2),
                        mode: mode,
                        picking: picking,
                        picked: $picked,
                        flying: $flying
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas.ignoresSafeArea())
        // Cabecera en barra, no como primera fila del scroll: siendo contenido
        // se iba con él, y el título y la X tienen que quedarse quietos
        // mientras recorres el armario entero.
        // **Barra del sistema, no una fila puesta a mano.**
        //
        // La de antes era contenido: se movía con el layout, se recolocaba al
        // aparecer la selección de abajo y había que reservarle hueco. En la
        // barra de verdad el título se queda quieto pase lo que pase debajo, y
        // los dos botones caen donde el sistema los pone en toda la app.
        // **En iPad, el título a la izquierda.** Centrado en una hoja ancha
        // queda flotando en medio de nada, lejos de lo que titula; el sistema
        // lo centra porque en un iPhone la barra es estrecha y ahí sí manda el
        // centro.
        .navigationTitle(isWide ? "" : title)
        .navigationBarTitleDisplayMode(.inline)
        .wkNavigationSubtitle(isWide ? "" : subtitle)
        .toolbar {
            if isWide {
                ToolbarItem(placement: .topBarLeading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(WK.Font.headline)
                            .foregroundStyle(WK.Palette.primaryText)
                        Text(subtitle)
                            .font(WK.Font.caption)
                            .foregroundStyle(WK.Palette.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { capture = .camera } label: { Image(systemName: "plus") }
                    .tint(WK.Palette.primaryText)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .tint(WK.Palette.primaryText)
            }
        }
        .sheet(item: $capture) { step in
            switch step {
            case .camera:
                CameraScreen { images in
                    capture = .review(ImportableBatch(images: images))
                }
            case let .review(batch):
                ImportSheet(images: batch.images)
            }
        }
        .task {
            guard let preselected, picked.isEmpty else { return }
            picked = [preselected.persistentModelID]
        }
    }

    // **La cabecera de antes, comentada y no borrada.** Era una fila de
    // contenido con el título, el subtítulo y los dos botones de cristal.
    // Funcionaba, pero se movía con el layout: ahora eso lo resuelve la barra
    // del sistema.
    //
    // private var header: some View {
    // HStack(alignment: .top) {
    // VStack(alignment: .leading, spacing: 2) {
    // Text(title)
    // .font(WK.Font.headline)
    // .foregroundStyle(WK.Palette.primaryText)
    // Text(subtitle)
    // .font(WK.Font.caption)
    // .foregroundStyle(WK.Palette.secondaryText)
    // }
    // Spacer()
    // // Círculos de cristal, no una cápsula opaca: la barra no lleva
    // // fondo propio y el armario sigue viéndose por debajo.
    // HStack(spacing: WK.Spacing.s) {
    // HeaderButton(symbol: "plus") { capture = .camera }
    // HeaderButton(symbol: "xmark") { dismiss() }
    // }
    // }
    // .padding(.horizontal, WK.Spacing.screenInset)
    // .padding(.top, WK.Spacing.m)
    // .padding(.bottom, WK.Spacing.s)
    // }

    /// Filtros, lo que llevas elegido y el botón de seguir.
    ///
    /// Las miniaturas no son decoración: sin ellas hay que subir y bajar toda
    /// la lista para recordar qué habías marcado, y la lista es el armario
    /// entero.
    private var bottom: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            // TODO: "Solo mis prendas", "Estilo" y "Calidez" — comentados hasta
            // que filtren de verdad y hasta pasarlos a cristal, como el resto
            // de controles flotantes. Un filtro que no filtra enseña a no tocar
            // los filtros.
            // filters
            HStack(spacing: WK.Spacing.m) {
                PickedStrip(ids: picked, store: store, picking: picking, flying: flying)
                Spacer(minLength: 0)
                Button { confirm() } label: {
                    // **Sin color propio.** El relleno es el acento —negro en
                    // claro, blanco en oscuro— y poner aquí el color de texto
                    // primario, que es exactamente el mismo, dejaba el check
                    // invisible sobre su propio botón: todo negro de día y todo
                    // blanco de noche. El color de la etiqueta lo decide
                    // `adaptiveGlassProminent`, que es quien sabe de qué color
                    // ha pintado el fondo.
                    Image(systemName: "checkmark")
                        .font(WK.Font.headline)
                        .frame(width: 56, height: 56)
                        .contentShape(.circle)
                }
                .buttonStyle(WKPressStyle())
                .adaptiveGlassProminent(tint: WK.Palette.accent, in: .circle)
                .disabled(picked.isEmpty)
                .opacity(picked.isEmpty ? 0.4 : 1)
                .animation(WKAnimation.selection, value: picked.isEmpty)
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.s)
    }

    /// Flotan sobre el contenido, sin barra propia: son un ajuste de lo que se
    /// está mirando, no un nivel más de interfaz.
    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.s) {
                FilterChip(
                    title: "Solo mis prendas",
                    symbol: onlyMine ? "checkmark.circle.fill" : "circle"
                ) {
                    withAnimation(WKAnimation.selection) { onlyMine.toggle() }
                }
                FilterChip(title: "Estilo", symbol: "chevron.up.chevron.down") {}
                FilterChip(title: "Calidez", symbol: "chevron.up.chevron.down") {}
            }
        }
        .scrollIndicators(.hidden)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// iPad —o iPhone en apaisado—: la barra es ancha.
    private var isWide: Bool { horizontalSizeClass == .regular }

    private func confirm() {
        let garments = picked.compactMap { modelContext.model(for: $0) as? Garment }
        dismiss()
        onConfirm(garments)
    }
}

/// Una balda dentro del selector.
///
/// Vista propia con su `@Query`: cada balda carga las suyas y marcar una prenda
/// de "zapatos" no reevalúa la fila de "parte inferior".
private struct PickerShelf: View {
    let category: GarmentCategory
    let store: ImageStore
    let isEven: Bool
    let mode: OutfitPickerSheet.Mode
    let picking: Namespace.ID
    @Binding var picked: [PersistentIdentifier]
    @Binding var flying: PersistentIdentifier?

    var body: some View {
        if !category.visibleGarments.isEmpty {
            // **La balda del armario, no una parecida.**
            //
            // Misma cabecera, mismo alto, mismas perchas y el mismo canto de
            // madera debajo. Antes esto tenía su propio título en minúsculas,
            // sus celdas con otras medidas y una banda gris alterna en vez del
            // tablero: el mismo armario se veía de dos maneras según por dónde
            // entraras, y la de aquí era la mala.
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink(value: category.persistentModelID) {
                    ShelfHeaderLabel(name: category.name, count: category.visibleGarments.count)
                }
                .buttonStyle(WKPressStyle())

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .bottom, spacing: WK.Spacing.m) {
                        ForEach(category.visibleGarments) { garment in
                            PickerCell(
                                garment: garment,
                                store: store,
                                picking: picking,
                                isPicked: picked.contains(garment.persistentModelID),
                                isFlying: flying == garment.persistentModelID
                            ) {
                                toggle(garment)
                            }
                        }
                    }
                    .padding(.horizontal, WK.Spacing.screenInset)
                    .frame(height: WK.Shelf.height, alignment: .bottom)
                }
                .scrollIndicators(.hidden)

                ShelfPlank()
            }
            .padding(.bottom, WK.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toggle(_ garment: Garment) {
        let id = garment.persistentModelID
        if picked.contains(id) {
            withAnimation(WKAnimation.selection) { picked.removeAll { $0 == id } }
            return
        }

        // Primero aparece cedida a la celda —o sea, encima de la prenda— y en
        // el siguiente frame recupera su sitio, que es lo que dibuja el vuelo.
        flying = id
        if mode == .outfit {
            let siblings = Set(category.visibleGarments.map(\.persistentModelID))
            picked.removeAll { siblings.contains($0) }
        }
        picked.append(id)

        Task {
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(WKAnimation.arrival) { flying = nil }
        }
    }
}

private struct PickerCell: View {
    let garment: Garment
    let store: ImageStore
    let picking: Namespace.ID
    let isPicked: Bool
    /// Esta prenda es ahora mismo el origen del vuelo hacia la píldora.
    let isFlying: Bool
    let action: () -> Void

    /// El mismo valor que usa la balda del armario: de ahí salen el nombre y
    /// el balanceo, y así los dos sitios inclinan la prenda igual.
    private var ref: GarmentRef { GarmentRef(garment) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                StoredImage(
                    key: garment.normalizedImageKey,
                    variant: .thumb,
                    store: store,
                    alignment: .bottom,
                    shadow: .init(opacity: 0.5, radius: 8, y: 5)
                )
                .frame(width: WK.Shelf.garmentWidth, height: WK.Shelf.imageHeight)
                // Colgada de la percha, igual que en el armario: el balanceo
                // es determinista a partir del id, así que la misma prenda se
                // inclina lo mismo en las dos pantallas.
                .rotationEffect(.degrees(ref.swayDegrees), anchor: .top)
                // Elegida = apagada. La prenda se ha ido abajo, a la píldora, y
                // dejarla igual de viva que las que siguen disponibles obliga a
                // buscar el check para saber cuál has cogido.
                .opacity(isPicked ? 0.3 : 1)
            // El origen del vuelo es un **proxy transparente**, y solo existe
            // durante el vuelo.
            //
            // Puesto sobre la imagen, la celda pasaba a ser *destino* del mismo
            // id en cuanto el vuelo acababa, y SwiftUI la arrastraba hasta la
            // píldora: o salía una copia fantasma pegada a cada prenda, o
            // desaparecía la miniatura de abajo. Con el proxy, en todo momento
            // hay como mucho una fuente por id y la imagen nunca se mueve.
                .overlay {
                    if isFlying {
                        Color.clear.matchedGeometryEffect(
                            id: garment.persistentModelID,
                            in: picking,
                            isSource: true
                        )
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isPicked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(WK.Palette.onAccent)
                            .frame(width: 26, height: 26)
                            .background(WK.Palette.accent, in: .circle)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                // **Sin nombre debajo**, como en el armario: la foto ya dice cuál
                // es cada prenda, y treinta nombres compuestos son treinta
                // líneas cortadas que no distinguen nada.
                //
                // Text(ref.name)
                //     .font(WK.Font.garmentName)
                //     .foregroundStyle(WK.Palette.secondaryText)
                //     .lineLimit(1)
                //     .truncationMode(.tail)
                //     .frame(width: WK.Shelf.garmentWidth)
            }
            .frame(height: WK.Shelf.height, alignment: .bottom)
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
        .animation(WKAnimation.selection, value: isPicked)
        .sensoryFeedback(.selection, trigger: isPicked)
    }
}

/// Las prendas ya marcadas, en pequeño.
private struct PickedStrip: View {
    let ids: [PersistentIdentifier]
    let store: ImageStore
    let picking: Namespace.ID
    let flying: PersistentIdentifier?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: WK.Spacing.xs) {
            ForEach(ids, id: \.self) { id in
                if let garment = modelContext.model(for: id) as? Garment {
                    StoredImage(key: garment.normalizedImageKey, variant: .thumb, store: store)
                        .frame(width: 34, height: 40)
                        .matchedGeometryEffect(id: id, in: picking, isSource: flying != id)
                }
            }
        }
        .padding(.horizontal, WK.Spacing.s)
        .padding(.vertical, WK.Spacing.s)
        .adaptiveGlass(in: .capsule)
        .opacity(ids.isEmpty ? 0 : 1)
        .animation(WKAnimation.selection, value: ids)
    }
}


/// Un botón de la cápsula de cabecera.
private struct HeaderButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(WK.Font.headline)
                .foregroundStyle(WK.Palette.primaryText)
                .frame(width: 42, height: 42)
                .contentShape(.circle)
        }
        .buttonStyle(WKPressStyle())
        .adaptiveGlassInteractive(in: .circle)
    }
}

/// Un filtro.
private struct FilterChip: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WK.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.caption)
                Text(title)
                    .font(WK.Font.captionMedium)
            }
            .foregroundStyle(WK.Palette.primaryText)
            .padding(.horizontal, WK.Spacing.m)
            .padding(.vertical, WK.Spacing.s)
            .background(WK.Palette.shelf, in: .capsule)
            .overlay(Capsule().stroke(WK.Palette.ink(0.07), lineWidth: 1))
            .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
    }
}

/// Chevron detrás del texto, como las cabeceras del armario.
private struct TrailingChevronStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WK.Palette.secondaryText)
        }
    }
}


/// Una balda entera, dentro de la hoja de elegir.
///
/// La misma celda y el mismo `picked` que la fila de fuera: lo que marques aquí
/// ya está marcado al volver, porque es literalmente la misma selección.
private struct PickerShelfScreen: View {
    let categoryID: PersistentIdentifier
    let store: ImageStore
    let mode: OutfitPickerSheet.Mode
    let picking: Namespace.ID
    @Binding var picked: [PersistentIdentifier]
    @Binding var flying: PersistentIdentifier?

    @Environment(\.modelContext) private var modelContext

    private var category: GarmentCategory? {
        modelContext.model(for: categoryID) as? GarmentCategory
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: WK.Spacing.m)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: WK.Spacing.m) {
                ForEach(category?.visibleGarments ?? []) { garment in
                    PickerCell(
                        garment: garment,
                        store: store,
                        picking: picking,
                        isPicked: picked.contains(garment.persistentModelID),
                        isFlying: flying == garment.persistentModelID
                    ) {
                        toggle(garment)
                    }
                }
            }
            .padding(WK.Spacing.screenInset)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .background(WK.Palette.canvas.ignoresSafeArea())
        .navigationTitle(category?.name ?? "Balda")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// La misma regla que en la fila de fuera: montando un outfit, marcar una
    /// prenda de esta balda sustituye a la que hubiera — un outfit no lleva dos
    /// pantalones. Haciendo la maleta se acumulan.
    private func toggle(_ garment: Garment) {
        let id = garment.persistentModelID
        withAnimation(WKAnimation.selection) {
            if picked.contains(id) {
                picked.removeAll { $0 == id }
                return
            }
            if mode == .outfit, let siblings = category?.visibleGarments {
                let ids = Set(siblings.map(\.persistentModelID))
                picked.removeAll { ids.contains($0) }
            }
            picked.append(id)
        }
    }
}
