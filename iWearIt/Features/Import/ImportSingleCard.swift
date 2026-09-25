import CoreGraphics
import SwiftData
import SwiftUI
import WKPersistence
import WKCore
import WKDesign
import WKVision

/// Una prenda detectada, a tamaño de ficha.
///
/// ## Es la pantalla de editar
///
/// Literalmente: la prenda grande arriba, el botón de mejorar debajo y las
/// mismas filas —nombre, color, tipo, material— con el valor grande y la
/// etiqueta pequeña, tocando cada una para cambiarla. Ver `GarmentFieldRows`,
/// que es de donde salen las filas de las dos.
///
/// Tenía que ser así: revisar una prenda recién importada y editar una que ya
/// está en el armario son el mismo trabajo sobre los mismos campos. Que una
/// tuviera píldoras y la otra chevrones solo significaba que había que
/// aprenderse dos pantallas para hacer lo mismo.
///
/// Lo único que añade esta es lo que solo existe mientras se importa: poder
/// mirar la foto original al lado del recorte, rodear la prenda a mano y
/// quitarla del lote.
struct ImportSingleCard: View {

    /// Los tipos que se ofrecen: los de su parte del cuerpo delante, el resto
    /// detrás. Escrito aquí y no en el vocabulario porque es una decisión de
    /// cómo se enseña la lista, no de qué prendas existen.
    static func typeOptions(for kind: GarmentKind) -> [WKChipSheet.Option] {
        let own = GarmentVocabulary.types(for: kind)
        let rest = GarmentVocabulary.allTypes.filter { !own.contains($0) }
        return (own + rest).map { .init(id: $0, label: $0) } + [.init(id: "", label: String(localized: "import.importsinglecard.notSet", defaultValue: "Not set"))]
    }

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
    /// El color elegido en el selector del sistema.
    var onPickColor: ((Color) -> Void)?
    var onChangeTags: (([String]) -> Void)?
    var onChangeCut: ((String?) -> Void)?
    var onChangeCategory: ((String) -> Void)?
    var onChangeSeasons: ((SeasonSet) -> Void)?
    /// El tipo fino: "Camisa", "Vaqueros", "Botines".
    var onChangeSubcategory: ((String?) -> Void)?
    var onChangeMaterial: ((String?) -> Void)?
    /// **Ya no se genera nada al aparecer.**
    ///
    /// Se queda el parámetro y su documentación por si vuelve la generación
    /// automática, pero hoy no lo mira nadie: redibujar la prenda es un botón,
    /// porque cada una es una petición que se paga y mirar una ficha no es
    /// pedir nada.
    var generatesCatalog: Bool = true
    var onToggleKeep: ((Bool) -> Void)?
    /// Rehacer el recorte a dedo. Lo que devuelva manda sobre lo detectado.
    var onManualCrop: ((ManualCrop.Result) -> Void)?
    /// Vuelve a pedir la versión de catálogo. Se genera sola al detectar; esto
    /// es para reintentarlo si falló.
    let onRestyle: () async -> Void
    /// Vuelve a cortar la prenda del fondo con lo que ya hay en el teléfono.
    ///
    /// Sin botón propio en la ficha: eso se hace en la pantalla anterior
    /// moviendo el recuadro sobre la foto, que es donde se ve qué se dejó
    /// fuera. Se queda por si hace falta volver a sacarlo.
    var onImprove: (() -> Void)?

