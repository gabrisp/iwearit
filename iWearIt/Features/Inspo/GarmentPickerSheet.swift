import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Elegir prendas del armario, **encontrándolas**.
///
/// ## Qué tenía de malo la rejilla a secas
///
/// Con treinta prendas se ve todo de un vistazo y una rejilla basta. Con
/// trescientas, elegir "esas zapatillas blancas" es bajar y bajar mirando
/// miniaturas de cinco centímetros: la pantalla enseñaba el armario entero y
/// te dejaba a ti la búsqueda.
///
/// ## Cómo se busca aquí
///
/// Por las mismas dos cosas por las que uno busca en su armario: **dónde está**
/// —la balda— y **qué es** —el nombre—. Una fila de píldoras con las baldas que
/// de verdad tienen ropa, y un campo para escribir. Nada de filtros
/// combinables por color y temporada: para coger dos prendas, cada filtro de
/// más es una decisión de más.
struct GarmentPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment

    let title: String
    /// Cuántas se pueden marcar. Al llegar al tope, la más antigua deja su
    /// sitio: seguir tocando nunca se queda sin efecto.
    var limit: Int = 3
    let initial: Set<UUID>
    let onDone: (Set<UUID>) -> Void

    @Query(FetchDescriptor<Garment>.visibleGarments())
    private var garments: [Garment]

    @Query(
        filter: #Predicate<GarmentCategory> { !$0.isHidden && $0.deletedAt == nil },
        sort: [SortDescriptor(\GarmentCategory.sortOrder)]
    )
    private var categories: [GarmentCategory]

    @State private var picked: Set<UUID> = []
    @State private var shelf: String?
    @State private var search = ""

    /// Las baldas con algo dentro y sin repetir slug: con sincronización
    /// pueden llegar dos filas de la misma. Ver `ClosetScreen`.
    private var shelves: [GarmentCategory] {
        var seen = Set<String>()
        return categories.filter { seen.insert($0.slug).inserted && !$0.visibleGarments.isEmpty }
    }

    private var visible: [Garment] {
        var result = garments
        if let shelf { result = result.filter { $0.category?.slug == shelf } }
        let needle = search.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty {
            result = result.filter { garment in
                garment.name.localizedStandardContains(needle)
                    || (garment.subcategory ?? "").localizedStandardContains(needle)
            }
        }
        // Lo marcado, siempre delante: si filtras después de elegir, lo que ya
        // tienes cogido no puede desaparecer de la pantalla.
        return result.sorted { picked.contains($0.id) && !picked.contains($1.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: WK.Spacing.m)],
                    spacing: WK.Spacing.l
                ) {
                    ForEach(visible) { garment in
                        PickableGarment(
                            garment: garment,
                            store: appEnvironment.imageStore,
                            isPicked: picked.contains(garment.id)
                        ) {
                            toggle(garment)
                        }
                    }
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.vertical, WK.Spacing.m)
                .animation(WKAnimation.content, value: shelf)
            }
            .scrollIndicators(.hidden)
            .background(WK.Palette.canvas.ignoresSafeArea())
            .overlay {
                if visible.isEmpty {
                    Text("Nada con ese filtro")
                        .font(WK.Font.caption)
                        .foregroundStyle(WK.Palette.secondaryText)
                }
            }
            // Las baldas arriba, pegadas a la barra: es el primer corte que
            // hace cualquiera —"de las camisetas"— y deja la rejilla en un
            // puñado de prendas.
            .safeAreaInset(edge: .top) { shelfBar }
            .searchable(text: $search, prompt: "Buscar una prenda")
            .navigationTitle(picked.isEmpty ? title : "\(picked.count) de \(limit)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(WK.Palette.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onDone(picked)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .tint(WK.Palette.primaryText)
                    .adaptiveProminentButton()
                }
            }
        }
        .task { picked = initial }
    }

    private var shelfBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.s) {
                ShelfChip(label: "Todo", isSelected: shelf == nil) { shelf = nil }
                ForEach(shelves) { category in
                    ShelfChip(
                        label: category.name,
                        isSelected: shelf == category.slug
                    ) {
                        shelf = shelf == category.slug ? nil : category.slug
                    }
                }
            }
            .padding(.vertical, WK.Spacing.xs)
        }
        .scrollIndicators(.hidden)
        .safeAreaPadding(.horizontal, WK.Spacing.screenInset)
        .scrollClipDisabled()
        .background(.clear)
    }

    private func toggle(_ garment: Garment) {
        withAnimation(WKAnimation.selection) {
            if picked.contains(garment.id) {
                picked.remove(garment.id)
            } else {
                if picked.count >= limit, let first = picked.first { picked.remove(first) }
                picked.insert(garment.id)
            }
        }
    }
}

/// Una balda como píldora. La misma pinta que el resto de filtros de la app.
private struct ShelfChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(WK.Font.caption)
                .foregroundStyle(isSelected ? WK.Palette.onAccent : WK.Palette.primaryText)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .background {
                    if isSelected {
                        Capsule().fill(WK.Palette.accent)
                    } else {
                        Capsule().fill(WK.Palette.ink(0.06))
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
    }
}

/// Una prenda que se puede marcar. Sin recuadro: se marca como dentro de una
/// balda, creciendo y con el check.
private struct PickableGarment: View {
    let garment: Garment
    let store: ImageStore
    let isPicked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            StoredImage(
                key: garment.normalizedImageKey,
                variant: .thumb,
                store: store,
                alignment: .bottom,
                shadow: isPicked
                    ? .init(opacity: 0.85, radius: 12, y: 0, tint: WK.Palette.accent)
                    : .init(opacity: 0.5, radius: 6, y: 3)
            )
            .frame(height: 104)
            .scaleEffect(isPicked ? 1 : 0.88)
            .overlay(alignment: .topTrailing) {
                if isPicked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WK.Palette.onAccent)
                        .frame(width: 24, height: 24)
                        .background(WK.Palette.accent, in: .circle)
                }
            }
            .animation(WKAnimation.selection, value: isPicked)
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}
