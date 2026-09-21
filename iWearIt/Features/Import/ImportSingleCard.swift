import CoreGraphics
import SwiftUI
import WKCore
import WKDesign
import WKVision

/// Una prenda detectada, a tamaño de ficha.
///
/// ## Por qué no una lista dentro de un scroll
///
/// La versión anterior apilaba paneles —imagen, selector, nombre, botones,
/// datos, tipo, casilla— dentro de un scroll largo: la prenda quedaba arriba
/// del todo y lo que había que decidir, abajo, de forma que nunca se veían las
/// dos cosas a la vez. Y editar algo obligaba a recorrer la pantalla buscando
/// en qué panel estaba.
///
/// Aquí no hay scroll. La prenda ocupa **lo que sobre**, debajo van su nombre y
/// cuatro fichas con lo que se puede corregir —tipo, prenda, color, material—
/// y las herramientas viven en la barra de abajo. Todo lo que hay que mirar y
/// todo lo que se puede tocar, en la misma pantalla.
struct ImportSingleCard: View {
    let candidate: ImportCandidate
    /// La foto tal cual entró, para poder comparar.
    let photo: CGImage
    /// Si esta prenda entra al armario al guardar.
    ///
    /// Solo significa algo cuando la foto trajo **varias**: con una sola no hay
    /// nada que elegir —o la guardas o cancelas— y por eso el control de
    /// quitarla no se dibuja si nadie pasa `onToggleKeep`.
    var isKept: Bool = true
    let onChangeKind: (GarmentKind) -> Void
    let onChangeName: (String) -> Void
    let onChangeColor: (String) -> Void
    /// El tipo fino: "Camisa", "Vaqueros", "Botines".
    var onChangeSubcategory: ((String?) -> Void)?
    var onChangeMaterial: ((String?) -> Void)?
    /// Si esta ficha puede pedir su versión de catálogo al aparecer.
    ///
    /// Apagado en las fichas que no estás mirando: cada reconstrucción es una
    /// petición facturable, y el pager mantiene vivas las de al lado.
    var generatesCatalog: Bool = true
    var onToggleKeep: ((Bool) -> Void)?
    /// Rehacer el recorte a dedo. Lo que devuelva manda sobre lo detectado.
    var onManualCrop: ((CGImage) -> Void)?
    /// Vuelve a pedir la versión de catálogo. Se genera sola al detectar; esto
    /// es para reintentarlo si falló.
    let onRestyle: () async -> Void
    /// Vuelve a cortar la prenda del fondo con lo que ya hay en el teléfono.
    let onImprove: () -> Void

    /// Qué imagen se está mirando. Vive aquí porque es estado de presentación:
    /// cambiarla no toca la prenda.
    @State private var source: Source = .cutout
    @State private var isCroppingByHand = false
    @State private var field: Field?
    @FocusState private var editing: Focus?

    private enum Focus: Hashable { case name, color }

    private enum Field: String, Identifiable {
        case kind, type, material
        var id: String { rawValue }
    }

    private enum Source: String, CaseIterable, Identifiable {
        // `catalog` se queda fuera mientras la generación con IA está
        // apagada: una pestaña que solo sabe decir "esto no existe" es peor
        // que no tenerla. Ver `ImportModel.confirmDetection`.
        case cutout, photo
        var id: String { rawValue }

        var label: String {
            switch self {
            case .cutout: "Recorte"
            case .photo: "Foto"
            }
        }
    }

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            hero
            name
            chips

            if let duplicateOf = candidate.duplicateOf {
                Label("Ya tienes una parecida: \(duplicateOf)", systemImage: "square.on.square")
                    .font(WK.Font.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.top, WK.Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WK.Palette.canvas)
        // Las herramientas, en la barra. Apartan el contenido lo que miden y
        // dejan la ficha pasar por debajo, sin reservar hueco a mano.
        .adaptiveSafeAreaBar(edge: .bottom) { tools }
        .fullScreenCover(isPresented: $isCroppingByHand) {
            // Sobre **la foto entera**, no sobre el recorte: si el recorte se
            // dejó media manga fuera, rodearlo otra vez no la devuelve.
            ManualCropScreen(image: photo) { cropped in
                onManualCrop?(cropped)
            }
        }
        .sheet(item: $field) { sheet(for: $0) }
        .task(id: generatesCatalog) {
            guard
                generatesCatalog,
                isKept,
                candidate.catalogImage == nil,
                candidate.catalogFailure == nil,
                !candidate.isRestyling
            else { return }
            await onRestyle()
        }
    }