    /// Qué imagen se está mirando. Vive aquí porque es estado de presentación:
    /// cambiarla no toca la prenda.
    @State private var source: Source = .cutout
    @State private var isCroppingByHand = false
    @State private var field: Field?
    /// Las baldas del armario, las propias incluidas, para elegir a cuál va.
    @Query(FetchDescriptor<GarmentCategory>.visibleCategories()) private var categories: [GarmentCategory]
    private enum Field: String, Identifiable {
        case part, shelf, type, cut, tags, warmth, material
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
            case .cutout: String(localized: "import.importsinglecard.cutout", defaultValue: "Cutout")
            case .photo: String(localized: "common.photo", defaultValue: "Photo")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WK.Spacing.m) {
                hero
                tools
                rows

                if let duplicateOf = candidate.duplicateOf {
                    Label(String(localized: "import.importsinglecard.youAlreadyHaveASimilar", defaultValue: "You already have a similar one: \(String(describing: duplicateOf))"), systemImage: "square.on.square")
                        .font(WK.Font.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.top, WK.Spacing.m)
            .padding(.bottom, WK.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas)
        // **Hoja, no `fullScreenCover`.** La cubierta a pantalla completa
        // presentada desde dentro de otra hoja dejaba la de debajo en negro al
        // cerrarse, y encima es un elemento que aquí no se usa. Con la hoja, el
        // cierre por arrastre se desactiva: a mitad de un recorte, un desliz
        // sin querer tira el trabajo.
        .sheet(isPresented: $isCroppingByHand) {
            // Sobre **la foto entera**, no sobre el recorte: si el recorte se
            // dejó media manga fuera, rodearlo otra vez no la devuelve.
            ManualCropScreen(image: photo) { cropped in
                onManualCrop?(cropped)
            }
            .interactiveDismissDisabled()
        }
        .sheet(item: $field) { sheet(for: $0) }
    }

    // MARK: La prenda

    /// La prenda, del mismo alto que en editar, con sus dos controles encima.
    ///
    /// El de cambiar a la foto va **sobre la imagen** y no en una fila: es una
    /// forma de mirar lo mismo, no otro dato de la prenda.
    private var hero: some View {
        image
            .frame(height: 230)
            .frame(maxWidth: .infinity)
            // Sin conmutador Recorte/Foto: se mira la prenda, que es lo que se
            // guarda. Se queda comentado.
            // .overlay(alignment: .bottom) { sourcePicker }
            // Sin X sobre la prenda: marcarla o no se decide con la casilla
            // de su tarjeta. Se queda comentado.
            // .overlay(alignment: .topTrailing) { discardButton }
    }

    @ViewBuilder
    private var image: some View {
        switch source {
        case .cutout:
            candidate.previewImage
                .resizable()
                .scaledToFit()
                // La misma sombra de contorno que en la balda y en editar: es
                // como se va a ver a partir de ahora.
                .shadow(color: WK.Palette.ink(0.5), radius: 18, y: 11)
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
                    .background(Circle().fill(WK.Palette.ink(0.07)))
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())
            .opacity(isKept ? 1 : 0.6)
        }
    }

    // MARK: Herramientas

    /// Lo que se le puede hacer al recorte, donde en editar está "mejorar".
    private var tools: some View {
        HStack(spacing: WK.Spacing.s) {
            // **Mejorar es redibujar la prenda fuera.** Se pide a mano, nunca
            // sola: cada una cuesta una petición, y lanzarla por el hecho de
            // mirar una ficha era pagar por prendas que estaban bien.
            //
            // Sale del teléfono únicamente el recorte normalizado.
            // Sin "mejorar" en lo rodeado a mano. Ver `isFromManualCrop`.
            if candidate.canRestyle {
                // Se llena mientras dura. Ver `WKProgressPill`.
                WKProgressPill(
                    candidate.isRestyling ? "mejorando…" : "mejorar",
                    symbol: "wand.and.sparkles",
                    isWorking: candidate.isRestyling
                ) {
                    Task { await onRestyle() }
                }
            }

            // **Y rodear a mano**, que es lo que queda cuando el recorte se
            // dejó media manga fuera: tu trazo manda sobre lo detectado y
            // entra al momento. Ver `ImportModel.addManualCandidate`.
            if onManualCrop != nil {
                ToolButton(title: "rodear", symbol: "lasso") { isCroppingByHand = true }
            }
        }
        .animation(WKAnimation.content, value: candidate.isRestyling)
    }

    // MARK: Los datos

