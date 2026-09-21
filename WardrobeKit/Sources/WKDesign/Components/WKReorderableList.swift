import SwiftUI

/// Lista que se reordena arrastrando, sin `List`.
///
/// `List` traía `.onMove` gratis, pero también su fondo, sus separadores, sus
/// márgenes y su modo de edición — cuatro cosas que había que combatir para que
/// se pareciera al resto de la app.
///
/// Aquí el gesto arranca con una pulsación mantenida y no con el primer
/// contacto: si empezara al tocar, no se podría hacer scroll en la lista sin
/// arrastrar una fila sin querer.
public struct WKReorderableList<Item: Identifiable & Equatable, Row: View>: View {
    private let items: [Item]
    private let rowHeight: CGFloat
    private let onMove: (Int, Int) -> Void
    private let row: (Item) -> Row

    @State private var draggingID: Item.ID?
    @State private var dragOffset: CGFloat = 0
    /// Cuántas posiciones se ha desplazado ya la fila que se arrastra.
    @State private var shift = 0

    public init(
        items: [Item],
        rowHeight: CGFloat = 56,
        onMove: @escaping (Int, Int) -> Void,
        @ViewBuilder row: @escaping (Item) -> Row
    ) {
        self.items = items
        self.rowHeight = rowHeight
        self.onMove = onMove
        self.row = row
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isDragging = draggingID == item.id
                row(item)
                    .frame(height: rowHeight)
                    .background(isDragging ? WK.Palette.shelf : .clear)
                    .clipShape(.rect(cornerRadius: isDragging ? WK.Radius.medium : 0))
                    .shadow(color: WK.Palette.ink(isDragging ? 0.18 : 0), radius: 12, y: 4)
                    .scaleEffect(isDragging ? 1.02 : 1)
                    .offset(y: offset(for: index, isDragging: isDragging))
                    .zIndex(isDragging ? 1 : 0)
                    .gesture(gesture(for: index, id: item.id))
                    .animation(WKAnimation.selection, value: draggingID)
                    .animation(isDragging ? nil : WKAnimation.selection, value: shift)
            }
        }
    }

    /// Dónde se dibuja cada fila mientras hay un arrastre en curso.
    ///
    /// La que se arrastra sigue al dedo; las demás se apartan una posición
    /// **solo si el hueco pasa por encima de ellas**. Sin eso, la lista se
    /// reordenaría de golpe al final en vez de ir enseñando dónde va a caer.
    private func offset(for index: Int, isDragging: Bool) -> CGFloat {
        guard let draggingID, let from = items.firstIndex(where: { $0.id == draggingID }) else {
            return 0
        }
        if isDragging { return dragOffset }

        let to = from + shift
        if from < to, index > from, index <= to { return -rowHeight }
        if from > to, index < from, index >= to { return rowHeight }
        return 0
    }

    private func gesture(for index: Int, id: Item.ID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .onEnded { _ in
                draggingID = id
                dragOffset = 0
                shift = 0
            }
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case let .second(_, drag?) = value, draggingID == id else { return }
                dragOffset = drag.translation.height
                shift = Int((drag.translation.height / rowHeight).rounded())
                shift = max(-index, min(items.count - 1 - index, shift))
            }
            .onEnded { _ in
                guard draggingID == id else { return }
                if shift != 0 { onMove(index, index + shift) }
                withAnimation(WKAnimation.selection) {
                    draggingID = nil
                    dragOffset = 0
                    shift = 0
                }
            }
    }
}