    // MARK: La prenda

    /// La prenda, ocupando lo que sobre, con sus dos controles encima.
    ///
    /// El de cambiar a la foto va **sobre la imagen** y no en una fila aparte:
    /// es una forma de mirar lo mismo, no otro dato de la prenda.
    private var hero: some View {
        image
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                WK.Palette.shelf,
                in: .rect(cornerRadius: WK.Radius.card, style: .continuous)
            )
            .overlay(alignment: .bottom) { sourcePicker }
            .overlay(alignment: .topTrailing) { discardButton }
    }

    @ViewBuilder
    private var image: some View {
        switch source {
        case .cutout:
            candidate.image
                .resizable()
                .scaledToFit()
                .padding(WK.Spacing.m)
                // La misma sombra de contorno que en la balda: es como se va a
                // ver a partir de ahora, y verla aquí igual evita la sorpresa.
                .shadow(color: WK.Palette.ink(0.18), radius: 10, y: 6)
                .transition(.opacity)
        case .photo:
            Image(decorative: photo, scale: 1)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: WK.Radius.card, style: .continuous))
                .transition(.opacity)
        }
    }

    /// Recorte o foto. El recorte es lo que se guarda; la foto es contra lo que
    /// se comprueba, porque un recorte solo siempre parece correcto.
    private var sourcePicker: some View {
        HStack(spacing: 2) {
            ForEach(Source.allCases) { option in
                Button {
                    withAnimation(WKAnimation.selection) { source = option }
                } label: {
                    Text(option.label)
                        .font(WK.Font.caption)
                        .foregroundStyle(
                            source == option ? WK.Palette.primaryText : WK.Palette.secondaryText
                        )
                        .padding(.horizontal, WK.Spacing.s)
                        .padding(.vertical, 6)
                        .background {
                            if source == option {
                                Capsule().fill(WK.Palette.canvas)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(WK.Palette.ink(0.06)))
        .padding(.bottom, WK.Spacing.s)
    }

    /// Quitar esta prenda del lote, o devolverla.
    ///
    /// Una X sobre la prenda, no una píldora que dice "Se va a guardar": lo que
    /// se va a guardar ya se está mirando, y una etiqueta repitiéndolo era una
    /// línea más entre la prenda y lo que sí hay que decidir.
    @ViewBuilder
    private var discardButton: some View {
        if let onToggleKeep {
            Button {
                withAnimation(WKAnimation.selection) { onToggleKeep(!isKept) }
            } label: {
                Image(systemName: isKept ? "xmark" : "arrow.uturn.backward")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.primaryText)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(WK.Palette.canvas.opacity(0.9)))
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())
            .padding(WK.Spacing.s)
            .opacity(isKept ? 1 : 0.6)
        }
    }

    // MARK: Lo editable

    /// **El nombre, escribible.** Se construye con el color, y el color se
    /// mide: una zapatilla azul marino se mide como negra más veces de las que
    /// parece. Enseñarlo sin poder tocarlo obliga a guardar algo que ya sabes
    /// que está mal y arreglarlo después.
    private var name: some View {
        TextField("Nombre", text: nameBinding)
            .font(WK.Font.title)
            .foregroundStyle(WK.Palette.primaryText)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.sentences)
            .focused($editing, equals: .name)
            .submitLabel(.done)
    }

    /// Tipo, prenda, color y material: lo que se corrige antes de guardar.
    ///
    /// En fichas y no en filas de formulario porque son cuatro palabras, no
    /// cuatro párrafos: puestas en fila caben en dos líneas y se leen de un
    /// vistazo, y cada una abre lo suyo al tocarla.
    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.xs) {
                FieldChip(
                    title: "Tipo",
                    value: ImportCandidateLabels.label(for: candidate.kind)
                ) { field = .kind }

                FieldChip(
                    title: "Prenda",
                    value: candidate.subcategory?.capitalized ?? "Sin definir"
                ) { field = .type }

                colorChip

                FieldChip(
                    title: "Material",
                    value: candidate.material?.capitalized ?? "Sin definir"
                ) { field = .material }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    /// El color se escribe en vez de elegirse de una lista: los nombres salen
    /// de una tabla de ciento y pico y ninguna lista corta acierta con "verde
    /// oliva" o "teja".
    private var colorChip: some View {
        HStack(spacing: WK.Spacing.xs) {
            if let color = candidate.colors.first {
                Circle()
                    .fill(Color(red: color.red, green: color.green, blue: color.blue))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(WK.Palette.ink(0.15), lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Color")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                TextField("Color", text: colorBinding)
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.primaryText)
                    .focused($editing, equals: .color)
                    .submitLabel(.done)
                    .frame(width: 92)
            }
        }
        .padding(.horizontal, WK.Spacing.s)
        .padding(.vertical, 6)
        .background(WK.Palette.ink(0.05), in: .capsule)
    }

    // MARK: Herramientas

    /// Lo que se le puede hacer al recorte, abajo y junto.
    private var tools: some View {
        HStack(spacing: WK.Spacing.s) {
            // **Mejorar, en el teléfono.** Donde estaba "redibujar con IA":
            // hace el mismo trabajo —volver a cortar la prenda del fondo— con
            // lo que ya hay aquí. Ver `ImportModel.improve`.
            ToolButton(title: "Mejorar", symbol: "wand.and.sparkles", action: onImprove)

            if onManualCrop != nil {
                ToolButton(title: "Recortar", symbol: "lasso") { isCroppingByHand = true }
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.xs)
    }

    // MARK: Hojas y enlaces

    @ViewBuilder
    private func sheet(for field: Field) -> some View {
        switch field {
        case .kind:
            WKChipSheet(
                title: "Tipo de prenda",
                subtitle: "Decide en qué balda acaba",
                options: GarmentKind.allCases.map {
                    .init(id: $0.rawValue, label: ImportCandidateLabels.label(for: $0))
                },
                selection: Binding(
                    get: { [candidate.kind.rawValue] },
                    set: { set in
                        guard let raw = set.first, let kind = GarmentKind(rawValue: raw) else { return }
                        onChangeKind(kind)
                    }
                ),
                limit: 1
            )
        case .type:
            WKChipSheet(
                title: "Qué prenda es",
                subtitle: "Manga larga, corta, vaqueros… lo que la distingue",
                options: GarmentVocabulary.types(for: candidate.kind).map {
                    .init(id: $0, label: $0)
                } + [.init(id: "", label: "Sin definir")],
                selection: Binding(
                    get: { Set([candidate.subcategory?.capitalized].compactMap { $0 }) },
                    set: { onChangeSubcategory?($0.first?.isEmpty == false ? $0.first : nil) }
                ),
                limit: 1
            )
        case .material:
            WKChipSheet(
                title: "Material",
                subtitle: "De qué está hecha, tal y como la llevas",
                options: GarmentVocabulary.materials.map { .init(id: $0, label: $0) }
                    + [.init(id: "", label: "Sin definir")],
                selection: Binding(
                    get: { Set([candidate.material?.capitalized].compactMap { $0 }) },
                    set: { onChangeMaterial?($0.first?.isEmpty == false ? $0.first : nil) }
                ),
                limit: 1
            )
        }
    }

    /// El nombre con el que se va a guardar, calculado con **la misma regla**
    /// que lo guardará. Enseñar aquí uno distinto del que acaba en la balda
    /// sería peor que no enseñar ninguno.
    private var nameBinding: Binding<String> {
        Binding(get: { candidate.displayName }, set: { onChangeName($0) })
    }

    private var colorBinding: Binding<String> {
        Binding(get: { candidate.colors.first?.nameKey ?? "" }, set: { onChangeColor($0) })
    }
}

/// Una ficha de dato: arriba qué es, abajo lo que vale.
private struct FieldChip: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                Text(value)
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, WK.Spacing.s)
            .padding(.vertical, 6)
            .background(WK.Palette.ink(0.05), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
    }
}

/// Un botón de la barra de abajo.
private struct ToolButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(WK.Font.callout)
                .foregroundStyle(WK.Palette.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, WK.Spacing.s)
                .background(WK.Palette.ink(0.05), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
    }
}