    /// Las mismas filas que en editar: color, parte, tipo, etiquetas y
    /// calidez. Literalmente las mismas —ver `GarmentFieldRows`—, porque
    /// revisar una prenda recién importada y editar una que ya está en el
    /// armario son el mismo trabajo sobre los mismos campos.
    private var rows: some View {
        VStack(spacing: 0) {
            // El nombre, **siempre editable**: se propone solo, pero lo que
            // escribas manda y ya no se regenera.
            NameRow(name: nameBinding)
            ColorRow(color: candidate.colors.first, picked: colorBinding)
            // **Qué es, no dónde va.** "Parte superior" es un filtro para
            // buscar, no algo que se elija: se elige camiseta o pantalón, y la
            // parte del cuerpo sale de ahí.
            // **La balda, elegible.** Sale sola —por lo que es, o por la
            // balda propia que mejor le cuadre— pero se puede cambiar aquí
            // mismo, y la elegida manda: no se vuelve a mover sola.
            EditRow(value: shelfName, label: String(localized: "common.shelf", defaultValue: "Shelf")) { field = .shelf }
            // Qué es dentro de su balda: chino o vaquero, no "pantalones".
            EditRow(
                value: candidate.subcategory?.capitalized ?? String(localized: "import.importsinglecard.notSet", defaultValue: "Not set"),
                label: String(localized: "common.type", defaultValue: "Type")
            ) { field = .type }
            EditRow(
                value: candidate.material?.capitalized ?? String(localized: "import.importsinglecard.notSet", defaultValue: "Not set"),
                label: String(localized: "common.material", defaultValue: "Material")
            ) { field = .material }
            EditRow(
                value: GarmentVocabulary.Warmth.label(for: candidate.seasons),
                label: String(localized: "common.warmth", defaultValue: "Warmth")
            ) { field = .warmth }
            // **Sin estilo.** "Casual · Edgy" se adivinaba y no servía para
            // nada que se haga en la app. Se queda comentado.
            // EditRow(
            //     value: candidate.tags.isEmpty ? "Sin etiquetas" : candidate.tags.joined(separator: " · "),
            //     label: "Etiquetas"
            // ) { field = .tags }

            // La manga o el largo, como etiquetas a la vista.
            CutChipsRow(kind: candidate.kind, selection: candidate.cut) { onChangeCut?($0) }
            // Etiquetas de uso: Deporte, Trabajo… Ver `TagChipsRow`.
            TagChipsRow(selection: candidate.tags) { onChangeTags?($0) }
        }
    }

    // MARK: Hojas y enlaces

