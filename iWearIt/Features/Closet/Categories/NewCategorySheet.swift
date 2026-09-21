import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Crear una balda propia, paso a paso.
///
/// Nombre primero, ejemplos después. El orden importa: marcar prendas sin saber
/// cómo se va a llamar la balda es marcar a ciegas.
struct NewCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(sort: [SortDescriptor(\GarmentCategory.sortOrder)])
    private var categories: [GarmentCategory]

    @State private var flow = WKFlowStack(Step.name)
    @State private var name = ""
    @State private var selectedExamples: Set<UUID> = []

    enum Step: Int, WKFlowStep {
        case name, examples
        var flowDepth: Int { rawValue }
    }

    var body: some View {
        Group {
            switch flow.step {
            case .name: nameStep
            case .examples: examplesStep
            }
        }
        .wkDynamicSheet()
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var nameStep: some View {
        WKFlowScreen(
            title: "¿Cómo se llama?",
            subtitle: "Gorras, ropa de running, lo que te sirva a ti.",
            stepID: Step.name,
            transition: flow.transition,
            primaryTitle: "Siguiente",
            isPrimaryEnabled: !trimmedName.isEmpty,
            isAtRoot: flow.isAtRoot,
            onLeading: { dismiss() },
            onPrimary: { flow.move(to: .examples) }
        ) {
            TextField("Nombre de la balda", text: $name)
                .font(WK.Font.title)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .padding(WK.Spacing.m)
                .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))
        }
    }

    private var examplesStep: some View {
        WKFlowScreen(
            title: "Enséñame cuáles van aquí",
            subtitle: "Marca al menos \(GarmentCategory.minimumExamplesForCentroid). Con menos no me puedo fiar de lo que aprenda.",
            stepID: Step.examples,
            transition: flow.transition,
            primaryTitle: selectedExamples.isEmpty ? "Crear vacía" : "Crear con \(selectedExamples.count)",
            isAtRoot: false,
            onLeading: { flow.move(to: .name) },
            onPrimary: { create() }
        ) {
            ExamplePicker(selection: $selectedExamples)
                .frame(maxHeight: 320)
        }
    }

    private func create() {
        let category = GarmentCategory(
            slug: UUID().uuidString,
            name: trimmedName,
            isBuiltIn: false,
            sortOrder: (categories.map(\.sortOrder).max() ?? 0) + 1,
            symbolName: "square.grid.2x2"
        )
        modelContext.insert(category)

        if let all = try? modelContext.fetch(FetchDescriptor<Garment>()) {
            let chosen = all.filter { selectedExamples.contains($0.id) }
            for garment in chosen {
                // Mover a mano bloquea la prenda: son la verdad de referencia
                // de esta balda y la auto-clasificación no debe reasignarlas.
                garment.category = category
                garment.categoryLockedByUser = true
            }
            // El centroide se guarda como **media sin normalizar**: normalizar
            // pierde la magnitud, y sin ella la actualización incremental pesa
            // mal lo anterior y el centroide va derivando con cada alta.
            let vectors = chosen.compactMap { $0.embedding.map(EmbeddingMath.decode) }
            if let mean = EmbeddingMath.mean(of: vectors) {
                category.centroidEmbedding = EmbeddingMath.encode(mean)
            }
            category.memberCountAtCentroid = chosen.count
            category.autoAssignEnabled = chosen.count >= GarmentCategory.minimumExamplesForCentroid
        }
        dismiss()
    }
}

/// Rejilla para marcar prendas de ejemplo.
private struct ExamplePicker: View {
    @Binding var selection: Set<UUID>
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(sort: [SortDescriptor(\Garment.dateAdded, order: .reverse)])
    private var garments: [Garment]

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72), spacing: WK.Spacing.s)],
                spacing: WK.Spacing.s
            ) {
                ForEach(garments) { garment in
                    ExampleCell(
                        garment: garment,
                        isSelected: selection.contains(garment.id),
                        store: appEnvironment.imageStore
                    ) {
                        if selection.contains(garment.id) {
                            selection.remove(garment.id)
                        } else {
                            selection.insert(garment.id)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct ExampleCell: View {
    let garment: Garment
    let isSelected: Bool
    let store: ImageStore
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            StoredImage(
                key: garment.normalizedImageKey,
                variant: .thumb,
                store: store,
                // Seleccionada = halo con la forma de la prenda. Sin rectángulo:
                // una prenda recortada no es rectangular, y la caja se ve como
                // lo que es, algo ajeno puesto encima.
                shadow: isSelected
                    ? .init(opacity: 0.85, radius: 10, y: 0, tint: WK.Palette.accent)
                    : .init(opacity: 0.5, radius: 6, y: 3)
            )
            .frame(width: 72, height: 72)
            .padding(WK.Spacing.xs)
            .scaleEffect(isSelected ? 1.08 : 1)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(WK.Palette.onAccent, WK.Palette.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(WKAnimation.selection, value: isSelected)
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}
