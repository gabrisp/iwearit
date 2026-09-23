import SwiftUI

/// Hoja de selección por chips.
///
/// La misma para tipo, etiquetas y calidez: son la misma pregunta con distinto
/// vocabulario, y escribir tres hojas parecidas garantiza que dos acaben
/// comportándose distinto.
///
/// Sin botón de confirmar: tocar un chip **es** la acción. En selección única
/// la hoja se cierra sola; en múltiple se queda abierta porque hace falta
/// seguir tocando.
public struct WKChipSheet: View {
    public struct Option: Identifiable, Hashable, Sendable {
        public let id: String
        public let label: String

        public init(id: String, label: String) {
            self.id = id
            self.label = label
        }
    }

    private let title: String
    private let subtitle: String
    private let options: [Option]
    private let limit: Int?
    /// Si se puede escribir un valor que no está en la lista.
    private let allowsCustom: Bool
    /// Si se puede quedar **sin nada elegido** tocando lo ya elegido.
    ///
    /// Para lo que de verdad puede no aplicar: hay prendas que no son de
    /// ninguna temporada en concreto.
    private let allowsEmpty: Bool
    @Binding private var selection: Set<String>
    @State private var custom = ""

    @Environment(\.dismiss) private var dismiss

    /// - Parameter limit: máximo de opciones a la vez. `1` cierra al elegir.
    public init(
        title: String,
        subtitle: String,
        options: [Option],
        selection: Binding<Set<String>>,
        limit: Int? = nil,
        allowsCustom: Bool = false,
        allowsEmpty: Bool = false
    ) {
        self.allowsCustom = allowsCustom
        self.allowsEmpty = allowsEmpty
        self.title = title
        self.subtitle = subtitle
        self.options = options
        _selection = selection
        self.limit = limit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.m) {
            VStack(alignment: .leading, spacing: WK.Spacing.xs) {
                Text(title)
                    .font(WK.Font.title)
                    .foregroundStyle(WK.Palette.primaryText)
                Text(subtitle)
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.secondaryText)
            }

            WKChipFlow(options: shownOptions, selection: selection) { toggle($0) }

            // **Uno propio.** Las listas se quedan cortas en cuanto cada
            // armario llama a las cosas a su manera: un "jort" no está en
            // ninguna lista hasta que alguien lo escribe.
            if allowsCustom {
                TextField("Otro…", text: $custom)
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.primaryText)
                    .padding(.horizontal, WK.Spacing.m)
                    .padding(.vertical, WK.Spacing.s + 2)
                    .background(WK.Palette.ink(0.06), in: .capsule)
                    .submitLabel(.done)
                    .onSubmit {
                        let value = custom.trimmingCharacters(in: .whitespaces)
                        guard !value.isEmpty else { return }
                        custom = ""
                        toggle(value.capitalized)
                    }
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .wkDynamicSheet()
    }

    /// Las opciones, más la elegida si es una escrita a mano: si no, el valor
    /// propio desaparecería de la hoja la próxima vez que se abriera.
    private var shownOptions: [Option] {
        let extra = selection
            .filter { id in !id.isEmpty && !options.contains { $0.id == id } }
            .map { Option(id: $0, label: $0) }
        return options + extra
    }

    private func toggle(_ id: String) {
        withAnimation(WKAnimation.selection) {
            if selection.contains(id) {
                // En selección única no se deselecciona —dejar la prenda sin
                // tipo al tocar el que ya estaba es un accidente, no una
                // intención— salvo donde no elegir nada significa algo. Ver
                // `allowsEmpty`.
                if limit != 1 || allowsEmpty { selection.remove(id) }
            } else {
                if limit == 1 {
                    selection = [id]
                } else if let limit, selection.count >= limit {
                    // Al llegar al tope, el nuevo sustituye al más antiguo en
                    // vez de no hacer nada. Un chip que no responde se lee como
                    // una app rota, no como un límite.
                    selection.removeFirst()
                    selection.insert(id)
                } else {
                    selection.insert(id)
                }
            }
        }
        if limit == 1 { dismiss() }
    }
}

/// Chips que fluyen a varias líneas.
///
/// Con `Layout` propio y no con `LazyVGrid`: una rejilla da a todos los chips
/// el mismo ancho, y "Y2K" junto a "Experimental" en columnas iguales deja
/// huecos enormes.
public struct WKChipFlow: View {
    private let options: [WKChipSheet.Option]
    private let selection: Set<String>
    private let onTap: (String) -> Void

    public init(
        options: [WKChipSheet.Option],
        selection: Set<String>,
        onTap: @escaping (String) -> Void
    ) {
        self.options = options
        self.selection = selection
        self.onTap = onTap
    }

    public var body: some View {
        FlowLayout(spacing: WK.Spacing.s) {
            ForEach(options) { option in
                let isSelected = selection.contains(option.id)
                Button { onTap(option.id) } label: {
                    Text(option.label)
                        .font(WK.Font.callout)
                        .foregroundStyle(isSelected ? WK.Palette.onAccent : WK.Palette.primaryText)
                        .padding(.horizontal, WK.Spacing.m)
                        .padding(.vertical, WK.Spacing.s + 2)
                        .background(
                            isSelected ? WK.Palette.accent : WK.Palette.ink(0.06),
                            in: .capsule
                        )
                        .contentShape(.capsule)
                }
                .buttonStyle(WKPressStyle())
            }
        }
    }
}

/// Coloca los hijos en fila y salta de línea cuando no caben.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rows[rows.count - 1] + size.width > width, rows[rows.count - 1] > 0 {
                height += rowHeight + spacing
                rows.append(0)
                rowHeight = 0
            }
            rows[rows.count - 1] += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: height + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