    @ViewBuilder
    private func sheet(for field: Field) -> some View {
        switch field {
        case .part:
            WKChipSheet(
                title: String(localized: "import.importsinglecard.bodyPart", defaultValue: "Body part"),
                subtitle: String(localized: "import.importsinglecard.decidesWhichShelfItEnds", defaultValue: "Decides which shelf it ends up on"),
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
        case .shelf:
            WKChipSheet(
                title: String(localized: "common.shelf", defaultValue: "Shelf"),
                subtitle: String(localized: "import.importsinglecard.whereYouLlHangIt", defaultValue: "Where you'll hang it"),
                options: categories.map { .init(id: $0.slug, label: $0.displayName) },
                selection: Binding(
                    get: { [shelfSlug] },
                    set: { set in
                        guard let slug = set.first else { return }
                        onChangeCategory?(slug)
                        // La balda dice qué parte es: "Pantalones" es de abajo,
                        // y con eso los tipos y el largo que se ofrecen son
                        // los de un pantalón.
                        if let kind = categories.first(where: { $0.slug == slug })?.defaultKind,
                           kind != candidate.kind {
                            onChangeKind(kind)
                        }
                    }
                ),
                limit: 1
            )
        case .cut:
            WKChipSheet(
                title: GarmentVocabulary.cutTitle(for: candidate.kind) ?? String(localized: "import.importsinglecard.cut", defaultValue: "Cut"),
                subtitle: String(localized: "import.importsinglecard.pickOneOrWriteYour", defaultValue: "Pick one or write your own"),
                options: GarmentVocabulary.cuts(for: candidate.kind).map { .init(id: $0, label: $0) },
                selection: Binding(
                    get: { Set([candidate.cut].compactMap { $0 }) },
                    set: { onChangeCut?($0.first) }
                ),
                limit: 1,
                allowsCustom: true
            )
        case .tags:
            WKChipSheet(
                title: String(localized: "import.importsinglecard.chooseTags", defaultValue: "Choose tags"),
                subtitle: String(localized: "import.importsinglecard.chooseUpToTags", defaultValue: "Choose up to \(String(describing: GarmentVocabulary.maximumTags)) tags"),
                options: GarmentVocabulary.tags.map { .init(id: $0, label: $0) },
                selection: Binding(
                    get: { Set(candidate.tags) },
                    set: { onChangeTags?(Array($0)) }
                ),
                limit: GarmentVocabulary.maximumTags
            )
        case .warmth:
            WKChipSheet(
                title: String(localized: "import.importsinglecard.changeWarmth", defaultValue: "Change warmth"),
                // Se puede **quitar**: hay prendas que valen para todo el año.
                subtitle: String(localized: "import.importsinglecard.removeItIfItWorks", defaultValue: "Remove it if it works all year round"),
                options: GarmentVocabulary.Warmth.allCases.map {
                    .init(id: $0.rawValue, label: $0.label)
                },
                selection: Binding(
                    get: {
                        GarmentVocabulary.Warmth.from(candidate.seasons)
                            .map { [$0.rawValue] } ?? []
                    },
                    set: { set in
                        guard
                            let raw = set.first,
                            let warmth = GarmentVocabulary.Warmth(rawValue: raw)
                        else {
                            // Sin nada marcado: vale para todas.
                            onChangeSeasons?(.all)
                            return
                        }
                        onChangeSeasons?(warmth.seasons)
                    }
                ),
                limit: 1,
                allowsEmpty: true
            )
        case .type:
            // **Todas las prendas, no solo las de su parte.** Si el detector
            // se equivocó de parte —una chaqueta leída como camiseta—, con la
            // lista filtrada por esa parte no había forma de arreglarlo desde
            // aquí: la prenda correcta no aparecía. Eligiendo la prenda se
            // corrige también la parte, que es lo que se quería corregir.
            WKChipSheet(
                title: String(localized: "import.importsinglecard.whatPieceItIs", defaultValue: "What piece it is"),
                subtitle: String(localized: "import.importsinglecard.longSleeveShortSleeveJeans", defaultValue: "Long sleeve, short sleeve, jeans… whatever sets it apart"),
                // Los de su parte **primero** y el resto detrás: lo normal es
                // que lo que buscas esté arriba del todo, y cuando el detector
                // se equivocó de parte —un bañador leído como short, una
                // camiseta larga leída como vestido— la prenda correcta sigue
                // estando, un poco más abajo. Con la lista recortada no había
                // forma de arreglarlo.
                options: Self.typeOptions(for: candidate.kind),
                selection: Binding(
                    get: { Set([candidate.subcategory?.capitalized].compactMap { $0 }) },
                    set: { chosen in
                        let type = chosen.first?.isEmpty == false ? chosen.first : nil
                        onChangeSubcategory?(type)
                        // Y con ella, la parte del cuerpo: unos vaqueros van
                        // abajo aunque el detector dijera otra cosa.
                        if let type, let kind = GarmentVocabulary.kind(forType: type) {
                            onChangeKind(kind)
                        }
                    }
                ),
                limit: 1
            )
        case .material:
            WKChipSheet(
                title: String(localized: "common.material", defaultValue: "Material"),
                subtitle: String(localized: "import.importsinglecard.whatItSMadeOf", defaultValue: "What it's made of, as you wear it"),
                options: GarmentVocabulary.materials.map { .init(id: $0, label: $0) }
                    + [.init(id: "", label: String(localized: "import.importsinglecard.notSet", defaultValue: "Not set"))],
                selection: Binding(
                    get: { Set([candidate.material?.capitalized].compactMap { $0 }) },
                    set: { onChangeMaterial?($0.first?.isEmpty == false ? $0.first : nil) }
                ),
                limit: 1
            )
        }
    }

    /// La balda a la que irá: la elegida, o la que le tocaría sola.
    private var shelfSlug: String { candidate.shelfSlug }

    private var shelfName: String {
        categories.first { $0.slug == shelfSlug }?.displayName
            ?? GarmentVocabulary.shelfName(for: candidate.kind)
    }

    /// El nombre con el que se va a guardar, calculado con **la misma regla**
    /// que lo guardará. Enseñar aquí uno distinto del que acaba en la balda
    /// sería peor que no enseñar ninguno.
    private var nameBinding: Binding<String> {
        Binding(get: { candidate.displayName }, set: { onChangeName($0) })
    }

    /// El color como color, no como palabra.
    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                guard let color = candidate.colors.first else { return WK.Palette.ink(0.3) }
                return Color(red: color.red, green: color.green, blue: color.blue)
            },
            set: { onPickColor?($0) }
        )
    }
}

/// Un botón de herramienta, con la misma forma que el "mejorar" de editar.
private struct ToolButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(WK.Font.callout)
                .foregroundStyle(WK.Palette.primaryText)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .background(WK.Palette.ink(0.07), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
    }
}
