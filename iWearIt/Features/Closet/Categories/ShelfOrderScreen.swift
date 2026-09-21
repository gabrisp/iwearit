import SwiftData
import SwiftUI
import WKDesign
import WKPersistence

/// Reordenar, renombrar, ocultar y borrar baldas.
///
/// Sin `List`: la lista reordenable es propia, así que se ve como el resto de
/// la app en vez de traer su fondo y sus separadores.
///
/// Las baldas semilla se pueden renombrar, mover y ocultar, pero **no borrar**:
/// son el destino de respaldo cuando ninguna balda propia supera el umbral de
/// similitud, y sin ellas una prenda podría quedarse sin sitio.
struct ShelfOrderScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\GarmentCategory.sortOrder)])
    private var categories: [GarmentCategory]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WK.Spacing.s) {
                Text("Mantén pulsada una balda para moverla.")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
                    .padding(.horizontal, WK.Spacing.cardInset)

                VStack(spacing: 0) {
                    WKReorderableList(items: categories, rowHeight: 58, onMove: move) { category in
                        ShelfOrderRow(
                            category: category,
                            isLast: category.id == categories.last?.id,
                            onDelete: { delete(category) }
                        )
                    }
                }
                .wkCard()
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas.ignoresSafeArea())
        .adaptiveSafeAreaBar(edge: .top) {
            HStack {
                Text("Baldas").font(WK.Font.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(WK.Font.headline)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .frame(width: 34, height: 34)
                        .background(WK.Palette.ink(0.07), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(WKPressStyle())
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.vertical, WK.Spacing.s)
        }
    }

    /// Reescribe `sortOrder` de forma densa tras mover.
    ///
    /// Aquí sí se reindexa, al revés que en el canvas: el orden de las baldas
    /// es una lista que el usuario controla, no una transformada que haya que
    /// conservar exacta.
    private func move(from source: Int, to destination: Int) {
        var reordered = categories
        let item = reordered.remove(at: source)
        reordered.insert(item, at: min(destination, reordered.count))
        for (index, category) in reordered.enumerated() {
            category.sortOrder = index
        }
    }

    private func delete(_ category: GarmentCategory) {
        guard !category.isBuiltIn else { return }
        withAnimation(WKAnimation.content) { modelContext.delete(category) }
    }
}

private struct ShelfOrderRow: View {
    @Bindable var category: GarmentCategory
    let isLast: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: WK.Spacing.m) {
                Image(systemName: "line.3.horizontal")
                    .font(.footnote)
                    .foregroundStyle(WK.Palette.tertiaryText)

                TextField("Nombre", text: $category.name)
                    .font(WK.Font.rowTitle)
                    .textFieldStyle(.plain)

                Button {
                    category.isHidden.toggle()
                } label: {
                    Image(systemName: category.isHidden ? "eye.slash" : "eye")
                        .foregroundStyle(WK.Palette.secondaryText)
                        .frame(width: 40, height: 40)
                        .contentShape(.rect)
                }
                .buttonStyle(WKPressStyle())

                if !category.isBuiltIn {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                            .frame(width: 40, height: 40)
                            .contentShape(.rect)
                    }
                    .buttonStyle(WKPressStyle())
                }
            }
            .padding(.horizontal, WK.Spacing.cardInset)
            .frame(maxHeight: .infinity)

            if !isLast {
                Rectangle()
                    .fill(WK.Palette.ink(0.07))
                    .frame(height: 1)
                    .padding(.leading, WK.Spacing.cardInset)
            }
        }
    }
}
