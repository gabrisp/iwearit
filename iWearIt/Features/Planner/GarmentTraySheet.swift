import SwiftData
import SwiftUI
import WKDesign
import WKPersistence

/// Bandeja para elegir una prenda del armario.
///
/// Se presenta baja por defecto para que el canvas siga a la vista mientras
/// eliges: montar un outfit es comparar, y tapar el lienzo entero lo impide.
struct GarmentTraySheet: View {
    let onPick: (Garment) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(FetchDescriptor<GarmentCategory>.visibleCategories())
    private var categories: [GarmentCategory]

    @Query(FetchDescriptor<Garment>.visibleGarments())
    private var garments: [Garment]

    @State private var selectedSlug: String?

    private var visible: [Garment] {
        guard let selectedSlug else { return garments }
        return garments.filter { $0.category?.slug == selectedSlug }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CategoryFilterBar(
                    categories: categories.map { ($0.slug, $0.name) },
                    selectedSlug: $selectedSlug
                )
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 88), spacing: WK.Spacing.m)],
                        spacing: WK.Spacing.m
                    ) {
                        ForEach(visible) { garment in
                            TrayCell(garment: garment, store: appEnvironment.imageStore) {
                                onPick(garment)
                                dismiss()
                            }
                        }
                    }
                    .padding(WK.Spacing.m)
                }
                .scrollIndicators(.hidden)
            }
            .background(WK.Palette.canvas)
            .navigationTitle("Añadir prenda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Un símbolo, nunca texto. Ver `ClosetBulkEditSheet`.
                    // Button("Cerrar") { dismiss() }
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(WK.Font.headline)
                            .contentShape(.rect)
                    }
                }
            }
        }
        .presentationDetents([.height(320), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(320)))
    }
}

/// Filtro por balda. Recibe tuplas POD, no los modelos.
private struct CategoryFilterBar: View {
    let categories: [(slug: String, name: String)]
    @Binding var selectedSlug: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.s) {
                FilterChip(title: "Todo", isSelected: selectedSlug == nil) {
                    selectedSlug = nil
                }
                ForEach(categories, id: \.slug) { category in
                    FilterChip(title: category.name, isSelected: selectedSlug == category.slug) {
                        selectedSlug = category.slug
                    }
                }
            }
            .padding(.horizontal, WK.Spacing.m)
            .padding(.vertical, WK.Spacing.s)
        }
        .scrollIndicators(.hidden)
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.subheadline)
            .padding(.horizontal, WK.Spacing.m)
            .padding(.vertical, WK.Spacing.xs + 2)
            .background {
                if isSelected {
                    Capsule().fill(WK.Palette.accent)
                } else {
                    Capsule().fill(WK.Palette.shelf)
                }
            }
            .foregroundStyle(isSelected ? WK.Palette.onAccent : WK.Palette.primaryText)
            .contentShape(.capsule)
            .buttonStyle(WKPressStyle())
    }
}

private struct TrayCell: View {
    let garment: Garment
    let store: ImageStore
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: WK.Spacing.xs) {
                StoredImage(key: garment.normalizedImageKey, variant: .thumb, store: store)
                    .frame(width: 88, height: 96)
                Text(garment.name)
                    .font(.caption2)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .lineLimit(1)
                    .frame(width: 88)
            }
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}
