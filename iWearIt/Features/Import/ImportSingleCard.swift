import CoreGraphics
import SwiftUI
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
    /// **Ya no se genera nada al aparecer.**
    ///
    /// Se queda el parámetro y su documentación por si vuelve la generación
    /// automática, pero hoy no lo mira nadie: redibujar la prenda es un botón,
    /// porque cada una es una petición que se paga y mirar una ficha no es
    /// pedir nada.
    var generatesCatalog: Bool = true
    var onToggleKeep: ((Bool) -> Void)?
    /// Rehacer el recorte a dedo. Lo que devuelva manda sobre lo detectado.
    var onManualCrop: ((CGImage) -> Void)?
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
    private enum Field: String, Identifiable {
        case type, material
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
        ScrollView {
            VStack(spacing: WK.Spacing.m) {
                hero
                tools
                rows

                if let duplicateOf = candidate.duplicateOf {
                    Label("Ya tienes una parecida: \(duplicateOf)", systemImage: "square.on.square")
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
        .fullScreenCover(isPresented: $isCroppingByHand) {
            // Sobre **la foto entera**, no sobre el recorte: si el recorte se
            // dejó media manga fuera, rodearlo otra vez no la devuelve.
            ManualCropScreen(image: photo) { cropped in
                onManualCrop?(cropped)
            }
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
            .overlay(alignment: .bottom) { sourcePicker }
            .overlay(alignment: .topTrailing) { discardButton }
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
            if candidate.catalogImage == nil {
                ToolButton(
                    title: candidate.isRestyling ? "mejorando…" : "mejorar",
                    symbol: "wand.and.sparkles"
                ) {
                    Task { await onRestyle() }
                }
                .disabled(candidate.isRestyling)
            }

            if onManualCrop != nil {
                ToolButton(title: "recortar", symbol: "lasso") { isCroppingByHand = true }
            }
        }
        .animation(WKAnimation.content, value: candidate.isRestyling)
    }

    // MARK: Los datos

    /// Las mismas filas que en editar, con lo que aquí se puede corregir.
    private var rows: some View {
        VStack(spacing: 0) {
            // **Sin nombre.** Nombrar una prenda antes de tenerla es un campo
            // que hay que rellenar para nada: lo que la distingue en la balda
            // es la foto, y debajo ya se lee qué es y de qué color. El armario
            // sigue componiendo un nombre con eso —hace falta para buscar—,
            // pero no se pide aquí.
            //
            // NameRow(name: nameBinding)
            ColorRow(color: candidate.colors.first, name: colorBinding)
            // **Solo la prenda.** Antes había encima una fila "Parte: Top",
            // que es la organización interna asomando: nadie tiene un top en
            // el armario, tiene una camisa. Se elige la prenda y la parte del
            // cuerpo —la que decide la balda— se deduce de ella.
            EditRow(
                value: candidate.subcategory?.capitalized ?? "Sin definir",
                label: "Tipo de prenda"
            ) { field = .type }
            EditRow(
                value: candidate.material?.capitalized ?? "Sin definir",
                label: "Material",
                showsSeparator: false
            ) { field = .material }
        }
    }

    // MARK: Hojas y enlaces

    @ViewBuilder
    private func sheet(for field: Field) -> some View {
        switch field {
        case .type:
            // **Todas las prendas, no solo las de su parte.** Si el detector
            // se equivocó de parte —una chaqueta leída como camiseta—, con la
            // lista filtrada por esa parte no había forma de arreglarlo desde
            // aquí: la prenda correcta no aparecía. Eligiendo la prenda se
            // corrige también la parte, que es lo que se quería corregir.
            WKChipSheet(
                title: "Qué prenda es",
                subtitle: "Manga larga, corta, vaqueros… lo que la distingue",
                options: GarmentVocabulary.allTypes.map { .init(id: $0, label: $0) }
                    + [.init(id: "", label: "Sin definir")],
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
