import SwiftUI

/// Rueda de selección.
///
/// Un `ScrollView` cuya fila centrada es la selección, con el resto
/// inclinándose y difuminándose al alejarse. No es una pila de botones:
/// **seleccionar es desplazar**, que es lo que permite recorrer una lista larga
/// con un gesto en lugar de con veinte toques.
public struct WKWheelPicker<Item: Hashable, Row: View>: View {
    private let items: [Item]
    private let rowHeight: CGFloat
    private let row: (Item) -> Row
    @Binding private var selection: Item?

    @State private var measuredHeight: CGFloat = 0
    /// Hasta que la rueda no se ha desplazado a la selección recibida, la
    /// posición es la que la disposición haya dejado —la primera fila— y
    /// dejarla escribir sobrescribiría la elección del llamante.
    @State private var hasSettled = false

    public init(
        items: [Item],
        selection: Binding<Item?>,
        rowHeight: CGFloat = 54,
        @ViewBuilder row: @escaping (Item) -> Row
    ) {
        self.items = items
        _selection = selection
        self.rowHeight = rowHeight
        self.row = row
    }

    private var verticalMargin: CGFloat {
        max(0, (measuredHeight - rowHeight) / 2)
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(items, id: \.self) { item in
                        row(item)
                            .frame(maxWidth: .infinity)
                            .frame(height: rowHeight)
                            .id(item)
                            // `phase.value` va de -1 a 1 a lo largo del
                            // viewport, así que sirve tal cual para inclinar:
                            // las filas se alejan del centro girando sobre el
                            // eje X y difuminándose, que es lo que hace que un
                            // scroll plano se lea como una rueda.
                            .scrollTransition(.interactive, axis: .vertical) { content, phase in
                                content
                                    .opacity(1 - abs(phase.value) * 0.7)
                                    .rotation3DEffect(
                                        .degrees(phase.value * 42),
                                        axis: (x: 1, y: 0, z: 0)
                                    )
                                    .blur(radius: abs(phase.value) * 1.6)
                            }
                            .onTapGesture { withAnimation { selection = item } }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.vertical, verticalMargin, for: .scrollContent)
            .scrollPosition(id: Binding(
                get: { selection },
                set: { newValue in
                    guard hasSettled, let newValue else { return }
                    selection = newValue
                }
            ), anchor: .center)
            .background {
                Capsule()
                    .fill(WK.Palette.ink(0.06))
                    .frame(height: rowHeight)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredHeight = $0 }
            .task(id: items) {
                hasSettled = false
                // Un turno de runloop para que las filas existan: un LazyVStack
                // no las ha construido cuando la vista aparece.
                try? await Task.sleep(for: .milliseconds(60))
                if let selection { proxy.scrollTo(selection, anchor: .center) }
                hasSettled = true
            }
            .sensoryFeedback(.selection, trigger: selection)
        }
    }
}
