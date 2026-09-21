import CoreGraphics
import SwiftUI
import WKCore
import WKDesign
import WKVision

/// Una prenda detectada, a tamaño de ficha.
///
/// ## Por qué no una fila de lista
///
/// Con **una** prenda, la lista es una lista de uno: una miniatura de 64
/// puntos, un selector y una casilla ya marcada. El usuario aprueba sin haber
/// mirado el recorte, y lo primero que hace después de guardar es abrir la
/// prenda para comprobar qué se guardó. La ficha enseña lo que se va a guardar
/// antes de guardarlo, que es para lo que existe la revisión.
///
/// Con varias, la lista sigue siendo lo correcto: ahí la decisión es cuáles
/// quedarse, y para eso hay que verlas juntas.
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

    /// Qué imagen se está mirando. Vive aquí porque es estado de presentación:
    /// cambiarla no toca la prenda.
    /// Se abre en la reconstruida: es la que se acaba de generar y la que
    /// enseña la prenda entera. El recorte sigue a un toque, para comparar.
    @State private var source: Source = .catalog
    @State private var isCroppingByHand = false
    @FocusState private var editing: Field?

    private enum Field: Hashable { case name, color }

    private enum Source: String, CaseIterable, Identifiable {
        case cutout, catalog, photo
        var id: String { rawValue }

        var label: String {
            switch self {
            case .cutout: "Recorte"
            case .catalog: "Catálogo"
            case .photo: "Foto"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WK.Spacing.m) {
                image
                    .frame(maxWidth: .infinity)
                    .frame(height: 340)
                    .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.card, style: .continuous))

                // **Las dos imágenes, a un toque.** El recorte es lo que se
                // guarda; la foto es contra lo que se comprueba. Sin poder ver
                // la de al lado no hay forma de saber si al recorte le falta
                // media manga: el recorte solo siempre parece correcto.
                Picker("Imagen", selection: $source) {
                    ForEach(Source.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                // Se genera sola al detectar. Esto es para reintentarlo si
                // aquella vez falló, y una sola vez: si ya está, volver a esta
                // pestaña no la vuelve a pagar.
                .onChange(of: source) { _, new in
                    guard
                        new == .catalog,
                        candidate.catalogImage == nil,
                        candidate.catalogFailure != nil
                    else { return }
                    Task { await onRestyle() }
                }

                VStack(spacing: WK.Spacing.xs) {
                    // **Editable.** El nombre se construye con el color, y el
                    // color se mide: una zapatilla azul marino se mide como
                    // negra más veces de las que parece. Enseñarlo sin poder
                    // tocarlo obliga a guardar algo que ya sabes que está mal
                    // y arreglarlo después.
                    TextField("Nombre", text: nameBinding)
                        .font(WK.Font.title)
                        .foregroundStyle(WK.Palette.primaryText)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.sentences)
                        .focused($editing, equals: .name)
                        .submitLabel(.done)

                    Text(ImportCandidateLabels.label(for: candidate.kind))
                        .font(WK.Font.caption)
                        .foregroundStyle(WK.Palette.secondaryText)
                }

                HStack(spacing: WK.Spacing.s) {
                    if let color = candidate.colors.first {
                        Circle()
                            .fill(Color(red: color.red, green: color.green, blue: color.blue))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(WK.Palette.ink(0.15), lineWidth: 1))
                    }
                    TextField("Color", text: colorBinding)
                        .font(WK.Font.callout)
                        .foregroundStyle(WK.Palette.primaryText)
                        .focused($editing, equals: .color)
                        .submitLabel(.done)
                        .frame(maxWidth: 160)
                }
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .background(WK.Palette.ink(0.05), in: .capsule)

                manualCropButton

                CandidateFactsRow(candidate: candidate)

                if let duplicateOf = candidate.duplicateOf {
                    Label("Ya tienes una parecida: \(duplicateOf)", systemImage: "square.on.square")
                        .font(WK.Font.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                // La categoría, corregible. Es el único dato que el usuario
                // cambia a menudo antes de guardar, y el único que cambia
                // dónde acaba la prenda.
                Picker("Tipo", selection: Binding(
                    get: { candidate.kind },
                    set: { onChangeKind($0) }
                )) {
                    ForEach(GarmentKind.allCases, id: \.self) { kind in
                        Text(ImportCandidateLabels.label(for: kind)).tag(kind)
                    }
                }
                .pickerStyle(.menu)

                keepButton
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas)
        // **La reconstrucción, al llegar a esta prenda.** Con una sola en la
        // foto ya viene hecha; con varias se pide aquí, que es cuando se sabe
        // que de verdad la vas a mirar.
        .fullScreenCover(isPresented: $isCroppingByHand) {
            // Sobre **la foto entera**, no sobre el recorte: si el recorte se
            // dejó media manga fuera, rodearlo otra vez no la devuelve.
            ManualCropScreen(image: photo) { cropped in
                onManualCrop?(cropped)
            }
        }
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

    /// Rodear la prenda con el dedo cuando el recorte no ha salido.
    ///
    /// No está escondido en un menú: cuando hace falta, hace mucha falta —el
    /// recorte partido es de las cosas que más se ven— y la alternativa era
    /// descartar la prenda y volver a probar con el mismo modelo esperando otro
    /// resultado.
    @ViewBuilder
    private var manualCropButton: some View {
        if onManualCrop != nil {
            Button { isCroppingByHand = true } label: {
                Label("Recortar a mano", systemImage: "lasso")
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.primaryText)
                    .padding(.horizontal, WK.Spacing.m)
                    .padding(.vertical, WK.Spacing.s)
                    .background(WK.Palette.ink(0.05), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(WKPressStyle())
        }
    }

    /// Quitar esta prenda del lote, o devolverla.
    ///
    /// Aquí y no en la miniatura de la tira: la decisión de descartar se toma
    /// **mirando la prenda**, y a 54 puntos no se ve si el recorte salió bien.
    @ViewBuilder
    private var keepButton: some View {
        if let onToggleKeep {
            Button {
                withAnimation(WKAnimation.selection) { onToggleKeep(!isKept) }
            } label: {
                Label(
                    isKept ? "Se va a guardar" : "Descartada",
                    systemImage: isKept ? "checkmark.circle.fill" : "slash.circle"
                )
                .font(WK.Font.callout)
                .foregroundStyle(isKept ? WK.Palette.accent : WK.Palette.secondaryText)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .background(WK.Palette.ink(0.05), in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(WKPressStyle())
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
        case .catalog:
            if let catalog = candidate.catalogImage {
                Image(decorative: catalog.cgImage, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: WK.Radius.card, style: .continuous))
                    .transition(.opacity)
            } else {
                VStack(spacing: WK.Spacing.s) {
                    if candidate.isRestyling {
                        ProgressView()
                        Text("Redibujando la prenda…")
                    } else {
                        Button {
                            Task { await onRestyle() }
                        } label: {
                            Label("Reintentar", systemImage: "arrow.clockwise")
                                .font(WK.Font.caption)
                                .foregroundStyle(WK.Palette.accent)
                        }
                        .buttonStyle(WKPressStyle())
                    }
                    // **El motivo, no una frase de relleno.**
                    //
                    // Aquí ponía siempre "el recorte es la foto real", que es
                    // verdad pero no dice nada: no distingue "no hay red" de
                    // "el servidor la rechazó por no fiel", que piden cosas
                    // distintas.
                    Text(candidate.catalogFailure ?? "Versión de tienda, reconstruida.")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, WK.Spacing.l)
                }
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .photo:
            Image(decorative: photo, scale: 1)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: WK.Radius.card, style: .continuous))
                .transition(.opacity)
        }
    }
}
